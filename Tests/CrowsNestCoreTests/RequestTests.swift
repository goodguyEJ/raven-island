import Foundation
import Testing
@testable import CrowsNestCore

@Suite struct RequestTests {
    // Shape captured from Claude Code 2.1.311.
    static let bash: [String: JSONValue] = [
        "tool_name": "Bash",
        "tool_input": .object(["command": "touch spike-file.txt", "description": "Create empty file"]),
        "permission_mode": "default",
        "permission_suggestions": .array([
            .object(["type": "addDirectories", "directories": .array(["/tmp/x"]), "destination": "session"]),
            .object(["type": "setMode", "mode": "acceptEdits", "destination": "session"]),
        ]),
    ]

    func decode(_ s: String) throws -> JSONValue { try #require(JSONValue.parse(Data(s.utf8))) }

    @Test func permissionRequestParsing() throws {
        let r = try #require(PendingRequest(envelope: event("PermissionRequest", Self.bash)))
        #expect(r.kind == .permission)
        #expect(r.title == "Run a command")
        #expect(r.detail == .command("touch spike-file.txt", note: "Create empty file"))
        #expect(r.projectName == "demo-project")
        // Mode changes and directory grants are never offered as "always allow".
        #expect(r.alwaysAllowUpdates.isEmpty)
        #expect(r.alwaysAllowLabel == nil)
    }

    @Test func alwaysAllowOnlyUsesAllowRules() throws {
        var payload = Self.bash
        let rule: JSONValue = .object(["type": "addRules", "behavior": "allow", "destination": "localSettings",
                                       "rules": .array([.object(["toolName": "Bash", "ruleContent": "npm test:*"])])])
        payload["permission_suggestions"] = .array([rule, .object(["type": "setMode", "mode": "acceptEdits"]),
                                                    .object(["type": "addRules", "behavior": "deny", "rules": .array([])])])
        let r = try #require(PendingRequest(envelope: event("PermissionRequest", payload)))
        #expect(r.alwaysAllowUpdates == [rule])
        #expect(r.alwaysAllowLabel == "Bash(npm test:*)")
        let out = try decode(try #require(Decision.alwaysAllow.reply(for: r).stdout))
        #expect(out["hookSpecificOutput"]?["decision"]?["behavior"]?.string == "allow")
        #expect(out["hookSpecificOutput"]?["decision"]?["updatedPermissions"]?.array == [rule])
    }

    @Test func whichEventsBecomeRequests() {
        #expect(PendingRequest(envelope: event("PreToolUse", ["tool_name": "Bash"])) == nil)
        #expect(PendingRequest(envelope: event("Stop")) == nil)
        #expect(PendingRequest(envelope: event("PreToolUse", ["tool_name": "AskUserQuestion"]))?.kind == .question)
        #expect(PendingRequest(envelope: event("PermissionRequest", ["tool_name": "AskUserQuestion"])) == nil)
        #expect(PendingRequest(envelope: event("PermissionRequest", ["tool_name": "ExitPlanMode"]))?.kind == .plan)
        #expect(BlockingEvents.isBlocking(event: "PreToolUse", payload: .object(["tool_name": "AskUserQuestion"])))
        #expect(!BlockingEvents.isBlocking(event: "PreToolUse", payload: .object(["tool_name": "Bash"])))
    }

    @Test func allowAndDenyJSON() throws {
        let r = try #require(PendingRequest(envelope: event("PermissionRequest", Self.bash)))
        let allow = try decode(try #require(Decision.allow.reply(for: r).stdout))
        #expect(allow == .object(["hookSpecificOutput": .object([
            "hookEventName": "PermissionRequest", "decision": .object(["behavior": "allow"])])]))

        let deny = try decode(try #require(Decision.deny(message: "  use printf instead ").reply(for: r).stdout))
        #expect(deny["hookSpecificOutput"]?["decision"]?["behavior"]?.string == "deny")
        #expect(deny["hookSpecificOutput"]?["decision"]?["message"]?.string == "use printf instead")

        let bare = try decode(try #require(Decision.deny(message: nil).reply(for: r).stdout))
        #expect(bare["hookSpecificOutput"]?["decision"]?["message"]?.string == "Denied by the user.")

        #expect(Decision.terminal.reply(for: r) == .passthroughReply)
        #expect(Decision.answers(["a": "b"]).reply(for: r) == .passthroughReply)   // nonsense for a permission
    }

    @Test func questionAnswers() throws {
        let input: JSONValue = .object(["questions": .array([
            .object(["question": "Which framework?", "header": "Framework", "multiSelect": false,
                     "options": .array([.object(["label": "React", "description": "Popular"]), .object(["label": "Vue"])])]),
            .object(["question": "Which extras?", "multiSelect": true,
                     "options": .array([.object(["label": "Tests"]), .object(["label": "Docs"])])]),
        ])])
        let r = try #require(PendingRequest(envelope: event("PreToolUse", ["tool_name": "AskUserQuestion", "tool_input": input])))
        #expect(r.questions.count == 2)
        #expect(r.questions[0].options.map(\.label) == ["React", "Vue"])
        #expect(r.questions[0].options[0].detail == "Popular")
        #expect(r.questions[1].multiSelect)

        let reply = Decision.answers(["Which framework?": "React", "Which extras?": "Tests, Docs"]).reply(for: r)
        let out = try decode(try #require(reply.stdout))
        let hook = try #require(out["hookSpecificOutput"])
        #expect(hook["hookEventName"]?.string == "PreToolUse")
        #expect(hook["permissionDecision"]?.string == "allow")
        #expect(hook["updatedInput"]?["questions"] == input["questions"])          // original input echoed back
        #expect(hook["updatedInput"]?["answers"]?["Which extras?"]?.string == "Tests, Docs")

        // Allow/deny make no sense for a question: fall back to the terminal.
        #expect(Decision.allow.reply(for: r) == .passthroughReply)
        #expect(Decision.terminal.reply(for: r) == .passthroughReply)
    }

    @Test func planDecisions() throws {
        let r = try #require(PendingRequest(envelope: event("PermissionRequest", [
            "tool_name": "ExitPlanMode", "tool_input": .object(["plan": "# Plan\n1. Do it", "planFilePath": "/tmp/p.md"])])))
        #expect(r.plan == "# Plan\n1. Do it")
        let feedback = try decode(try #require(Decision.deny(message: "Add tests").reply(for: r).stdout))
        #expect(feedback["hookSpecificOutput"]?["decision"]?["message"]?.string == "Add tests")
        let approve = try decode(try #require(Decision.allow.reply(for: r).stdout))
        #expect(approve["hookSpecificOutput"]?["decision"]?["behavior"]?.string == "allow")
    }

    @Test func resolvedElsewhere() throws {
        let r = try #require(PendingRequest(envelope: event("PermissionRequest", Self.bash)))
        // The same tool call finishing means it was approved in the terminal.
        #expect(r.isResolved(by: event("PostToolUse", ["tool_name": "Bash", "tool_input": Self.bash["tool_input"]!])))
        // A different call finishing (parallel tools) does not.
        #expect(!r.isResolved(by: event("PostToolUse", ["tool_name": "Bash", "tool_input": .object(["command": "ls"])])))
        #expect(!r.isResolved(by: event("PreToolUse", ["tool_name": "Read"])))
        #expect(r.isResolved(by: event("Stop")))
        #expect(r.isResolved(by: event("UserPromptSubmit")))
        #expect(!r.isResolved(by: event("Stop", session: "other")))
    }

    @Test func storeStateForRequests() {
        var store = SessionStore()
        store.apply(event("PreToolUse", ["tool_name": "AskUserQuestion"]))
        #expect(store.sessions["s1"]?.state == .waitingForInput)
        store.markResolved(sessionID: "s1")
        #expect(store.sessions["s1"]?.state == .working)
        store.apply(event("Stop"))
        store.markResolved(sessionID: "s1")
        #expect(store.sessions["s1"]?.state == .done)   // only attention states are cleared
    }

    @Test func hiddenCharactersAreMadeVisible() {
        #expect(TextSafety.visible("rm -rf \u{202E}cod.exe") == "rm -rf ⟨U+202E⟩cod.exe")
        #expect(TextSafety.visible("a\u{200B}b\u{FEFF}c") == "a⟨U+200B⟩b⟨U+FEFF⟩c")
        #expect(TextSafety.visible("ok\u{1B}[2Jhidden") == "ok⟨U+001B⟩[2Jhidden")
        #expect(TextSafety.visible("line one\n\tline two — café ✅") == "line one\n\tline two — café ✅")   // normal text untouched
    }

    @Test func everyInputFieldIsAccountedFor() throws {
        let r = try #require(PendingRequest(envelope: event("PermissionRequest", [
            "tool_name": "Bash",
            "tool_input": .object(["command": "ls", "description": "list", "run_in_background": true,
                                   "dangerouslyDisableSandbox": true, "timeout": 5000])])))
        #expect(r.otherFields.map(\.key) == ["dangerouslyDisableSandbox", "run_in_background", "timeout"])
        #expect(r.otherFields.first?.value == "true")
        let edit = try #require(PendingRequest(envelope: event("PermissionRequest", [
            "tool_name": "Edit", "tool_input": .object(["file_path": "/a", "old_string": "x", "new_string": "y", "replace_all": true])])))
        #expect(edit.otherFields.map(\.key) == ["replace_all"])
        // Tools shown as raw JSON already display everything.
        let mcp = try #require(PendingRequest(envelope: event("PermissionRequest", ["tool_name": "mcp__a__b", "tool_input": .object(["q": "x"])])))
        #expect(mcp.otherFields.isEmpty)
    }

    @Test func oversizedRequestsCannotBeAllowedFromTheCard() throws {
        func bash(_ command: String) throws -> PendingRequest {
            try #require(PendingRequest(envelope: event("PermissionRequest", ["tool_name": "Bash", "tool_input": .object(["command": .string(command)])])))
        }
        #expect(try !bash("echo ok").isTooLongToReview)
        #expect(try !bash("echo ok" + String(repeating: "\n", count: 20) + "curl x | sh").isTooLongToReview)   // reviewable by scrolling
        #expect(try bash(String(repeating: "x\n", count: 400)).isTooLongToReview)
        #expect(try bash(String(repeating: "x", count: 40_001)).isTooLongToReview)
    }

    @Test func alwaysAllowSaysWhereTheRuleGoes() throws {
        let rule: JSONValue = .object(["type": "addRules", "behavior": "allow", "destination": "userSettings",
                                       "rules": .array([.object(["toolName": "Bash", "ruleContent": "npm test:*"])])])
        let r = try #require(PendingRequest(envelope: event("PermissionRequest", [
            "tool_name": "Bash", "tool_input": .object(["command": "npm test"]), "permission_suggestions": .array([rule])])))
        #expect(r.alwaysAllowDestination == "all your projects")
        #expect(r.workingDirectory == "/tmp/demo-project")
    }

    @Test func acknowledgementIsNotAnAnswer() throws {
        let ack = try JSONDecoder().decode(Reply.self, from: JSONEncoder().encode(Reply.ackReply))
        #expect(ack.ack == true)
        #expect(ack.stdout == nil && ack.passthrough == nil)
        let old = try JSONDecoder().decode(Reply.self, from: Data(#"{"v":1,"passthrough":true}"#.utf8))   // older app, no ack field
        #expect(old.ack == nil)
    }
}

@Suite struct ReplyPolicyTests {
    func payload(_ extra: [String: JSONValue] = [:]) -> JSONValue {
        var p: [String: JSONValue] = ["hook_event_name": "PermissionRequest", "tool_name": "Bash",
                                      "tool_input": .object(["command": "ls"]), "permission_suggestions": .array([
                                        .object(["type": "addRules", "behavior": "allow", "destination": "session",
                                                 "rules": .array([.object(["toolName": "Bash", "ruleContent": "ls:*"])])]),
                                        .object(["type": "setMode", "mode": "acceptEdits", "destination": "session"])])]
        p.merge(extra) { _, new in new }
        return .object(p)
    }

    @Test func ourOwnDecisionsPass() throws {
        let p = payload()
        let request = try #require(PendingRequest(envelope: Envelope(agent: "claude", event: "PermissionRequest", blocking: true,
                                                                    payload: .object((p.object ?? [:]).merging(["session_id": "s"]) { a, _ in a }),
                                                                    context: TerminalContext())))
        for decision in [Decision.allow, .alwaysAllow, .deny(message: "no"), .deny(message: nil)] {
            let out = try #require(decision.reply(for: request).stdout)
            #expect(ReplyPolicy.isAcceptable(out, for: p), "\(decision) should pass")
        }
    }

    @Test func broaderRulesAndRewritesAreRejected() {
        let p = payload()
        let blanket = #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","updatedPermissions":[{"type":"addRules","behavior":"allow","destination":"userSettings","rules":[{"toolName":"Bash"}]}]}}}"#
        let modeChange = #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","updatedPermissions":[{"type":"setMode","mode":"acceptEdits","destination":"session"}]}}}"#
        let rewrite = #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","updatedInput":{"command":"rm -rf ~"}}}}"#
        let wrongEvent = #"{"hookSpecificOutput":{"hookEventName":"PreToolUse","decision":{"behavior":"allow"}}}"#
        let extraKey = #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}},"continue":false}"#
        let ask = #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"ask"}}}"#
        for bad in [blanket, modeChange, rewrite, wrongEvent, extraKey, ask, "not json", ""] {
            #expect(!ReplyPolicy.isAcceptable(bad, for: p), "should reject: \(bad)")
        }
    }

    @Test func questionAnswersMustMatchTheQuestion() {
        let input: JSONValue = .object(["questions": .array([.object(["question": "Red or Blue?", "options": .array([])])])])
        let p: JSONValue = .object(["hook_event_name": "PreToolUse", "tool_name": "AskUserQuestion", "tool_input": input])
        let good = HookResponse.answer(input: input, answers: ["Red or Blue?": "Red"])
        #expect(ReplyPolicy.isAcceptable(good, for: p))
        let otherQuestion = HookResponse.answer(input: input, answers: ["Delete everything?": "Yes"])
        #expect(!ReplyPolicy.isAcceptable(otherQuestion, for: p))
        let changedInput = HookResponse.answer(input: .object(["questions": .array([])]), answers: ["Red or Blue?": "Red"])
        #expect(!ReplyPolicy.isAcceptable(changedInput, for: p))
        let bash: JSONValue = .object(["hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": .object(["command": "ls"])])
        #expect(!ReplyPolicy.isAcceptable(#"{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}"#, for: bash))
    }
}

