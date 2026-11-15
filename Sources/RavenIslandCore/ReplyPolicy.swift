import Foundation

/// The helper's last line of defence: before printing a decision for Claude Code, it checks that the
/// decision has exactly the shape Raven Island produces for that request. Anything else (a broader
/// permission rule than the request offered, a rewritten tool input, an unknown field) is dropped
/// and Claude Code shows its own prompt instead.
public enum ReplyPolicy {
    public static func isAcceptable(_ stdout: String, for payload: JSONValue) -> Bool {
        guard let event = payload["hook_event_name"]?.string,
              let root = JSONValue.parse(Data(stdout.utf8))?.object,
              Set(root.keys) == ["hookSpecificOutput"],
              let output = root["hookSpecificOutput"]?.object,
              output["hookEventName"]?.string == event else { return false }

        switch event {
        case "PermissionRequest":
            guard Set(output.keys) == ["hookEventName", "decision"], let decision = output["decision"]?.object,
                  let behavior = decision["behavior"]?.string else { return false }
            switch behavior {
            case "allow":
                guard Set(decision.keys).isSubset(of: ["behavior", "updatedPermissions"]) else { return false }
                guard let updates = decision["updatedPermissions"] else { return true }
                // Only rules the request itself suggested, and only "allow" rules.
                let offered = payload["permission_suggestions"]?.array ?? []
                guard let list = updates.array, !list.isEmpty else { return false }
                return list.allSatisfy { update in
                    update["type"]?.string == "addRules" && update["behavior"]?.string == "allow" && offered.contains(update)
                }
            case "deny":
                guard Set(decision.keys).isSubset(of: ["behavior", "message", "interrupt"]) else { return false }
                if let m = decision["message"], m.string == nil { return false }
                if let i = decision["interrupt"], i.bool == nil { return false }
                return true
            default:
                return false
            }

        case "PreToolUse":
            // Only used to answer a question: the original input plus answers to its own questions.
            guard payload["tool_name"]?.string == "AskUserQuestion",
                  Set(output.keys) == ["hookEventName", "permissionDecision", "updatedInput"],
                  output["permissionDecision"]?.string == "allow",
                  var updated = output["updatedInput"]?.object,
                  let answers = updated.removeValue(forKey: "answers")?.object,
                  JSONValue.object(updated) == (payload["tool_input"] ?? JSONValue.object([:])) else { return false }
            let questions = Set((payload["tool_input"]?["questions"]?.array ?? []).compactMap { $0["question"]?.string })
            return !answers.isEmpty && answers.allSatisfy { questions.contains($0.key) && $0.value.string != nil }

        default:
            return false
        }
    }
}
