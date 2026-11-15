import Foundation

public enum RequestKind: String, Codable, Sendable { case permission, question, plan }

public struct QuestionOption: Equatable, Sendable {
    public var label: String
    public var detail: String?
}

public struct Question: Equatable, Sendable {
    public var question: String
    public var header: String?
    public var options: [QuestionOption]
    public var multiSelect: Bool
}

/// What the approval card shows for a tool call.
public enum RequestDetail: Equatable, Sendable {
    case command(String, note: String?)
    case edit(path: String, old: String, new: String)
    case write(path: String, content: String)
    case generic(String)
}

/// Something an agent is blocked on that the user can answer from the panel.
public struct PendingRequest: Identifiable, Equatable, Sendable {
    public let id: String
    public let sessionID: String
    public let kind: RequestKind
    public let hookEvent: String
    public let tool: String
    public let input: JSONValue
    public let cwd: String?
    public let suggestions: [JSONValue]
    public let receivedAt: Date

    /// Nil when the event is not something the panel answers (the caller then passes it through).
    public init?(envelope: Envelope, id: String = UUID().uuidString, now: Date = Date()) {
        let p = envelope.payload
        guard let session = envelope.sessionID, let tool = p["tool_name"]?.string else { return nil }
        switch (envelope.event, tool) {
        case ("PreToolUse", "AskUserQuestion"): kind = .question
        case ("PermissionRequest", "AskUserQuestion"): return nil   // already offered at PreToolUse
        case ("PermissionRequest", "ExitPlanMode"): kind = .plan
        case ("PermissionRequest", _): kind = .permission
        default: return nil
        }
        self.id = id
        self.sessionID = session
        self.hookEvent = envelope.event
        self.tool = tool
        self.input = p["tool_input"] ?? .object([:])
        self.cwd = p["cwd"]?.string
        self.suggestions = p["permission_suggestions"]?.array ?? []
        self.receivedAt = now
    }

    public var projectName: String {
        guard let cwd, !cwd.isEmpty else { return "Unknown" }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    /// Short headline, e.g. "Run a command" or "Edit routes.ts".
    public var title: String {
        switch kind {
        case .question: return "Question"
        case .plan: return "Plan ready for review"
        case .permission:
            switch tool {
            case "Bash": return "Run a command"
            case "Edit", "MultiEdit", "NotebookEdit":
                return "Edit " + Activity.base(input["file_path"]?.string ?? input["notebook_path"]?.string)
            case "Write": return "Write " + Activity.base(input["file_path"]?.string)
            case "Read": return "Read " + Activity.base(input["file_path"]?.string)
            case "WebFetch": return "Fetch " + (input["url"]?.string.flatMap { URL(string: $0)?.host } ?? "a page")
            default: return "Use " + Activity.describe(tool: tool, input: input)
            }
        }
    }

    public var detail: RequestDetail {
        switch tool {
        case "Bash":
            return .command(input["command"]?.string ?? "", note: input["description"]?.string)
        case "Edit":
            return .edit(path: input["file_path"]?.string ?? "", old: input["old_string"]?.string ?? "",
                         new: input["new_string"]?.string ?? "")
        case "Write":
            return .write(path: input["file_path"]?.string ?? "", content: input["content"]?.string ?? "")
        default:
            return .generic(HookResponse.encode(input, pretty: true))
        }
    }

    /// Only "add an allow rule" suggestions are offered as "Always allow"; mode changes and
    /// directory grants are never applied on the user's behalf.
    public var alwaysAllowUpdates: [JSONValue] {
        suggestions.filter { $0["type"]?.string == "addRules" && $0["behavior"]?.string == "allow" }
    }

    /// Human form of the rules "Always allow" would add, e.g. "Bash(npm test:*)".
    public var alwaysAllowLabel: String? {
        let rules = alwaysAllowUpdates.flatMap { $0["rules"]?.array ?? [] }.compactMap { rule -> String? in
            guard let name = rule["toolName"]?.string else { return nil }
            if let content = rule["ruleContent"]?.string, !content.isEmpty { return "\(name)(\(content))" }
            return name
        }
        return rules.isEmpty ? nil : rules.joined(separator: ", ")
    }

    public var questions: [Question] {
        (input["questions"]?.array ?? []).compactMap { q in
            guard let text = q["question"]?.string else { return nil }
            let options = (q["options"]?.array ?? []).compactMap { o -> QuestionOption? in
                guard let label = o["label"]?.string else { return nil }
                return QuestionOption(label: label, detail: o["description"]?.string)
            }
            return Question(question: text, header: q["header"]?.string, options: options,
                            multiSelect: q["multiSelect"]?.bool ?? false)
        }
    }

    public var plan: String? { input["plan"]?.string }

    /// True when a later event shows this request was settled somewhere else (e.g. in the terminal).
    public func isResolved(by envelope: Envelope) -> Bool {
        guard envelope.sessionID == sessionID else { return false }
        switch envelope.event {
        case "Stop", "StopFailure", "UserPromptSubmit", "SessionEnd":
            return true
        case "PostToolUse", "PostToolUseFailure":
            return envelope.payload["tool_name"]?.string == tool && envelope.payload["tool_input"] == input
        case "PermissionDenied":
            return envelope.payload["tool_name"]?.string == tool
        default:
            return false
        }
    }
}

/// Makes text safe to show on an approval card: characters that are invisible or that reorder the
/// text on screen are replaced with a visible marker, so what you read is what will run.
public enum TextSafety {
    /// Characters that look like nothing (or like a space) but are not a plain space.
    static let blankLookalikes: Set<UInt32> = [0x115F, 0x1160, 0x3164, 0xFFA0, 0x2800, 0x034F]