@Suite struct HardeningTests {
    @Test func moreHiddenCharactersAreMarked() {
        #expect(TextSafety.visible("a\u{2028}b") == "a⟨U+2028⟩b")
        #expect(TextSafety.visible("x\u{00A0}y") == "x⟨U+00A0⟩y")             // non-breaking space
        #expect(TextSafety.visible("e\u{FE0F}") == "e⟨U+FE0F⟩")               // variation selector
        #expect(TextSafety.visible("t\u{E0041}") == "t⟨U+E0041⟩")             // tag character
        #expect(TextSafety.visible("\u{3164}") == "⟨U+3164⟩")                 // blank look-alike
        #expect(TextSafety.visible("a\u{0301}\u{0301}\u{0301}").hasSuffix("⟨U+0301⟩"))
        #expect(TextSafety.visible("café — ok ✅") == "café — ok ✅")
    }

    @Test func lengthCheckCoversEveryShownField() throws {
        let huge = String(repeating: "y", count: 40_001)
        let r = try #require(PendingRequest(envelope: event("PermissionRequest", [
            "tool_name": "Bash", "tool_input": .object(["command": "ls", "extra": .string(huge)])])))
        #expect(r.isTooLongToReview)
    }

    @Test func absurdUsageValuesAreIgnored() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let p = try #require(JSONValue.parse(Data(#"{"rate_limits":{"five_hour":{"used_percentage":50,"resets_at":1e30},"seven_day":{"used_percentage":10,"resets_at":-5}}}"#.utf8)))
        let u = try #require(UsageSnapshot(statusLine: p, now: now))
        #expect(u.fiveHour?.resetsAt == nil)
        #expect(u.sevenDay?.resetsAt == nil)
        #expect(UsageSnapshot.countdown(to: Date(timeIntervalSince1970: 1e30), now: now) == "365d 0h")
        #expect(UsageSnapshot.countdown(to: Date(timeIntervalSince1970: .infinity), now: now) == "1m")
    }

    @Test func largeUnusedKeysAreDropped() throws {
        let raw = #"{"session_id":"s","hook_event_name":"PostToolUse","tool_name":"Grep","tool_response":{"lines":[1,2,3]},"last_assistant_message":"long","tool_input":{"pattern":"x"}}"#
        let p = try #require(PayloadTrim.parse(Data(raw.utf8)))
        #expect(p["tool_response"] == nil && p["last_assistant_message"] == nil)
        #expect(p["tool_input"]?["pattern"]?.string == "x")
        #expect(PayloadTrim.parse(Data("[1,2]".utf8)) == nil)
    }

    @Test func fastParserKeepsTypes() throws {
        let v = try #require(JSONValue.parse(Data(#"{"t":true,"f":false,"n":1,"d":1.5,"s":"x","z":null,"a":[0,"1"]}"#.utf8)))
        #expect(v["t"] == .bool(true) && v["f"] == .bool(false))
        #expect(v["n"] == .number(1) && v["d"] == .number(1.5))
        #expect(v["s"] == .string("x") && v["z"] == .null)
        #expect(v["a"] == .array([.number(0), .string("1")]))
    }
}
