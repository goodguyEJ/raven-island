import Foundation

public enum SessionState: String, Codable, Sendable, CaseIterable {
    case idle, working, needsApproval, waitingForInput, done, error

    /// Lower sorts first in the session list.
    public var sortRank: Int {
        switch self {
        case .needsApproval: return 0
        case .waitingForInput: return 1
        case .error: return 2
        case .working: return 3
        case .done: return 4
        case .idle: return 5
        }
    }

    public var needsAttention: Bool { self == .needsApproval || self == .waitingForInput }

    public var label: String {
        switch self {
        case .idle: return "Idle"
        case .working: return "Working"
        case .needsApproval: return "Needs approval"
        case .waitingForInput: return "Waiting for you"
        case .done: return "Done"
        case .error: return "Error"
        }
    }
}

/// What a working session is doing right now, in broad strokes. Drives which animation is shown.
public enum WorkKind: String, Codable, Sendable, CaseIterable {
    case thinking, searching, running, building

    /// The kind of work a tool call represents.
    public static func forTool(_ tool: String) -> WorkKind {
        switch tool {
        case "Read", "Grep", "Glob", "LS", "WebSearch", "WebFetch", "ToolSearch", "NotebookRead": return .searching
        case "Bash", "BashOutput", "KillShell": return .running
        case "Edit", "MultiEdit", "Write", "NotebookEdit", "Task", "Agent": return .building
        default:
            // Tools from connected services mostly look things up; names that say otherwise count as building.
            if tool.hasPrefix("mcp__") {
                let name = tool.lowercased()
                let changes = ["create", "update", "write", "edit", "delete", "send", "post", "add", "set", "upsert"]
                return changes.contains { name.contains($0) } ? .building : .searching
            }
            return .building
        }
    }

    public var label: String {
        switch self {
        case .thinking: return "Thinking"
        case .searching: return "Looking things up"
        case .running: return "Running a command"
        case .building: return "Building"
        }
    }
}

public struct Session: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public var agent: String
    public var cwd: String?
    public var title: String?
    public var state: SessionState
    public var stateSince: Date
    public var lastEventAt: Date
    public var activity: String?
    public var subagents: Int
    public var permissionMode: String?
    public var context: TerminalContext
    /// Cleared from the list by the user (or automatically once finished). The session is still
    /// tracked, and comes back as soon as it does something new.
    public var dismissed = false
    /// Only meaningful while `state` is working.
    public var workKind: WorkKind = .thinking

    public init(id: String, agent: String, cwd: String?, title: String?, state: SessionState,
                stateSince: Date, lastEventAt: Date, activity: String?, subagents: Int,
                permissionMode: String?, context: TerminalContext) {
        self.id = id; self.agent = agent; self.cwd = cwd; self.title = title; self.state = state
        self.stateSince = stateSince; self.lastEventAt = lastEventAt; self.activity = activity
        self.subagents = subagents; self.permissionMode = permissionMode; self.context = context
    }

    public var projectName: String {
        guard let cwd, !cwd.isEmpty else { return "Unknown" }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }
}

public enum Activity {
    static func firstLine(_ s: String, max: Int = 80) -> String {
        let line = s.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count > max ? String(trimmed.prefix(max - 1)) + "…" : trimmed
    }