    public static func visible(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        var marksInARow = 0
        for scalar in text.unicodeScalars {
            let v = scalar.value
            let props = scalar.properties
            var flag = false
            switch props.generalCategory {
            case .control: flag = v != 0x0A && v != 0x09
            case .format, .lineSeparator, .paragraphSeparator, .privateUse, .unassigned, .surrogate: flag = true
            case .spaceSeparator: flag = v != 0x20          // non-breaking and other look-alike spaces
            default: break
            }
            if props.isDefaultIgnorableCodePoint || blankLookalikes.contains(v) || (0xE0000...0xE007F).contains(v) { flag = true }
            // Stacks of combining marks can draw over neighbouring text; allow two, mark the rest.
            if props.generalCategory == .nonspacingMark || props.generalCategory == .enclosingMark {
                marksInARow += 1
                if marksInARow > 2 { flag = true }
            } else {
                marksInARow = 0
            }
            if flag {
                out.append(contentsOf: "⟨U+\(String(v, radix: 16, uppercase: true).leftPad(4))⟩".unicodeScalars)
            } else {
                out.append(scalar)
            }
        }
        return String(out)
    }
}

extension String {
    func leftPad(_ width: Int) -> String { count >= width ? self : String(repeating: "0", count: width - count) + self }
}

extension PendingRequest {
    /// Input keys the card already shows in its main area, per tool.
    static let primaryKeys: [String: Set<String>] = [
        "Bash": ["command", "description"],
        "Edit": ["file_path", "old_string", "new_string"],
        "Write": ["file_path", "content"],
    ]

    /// Every other input field, so nothing that affects the call is left off the card
    /// (for example a command's background or sandbox flags, or an edit's replace-all).
    public var otherFields: [(key: String, value: String)] {
        guard kind == .permission, let shown = Self.primaryKeys[tool], let fields = input.object else { return [] }
        return fields.keys.filter { !shown.contains($0) }.sorted().map { key in
            (key, fields[key]?.string ?? HookResponse.encode(fields[key] ?? .null))
        }
    }

