import Foundation
import Testing
@testable import CrowsNestCore

func event(_ name: String, session: String = "s1", _ extra: [String: JSONValue] = [:],
           context: TerminalContext = TerminalContext()) -> Envelope {
    var payload: [String: JSONValue] = [
        "session_id": .string(session), "hook_event_name": .string(name), "cwd": .string("/tmp/demo-project"),
    ]
    payload.merge(extra) { _, new in new }
    return Envelope(agent: "claude", event: name, blocking: name == "PermissionRequest",
                    payload: .object(payload), context: context)
}

@Suite struct SessionStoreTests {
    @Test func lifecycle() {
        var store = SessionStore()
        let t0 = Date(timeIntervalSince1970: 1000)
        store.apply(event("SessionStart"), now: t0)
        #expect(store.sessions["s1"]?.state == .idle)
        #expect(store.sessions["s1"]?.projectName == "demo-project")

        store.apply(event("UserPromptSubmit", ["prompt": "Fix the login bug\nand add tests"]), now: t0 + 1)
        #expect(store.sessions["s1"]?.state == .working)
        #expect(store.sessions["s1"]?.title == "Fix the login bug")

        store.apply(event("PreToolUse", ["tool_name": "Bash", "tool_input": .object(["command": "npm test"])]), now: t0 + 2)
        #expect(store.sessions["s1"]?.activity == "Running: npm test")
        #expect(store.sessions["s1"]?.stateSince == t0 + 1)   // still working: timer not reset

        store.apply(event("PermissionRequest", ["tool_name": "Bash", "tool_input": .object(["command": "npm test"])]), now: t0 + 3)
        #expect(store.sessions["s1"]?.state == .needsApproval)
        #expect(store.attentionCount == 1)

        store.apply(event("PostToolUse", ["tool_name": "Bash"]), now: t0 + 4)
        #expect(store.sessions["s1"]?.state == .working)

        store.apply(event("Stop"), now: t0 + 5)
        #expect(store.sessions["s1"]?.state == .done)
        #expect(store.sessions["s1"]?.activity == nil)

        store.apply(event("SessionEnd"), now: t0 + 6)
        #expect(store.sessions.isEmpty)
    }

    @Test func unknownSessionIsCreatedFromAnyEvent() {
        var store = SessionStore()
        store.apply(event("PreToolUse", session: "late", ["tool_name": "Read", "tool_input": .object(["file_path": "/a/b/c.swift"])]))
        #expect(store.sessions["late"]?.state == .working)
        #expect(store.sessions["late"]?.activity == "Reading c.swift")
    }

    @Test func eventsWithoutSessionAreIgnored() {
        var store = SessionStore()
        let e = Envelope(agent: "claude", event: "Stop", blocking: false, payload: .object([:]), context: TerminalContext())
        #expect(store.apply(e) == nil)
        #expect(store.sessions.isEmpty)
    }

    @Test func notifications() {
        var store = SessionStore()
        store.apply(event("UserPromptSubmit", ["prompt": "hi"]))
        store.apply(event("Notification", ["notification_type": "permission_prompt"]))
        #expect(store.sessions["s1"]?.state == .needsApproval)
        store.apply(event("Notification", ["notification_type": "agent_needs_input"]))
        #expect(store.sessions["s1"]?.state == .waitingForInput)
        store.apply(event("Stop"))
        store.apply(event("Notification", ["notification_type": "idle_prompt"]))
        #expect(store.sessions["s1"]?.state == .done)   // idle after finishing stays "done"
        store.apply(event("Notification", ["notification_type": "auth_success"]))
        #expect(store.sessions["s1"]?.state == .done)
    }

    @Test func subagentsAndFailure() {
        var store = SessionStore()
        store.apply(event("SubagentStart"))
        store.apply(event("SubagentStart"))
        store.apply(event("SubagentStop"))
        #expect(store.sessions["s1"]?.subagents == 1)
        store.apply(event("SubagentStop"))
        store.apply(event("SubagentStop"))
        #expect(store.sessions["s1"]?.subagents == 0)
        store.apply(event("StopFailure", ["error": "rate_limit"]))
        #expect(store.sessions["s1"]?.state == .error)
    }

    @Test func sortingPutsUrgentFirst() {
        var store = SessionStore()
        store.apply(event("Stop", session: "done"))
        store.apply(event("UserPromptSubmit", session: "working", ["prompt": "x"]))
        store.apply(event("PermissionRequest", session: "approval", ["tool_name": "Bash"]))
        #expect(store.sorted.map(\.id) == ["approval", "working", "done"])
    }