    static func base(_ path: String?) -> String {
        guard let path, !path.isEmpty else { return "file" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    /// One short human line for a tool call.
    public static func describe(tool: String, input: JSONValue?) -> String {
        let i = input ?? .null
        switch tool {
        case "Bash": return "Running: " + firstLine(i["command"]?.string ?? "command")
        case "Edit", "MultiEdit", "Write", "NotebookEdit":
            return "Editing " + base(i["file_path"]?.string ?? i["notebook_path"]?.string)
        case "Read": return "Reading " + base(i["file_path"]?.string)
        case "Grep", "Glob": return "Searching " + firstLine(i["pattern"]?.string ?? "files", max: 40)
        case "WebFetch": return "Fetching " + (i["url"]?.string.flatMap { URL(string: $0)?.host } ?? "a page")
        case "WebSearch": return "Searching the web"
        case "Task", "Agent": return "Running a subagent"
        case "AskUserQuestion": return "Asking a question"
        case "ExitPlanMode": return "Presenting a plan"
        default:
            if tool.hasPrefix("mcp__") {
                let parts = tool.dropFirst(5).components(separatedBy: "__")
                if parts.count >= 2 { return "\(parts[0]): \(parts.dropFirst().joined(separator: " "))" }
            }
            return tool
        }
    }
}

/// Pure reducer from hook events to session state. No I/O, so it is fully unit-testable.
public struct SessionStore: Sendable {
    public private(set) var sessions: [String: Session] = [:]

    public init() {}

    /// Sessions shown in the list: everything that has not been cleared.
    public var sorted: [Session] {
        sessions.values.filter { !$0.dismissed }.sorted {
            ($0.state.sortRank, $1.stateSince, $0.id) < ($1.state.sortRank, $0.stateSince, $1.id)
        }
    }

    public var attentionCount: Int { sessions.values.filter { $0.state.needsAttention && !$0.dismissed }.count }

    /// Applies one event. Returns the session after the event, or nil if it was removed or ignored.
    @discardableResult
    public mutating func apply(_ env: Envelope, now: Date = Date()) -> Session? {
        guard let id = env.sessionID, !id.isEmpty else { return nil }
        let p = env.payload

        if env.event == "SessionEnd" {
            sessions[id] = nil
            return nil
        }

        var s = sessions[id] ?? Session(id: id, agent: env.agent, cwd: nil, title: nil, state: .idle,
                                        stateSince: now, lastEventAt: now, activity: nil, subagents: 0,
                                        permissionMode: nil, context: env.context)
        s.lastEventAt = now
        if let cwd = p["cwd"]?.string { s.cwd = cwd }
        if let mode = p["permission_mode"]?.string { s.permissionMode = mode }
        // Later events may come from a different process tree (e.g. after resume); keep the freshest.
        if env.context.agentPid != nil || s.context.agentPid == nil { s.context = env.context }

        func set(_ state: SessionState) {
            if s.state != state { s.state = state; s.stateSince = now }
        }
        let tool = p["tool_name"]?.string

        switch env.event {
        case "SessionStart":
            break
        case "UserPromptSubmit":
            if let prompt = p["prompt"]?.string, !prompt.isEmpty {
                s.title = Activity.firstLine(prompt, max: 120)
            }
            s.activity = "Thinking"
            s.workKind = .thinking
            set(.working)
        case "PreToolUse":
            if let tool {
                s.activity = Activity.describe(tool: tool, input: p["tool_input"])
                s.workKind = WorkKind.forTool(tool)
            }
            set(tool == "AskUserQuestion" ? .waitingForInput : .working)
        case "PostToolUse", "PostToolUseFailure":
            // Between tool calls the agent is deciding what to do next.
            s.workKind = .thinking
            set(.working)
        case "PermissionRequest":
            if let tool { s.activity = Activity.describe(tool: tool, input: p["tool_input"]) }
            set(.needsApproval)
        case "Notification":
            switch p["notification_type"]?.string {
            case "permission_prompt": set(.needsApproval)
            case "idle_prompt": if s.state != .done && s.state != .error { set(.waitingForInput) }
            case "agent_needs_input", "elicitation_dialog", "elicitation_url_dialog": set(.waitingForInput)
            default: break
            }
        case "SubagentStart":
            s.subagents += 1
        case "SubagentStop":
            s.subagents = max(0, s.subagents - 1)
        case "PreCompact":
            s.activity = "Compacting context"
            s.workKind = .thinking
        case "PostCompact":
            s.activity = nil
        case "Stop":
            s.activity = nil
            s.subagents = 0
            set(.done)
        case "StopFailure":
            s.activity = p["error"]?.string ?? p["message"]?.string
            set(.error)
        default:
            break
        }

        // A cleared session returns when it starts something new or its state changes
        // (a finished one that just repeats "finished" stays cleared).
        if s.dismissed, let before = sessions[id], s.state != before.state || env.event == "UserPromptSubmit" {
            s.dismissed = false
        }
        sessions[id] = s
        return s
    }

    /// Clears one session from the list.
    public mutating func dismiss(_ id: String) {
        sessions[id]?.dismissed = true
    }

    public mutating func restore(_ id: String) {
        sessions[id]?.dismissed = false
    }

    /// Clears every finished session. Returns how many were cleared.
    @discardableResult
    public mutating func dismissFinished() -> Int {
        let ids = sessions.values.filter { $0.state == .done && !$0.dismissed }.map(\.id)
        for id in ids { sessions[id]?.dismissed = true }
        return ids.count
    }

    /// Clears sessions that finished, or started but were never given anything to do, more than
    /// `after` seconds ago. Returns how many were cleared.
    @discardableResult
    public mutating func dismissFinished(olderThan after: TimeInterval, now: Date = Date()) -> Int {
        let ids = sessions.values
            .filter { ($0.state == .done || $0.state == .idle) && !$0.dismissed && now.timeIntervalSince($0.stateSince) >= after }.map(\.id)
        for id in ids { sessions[id]?.dismissed = true }
        return ids.count
    }

    public var finishedCount: Int { sessions.values.filter { $0.state == .done && !$0.dismissed }.count }

    /// Called after the user answers a request from the panel, so the row stops asking for attention
    /// before the agent's next event arrives.
    public mutating func markResolved(sessionID: String, now: Date = Date()) {
        guard var s = sessions[sessionID], s.state.needsAttention else { return }
        s.state = .working
        s.stateSince = now
        sessions[sessionID] = s
    }

    /// Drops sessions whose agent process has exited, or that have been silent past `staleAfter`
    /// with no known process. Returns the removed ids.
    @discardableResult
    public mutating func reap(now: Date = Date(), staleAfter: TimeInterval = 6 * 3600,
                              isAlive: (Int32) -> Bool) -> [String] {
        var removed: [String] = []
        for (id, s) in sessions {
            // Remote sessions have no local process to check.
            if s.context.host == nil, let pid = s.context.agentPid {
                if !isAlive(pid) { removed.append(id) }
            } else if now.timeIntervalSince(s.lastEventAt) > staleAfter {
                removed.append(id)
            }
        }
        for id in removed { sessions[id] = nil }
        return removed
    }
}