    /// All the text a reviewer has to read for this request.
    /// Everything the card shows for this request, so the length check covers every field.
    var reviewText: String {
        var parts = [cwd ?? ""]
        switch kind {
        case .plan: parts.append(plan ?? "")
        case .question: break
        case .permission:
            switch detail {
            case .command(let c, let n): parts += [c, n ?? ""]
            case .edit(let path, let old, let new): parts += [path, old, new]
            case .write(let path, let content): parts += [path, content]
            case .generic(let json): parts.append(json)
            }
            parts += otherFields.map { "\($0.key) = \($0.value)" }
            parts.append(alwaysAllowLabel ?? "")
        }
        return parts.joined(separator: "\n")
    }

    public static let reviewLineLimit = 400
    public static let reviewCharacterLimit = 40_000

    /// Too much to read in a small panel. Such requests can be denied or sent to the terminal from
    /// the card, but not allowed.
    public var isTooLongToReview: Bool {
        let text = reviewText
        if text.utf8.count > Self.reviewCharacterLimit { return true }
        return text.utf8.reduce(0) { $1 == 0x0A ? $0 + 1 : $0 } >= Self.reviewLineLimit
    }

    /// Where "Always allow" would save its rule, in plain words.
    public var alwaysAllowDestination: String? {
        guard let raw = alwaysAllowUpdates.first?["destination"]?.string else { return nil }
        switch raw {
        case "session": return "this session only"
        case "localSettings": return "this project, on this Mac"
        case "projectSettings": return "this project, for everyone"
        case "userSettings": return "all your projects"
        default: return raw
        }
    }

    public var workingDirectory: String {
        guard let cwd, !cwd.isEmpty else { return "Unknown folder" }
        let home = NSHomeDirectory()
        return cwd.hasPrefix(home) ? "~" + cwd.dropFirst(home.count) : cwd
    }
}

public enum Decision: Equatable, Sendable {
    case allow
    case alwaysAllow
    case deny(message: String?)
    case answers([String: String])
    /// Let the agent's own prompt handle it.
    case terminal

    /// The reply the bridge prints for the agent.
    public func reply(for request: PendingRequest) -> Reply {
        switch (request.kind, self) {
        case (_, .terminal):
            return .passthroughReply
        case (.question, .answers(let answers)):
            return Reply(stdout: HookResponse.answer(input: request.input, answers: answers))
        case (.question, _):
            return .passthroughReply
        case (_, .allow):
            return Reply(stdout: HookResponse.allow())
        case (_, .alwaysAllow):
            return Reply(stdout: HookResponse.allow(updatedPermissions: request.alwaysAllowUpdates))
        case (_, .deny(let message)):
            return Reply(stdout: HookResponse.deny(message: message))
        case (_, .answers):
            return .passthroughReply
        }
    }
}

/// Builds the exact JSON Claude Code expects on a hook's stdout.
public enum HookResponse {
    public static func encode(_ value: JSONValue, pretty: Bool = false) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
                                          : [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    static func permission(_ decision: [String: JSONValue]) -> String {
        encode(.object(["hookSpecificOutput": .object([
            "hookEventName": "PermissionRequest", "decision": .object(decision),
        ])]))
    }

    public static func allow(updatedPermissions: [JSONValue] = []) -> String {
        var decision: [String: JSONValue] = ["behavior": "allow"]
        if !updatedPermissions.isEmpty { decision["updatedPermissions"] = .array(updatedPermissions) }
        return permission(decision)
    }

    public static func deny(message: String?, interrupt: Bool = false) -> String {
        var decision: [String: JSONValue] = ["behavior": "deny"]
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        decision["message"] = .string(trimmed.isEmpty ? "Denied by the user." : trimmed)
        if interrupt { decision["interrupt"] = true }
        return permission(decision)
    }

    /// Answers an AskUserQuestion call from its PreToolUse hook: the original input plus an `answers` map.
    public static func answer(input: JSONValue, answers: [String: String]) -> String {
        var updated = input.object ?? [:]
        updated["answers"] = .object(answers.mapValues { .string($0) })
        return encode(.object(["hookSpecificOutput": .object([
            "hookEventName": "PreToolUse", "permissionDecision": "allow", "updatedInput": .object(updated),
        ])]))
    }
}