    @Test func reaping() {
        var store = SessionStore()
        let t0 = Date(timeIntervalSince1970: 0)
        store.apply(event("SessionStart", session: "dead", context: TerminalContext(agentPid: 111)), now: t0)
        store.apply(event("SessionStart", session: "alive", context: TerminalContext(agentPid: 222)), now: t0)
        store.apply(event("SessionStart", session: "nopid-old"), now: t0)
        store.apply(event("SessionStart", session: "nopid-new"), now: t0 + 7 * 3600)
        let removed = store.reap(now: t0 + 7 * 3600 + 60) { $0 == 222 }
        #expect(Set(removed) == ["dead", "nopid-old"])
        #expect(Set(store.sessions.keys) == ["alive", "nopid-new"])
    }

    @Test func activityDescriptions() {
        #expect(Activity.describe(tool: "Edit", input: .object(["file_path": "/x/y/App.swift"])) == "Editing App.swift")
        #expect(Activity.describe(tool: "mcp__github__create_issue", input: nil) == "github: create_issue")
        #expect(Activity.describe(tool: "WebFetch", input: .object(["url": "https://example.com/a"])) == "Fetching example.com")
        let long = String(repeating: "a", count: 200)
        #expect(Activity.describe(tool: "Bash", input: .object(["command": .string(long)])).count == "Running: ".count + 80)
    }

    @Test func clearedSessionsLeaveTheListAndComeBackOnNewActivity() {
        var store = SessionStore()
        store.apply(event("UserPromptSubmit", session: "a", ["prompt": "one"]))
        store.apply(event("Stop", session: "a"))
        store.apply(event("UserPromptSubmit", session: "b", ["prompt": "two"]))
        store.dismiss("a")
        #expect(store.sorted.map(\.id) == ["b"])
        #expect(store.sessions["a"] != nil)                          // still tracked

        store.apply(event("Stop", session: "a"))                     // repeats "finished": stays cleared
        store.apply(event("Notification", session: "a", ["notification_type": "idle_prompt"]))
        #expect(store.sorted.map(\.id) == ["b"])

        store.apply(event("UserPromptSubmit", session: "a", ["prompt": "again"]))
        #expect(Set(store.sorted.map(\.id)) == ["a", "b"])          // new work brings it back
    }

    @Test func clearedWorkingSessionReturnsWhenItNeedsYouOrFinishes() {
        var store = SessionStore()
        store.apply(event("UserPromptSubmit", ["prompt": "x"]))
        store.dismiss("s1")
        store.apply(event("PreToolUse", ["tool_name": "Read"]))      // still just working
        store.apply(event("PostToolUse", ["tool_name": "Read"]))
        #expect(store.sorted.isEmpty)
        #expect(store.attentionCount == 0)
        store.apply(event("PermissionRequest", ["tool_name": "Bash"]))
        #expect(store.sorted.map(\.id) == ["s1"])
        #expect(store.attentionCount == 1)
    }

    @Test func finishedSessionsClearAutomaticallyAfterADelay() {
        var store = SessionStore()
        let t0 = Date(timeIntervalSince1970: 5000)
        store.apply(event("Stop", session: "old"), now: t0)
        store.apply(event("Stop", session: "recent"), now: t0 + 250)
        store.apply(event("UserPromptSubmit", session: "busy", ["prompt": "x"]), now: t0)
        store.apply(event("StopFailure", session: "failed"), now: t0)
        #expect(store.finishedCount == 2)
        #expect(store.dismissFinished(olderThan: 300, now: t0 + 300) == 1)
        #expect(Set(store.sorted.map(\.id)) == ["recent", "busy", "failed"])   // errors and running work are never auto-cleared
        #expect(store.dismissFinished() == 1)
        #expect(Set(store.sorted.map(\.id)) == ["busy", "failed"])
        #expect(store.finishedCount == 0)
    }

    @Test func sessionsThatNeverStartedClearToo() {
        var store = SessionStore()
        let t0 = Date(timeIntervalSince1970: 9000)
        store.apply(event("SessionStart", session: "headless"), now: t0)
        store.apply(event("UserPromptSubmit", session: "busy", ["prompt": "x"]), now: t0)
        #expect(store.dismissFinished(olderThan: 300, now: t0 + 301) == 1)
        #expect(store.sorted.map(\.id) == ["busy"])
        store.apply(event("UserPromptSubmit", session: "headless", ["prompt": "now"]), now: t0 + 400)
        #expect(Set(store.sorted.map(\.id)) == ["busy", "headless"])   // comes back once it does something
    }

    @Test func restoredSessionIsListedAgain() {
        var store = SessionStore()
        store.apply(event("PermissionRequest", session: "a", ["tool_name": "Bash"]))
        store.dismiss("a")
        store.apply(event("PermissionRequest", session: "a", ["tool_name": "Bash"]))   // same state: stays cleared
        #expect(store.sorted.isEmpty)
        store.restore("a")
        #expect(store.sorted.map(\.id) == ["a"])
        #expect(store.attentionCount == 1)
    }
}
