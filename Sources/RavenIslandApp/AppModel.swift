import Foundation
import Combine
import RavenIslandCore

struct LogEntry: Identifiable {
    let id = UUID()
    let time: Date
    let event: String
    let session: String
    let detail: String
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    /// Requests waiting for the user, oldest first.
    @Published private(set) var pending: [PendingRequest] = []
    @Published private(set) var log: [LogEntry] = []
    @Published private(set) var hookStatus: Installer.Status?
    @Published private(set) var eventCount = 0
    /// Latest subscription usage reported through the status line; nil until one arrives.
    @Published private(set) var usage: UsageSnapshot?

    /// Brings a session's terminal to the front. Set by the app delegate.
    var jump: (Session) -> String = { _ in "Jumping is not available" }

    var diagnostics: () -> String = { "" }

    func session(id: String) -> Session? { store.sessions[id] }

    /// Called when a session moves to a new state (old state is nil for a session seen for the first time).
    var onTransition: (_ session: Session, _ old: SessionState?) -> Void = { _, _ in }

    /// Seconds after which a finished session is cleared from the list; nil keeps it until cleared by hand.
    var autoClearAfter: TimeInterval? = 300
    /// Clear a finished session when the user jumps to it (they have seen it).
    var clearOnJump = true

    @Published private(set) var finishedCount = 0

    private func publishSessions() {
        sessions = store.sorted
        finishedCount = store.finishedCount
    }

    /// The row's check button. A session with a decision waiting stays listed until it's answered.
    func dismiss(_ id: String) {
        guard !pending.contains(where: { $0.sessionID == id }) else { return }
        store.dismiss(id)
        publishSessions()
    }

    func dismissFinished() {
        store.dismissFinished()
        publishSessions()
    }

    /// Row click: bring the terminal forward, and treat a finished session as dealt with.
    func open(_ session: Session) {
        _ = jump(session)
        if clearOnJump, session.state == .done { dismiss(session.id) }
    }

    /// When off, Raven Island only observes and every request goes to the agent's own prompt.
    var answersFromPanel = true

    private var store = SessionStore()
    private var connections: [String: BlockingConnection] = [:]
    private var reapTimer: Timer?

    var attentionCount: Int { store.attentionCount }

    func start() {
        if let data = UserDefaults.standard.data(forKey: "usage"),
           let saved = try? JSONDecoder().decode(UsageSnapshot.self, from: data) {
            let live = saved.current()
            usage = live.isEmpty ? nil : live
        }
        refreshHookStatus()
        reapTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reap() }
        }
        reapTimer?.tolerance = 5
        // Heartbeat for waiting requests. Sent from the main thread, so a hung app stops sending and
        // every waiting helper falls back to Claude Code's own prompt within a few seconds.
        let heartbeat = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                for request in self.pending { self.connections[request.id]?.acknowledge() }
            }
        }
        // Common modes, not just the default one: a default-mode timer pauses while the user scrolls a
        // card or holds the mouse down, the helper hears nothing for 3 s, and the decision is handed
        // back to the terminal mid-read.
        RunLoop.main.add(heartbeat, forMode: .common)
        heartbeatTimer = heartbeat
        prepareHelper()
    }

    private var heartbeatTimer: Timer?

    /// Records this app as the helper's trusted peer, and refreshes an installed helper that is out of
    /// date with the one in this app bundle. Never installs a helper the user hasn't installed.
    private func prepareHelper() {
        let executable = Bundle.main.executableURL
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ravenisland-bridge")
        DispatchQueue.global(qos: .utility).async {
            if let executable { try? Installer.recordAppExecutable(executable) }
            let fm = FileManager.default
            let installed = AppPaths.installedBridge
            guard fm.isExecutableFile(atPath: bundled.path), fm.fileExists(atPath: installed.path),
                  let a = try? Data(contentsOf: bundled, options: .mappedIfSafe),
                  let b = try? Data(contentsOf: installed, options: .mappedIfSafe), a != b else { return }
            try? Installer.installBridge(from: bundled)
        }
    }

    /// Requests are capped so a misbehaving local process cannot hold unlimited connections open.
    static let maxPending = 40
    /// A card must be on screen this long before a click or shortcut counts, so an answer meant for
    /// the previous card cannot land on a new one.
    static let armingDelay: TimeInterval = 0.6

    private var frontID: String?
    private var frontSince = Date.distantPast
    private var reviewed: Set<String> = []

    /// The card reports that all of its content has been scrolled into view.
    func markReviewed(_ id: String) { reviewed.insert(id) }

    private func noteFrontChange() {
        if pending.first?.id != frontID {
            frontID = pending.first?.id
            frontSince = Date()
        }
        reviewed.formIntersection(Set(pending.map(\.id)))
        editing.formIntersection(Set(pending.map(\.id)))
    }

    /// The request a keyboard shortcut may act on right now, if any: it has to be the card on
    /// screen, shown long enough to have been seen, and (to allow) fully reviewed.
    /// Requests whose card has a note field open: shortcuts must not act while the user types.
    private var editing: Set<String> = []

    func setEditing(_ id: String, _ on: Bool) {
        if on { editing.insert(id) } else { editing.remove(id) }
    }

    func shortcutTarget(allowing: Bool) -> PendingRequest? {
        guard let front = pending.first, front.id == frontID, !editing.contains(front.id),
              Date().timeIntervalSince(frontSince) >= Self.armingDelay else { return nil }
        if allowing {
            guard front.kind != .question, !front.isTooLongToReview, reviewed.contains(front.id) else { return nil }
        } else {
            guard front.kind == .permission else { return nil }
        }
        return front
    }

    func handle(_ envelope: Envelope, connection: BlockingConnection?) {
        // A helper from a different version may not speak the same protocol: don't guess.
        guard envelope.v == Envelope.version else {
            connection?.reply(.passthroughReply)
            return
        }
        if envelope.agent == ControlEvent.agent {
            handleControl(envelope, connection: connection)
            return
        }

        if envelope.event == StatusLineEvent.name {
            if let report = UsageSnapshot(statusLine: envelope.payload) { updateUsage(report) }
            connection?.reply(.passthroughReply)   // never leave a connection unanswered
            return
        }

        // A later event can show that a waiting request was settled in the terminal.
        for request in pending where request.isResolved(by: envelope) {
            finish(request.id, reply: .passthroughReply, note: "settled elsewhere")
        }

        let before = envelope.sessionID.flatMap { store.sessions[$0]?.state }
        let after = store.apply(envelope)
        if let after, after.state != before { onTransition(after, before) }
        eventCount += 1
        publishSessions()
        let detail = envelope.payload["tool_name"]?.string
            ?? envelope.payload["notification_type"]?.string
            ?? after?.state.label ?? ""
        appendLog(envelope.event, session: envelope.sessionID, detail: detail)

        guard let connection else { return }
        guard answersFromPanel, pending.count < Self.maxPending,
              let request = PendingRequest(envelope: envelope) else {
            connection.reply(.passthroughReply)
            return
        }
        connections[request.id] = connection
        pending.append(request)
        // A decision must never sit behind a session the user cleared earlier.
        store.restore(request.sessionID)
        publishSessions()
        noteFrontChange()
        // Sent from the main thread, so its arrival proves the app is responsive and the card is up.
        connection.acknowledge()
        connection.whenPeerCloses { [weak self] in
            // The agent gave up on the hook (answered in the terminal, cancelled, or timed out).
            Task { @MainActor in self?.finish(request.id, reply: nil, note: "hook went away") }
        }
    }

    /// The user's answer from the panel (or a shortcut).
    func resolve(_ id: String, _ decision: Decision) {
        guard let request = pending.first(where: { $0.id == id }) else { return }
        if decision != .terminal { store.markResolved(sessionID: request.sessionID) }
        finish(id, reply: decision.reply(for: request), note: label(decision))
        publishSessions()
    }

    private func updateUsage(_ report: UsageSnapshot) {
        let merged = (usage?.merging(report) ?? report).current()
        guard merged != usage else { return }
        usage = merged.isEmpty ? nil : merged
        if let data = try? JSONEncoder().encode(merged) { UserDefaults.standard.set(data, forKey: "usage") }
    }

    private func finish(_ id: String, reply: Reply?, note: String) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        let request = pending.remove(at: index)
        if let reply { connections[id]?.reply(reply) }
        connections[id] = nil
        noteFrontChange()
        appendLog("→ " + note, session: request.sessionID, detail: request.title)
    }

    private func label(_ decision: Decision) -> String {
        switch decision {
        case .allow: return "allowed"
        case .alwaysAllow: return "always allowed"
        case .deny: return "denied"
        case .answers: return "answered"
        case .terminal: return "sent to terminal"
        }
    }

    private func appendLog(_ event: String, session: String?, detail: String) {
        log.append(LogEntry(time: Date(), event: event, session: String((session ?? "?").prefix(8)), detail: detail))
        if log.count > 300 { log.removeFirst(log.count - 300) }
    }

    // MARK: Requests from the ravenisland-bridge CLI

    private func handleControl(_ envelope: Envelope, connection: BlockingConnection?) {
        func send(_ value: JSONValue) { connection?.reply(Reply(stdout: HookResponse.encode(value, pretty: true) + "\n")) }
        switch envelope.event {
        case ControlEvent.sessions:
            // States only. Prompts, commands, and folder paths stay inside the app.
            let format = ISO8601DateFormatter()
            send(.array(store.sorted.map { s in
                .object(["id": .string(s.id), "state": .string(s.state.rawValue), "agent": .string(s.agent),
                         "stateSince": .string(format.string(from: s.stateSince)), "subagents": .number(Double(s.subagents)),
                         "termProgram": s.context.termProgram.map { .string($0) } ?? .null,
                         "hasTTY": .bool(s.context.tty != nil)])
            }))
        case ControlEvent.pending:
            send(.array(pending.map { r in
                .object(["id": .string(r.id), "session": .string(r.sessionID), "kind": .string(r.kind.rawValue),
                         "tool": .string(r.tool)])
            }))
        #if DEBUG
        case ControlEvent.resolve:
            // Test builds only: lets the end-to-end tests stand in for a click.
            let p = envelope.payload
            let id = p["id"]?.string ?? pending.first?.id ?? ""
            let decision: Decision?
            switch p["decision"]?.string {
            case "allow": decision = .allow
            case "deny": decision = .deny(message: p["message"]?.string)
            case "terminal": decision = .terminal
            default: decision = nil
            }
            let known = pending.contains { $0.id == id }
            if let decision, known { resolve(id, decision) }
            send(.object(["resolved": .bool(decision != nil && known)]))
        #endif
        case ControlEvent.diagnostics:
            connection?.reply(Reply(stdout: diagnostics()))
        case ControlEvent.jump:
            let prefix = envelope.payload["id"]?.string ?? ""
            if let target = store.sorted.first(where: { $0.id.hasPrefix(prefix) }) {
                send(.object(["session": .string(target.id), "result": .string(jump(target))]))
            } else {
                send(.object(["result": "No session matches that id"]))
            }
        default:
            connection?.reply(.passthroughReply)
        }
    }

    func reap() {
        let removed = Set(store.reap(isAlive: ProcessTree.isAlive))
        var changed = !removed.isEmpty
        // A session whose process is gone can't be waiting for an answer any more.
        for request in pending where removed.contains(request.sessionID) {
            finish(request.id, reply: .passthroughReply, note: "session ended")
        }
        if let after = autoClearAfter, store.dismissFinished(olderThan: after) > 0 { changed = true }
        if changed { publishSessions() }
        // A window that has reset since the last report no longer applies.
        if let u = usage {
            let live = u.current()
            if live != u { usage = live.isEmpty ? nil : live }
        }
    }

    /// Installs the helper and hooks. The helper goes first: hooks that point at a missing helper
    /// would silently do nothing.
    @discardableResult
    func installIntegration(statusLine: Bool = true) throws -> Installer.Change {
        defer { refreshHookStatus() }
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ravenisland-bridge")
        try AppPaths.ensureRoot()
        try Installer.installBridge(from: helper)
        if let executable = Bundle.main.executableURL { try Installer.recordAppExecutable(executable) }
        var installer = Installer()
        installer.legacyRoot = AppPaths.legacyRoot
        return try installer.install(statusLine: statusLine)
    }

    @discardableResult
    func uninstallIntegration() throws -> Installer.Change {
        defer { refreshHookStatus() }
        var installer = Installer()
        installer.legacyRoot = AppPaths.legacyRoot
        return try installer.uninstall()
    }

    var isConnected: Bool { hookStatus?.isFullyInstalled == true && FileManager.default.isExecutableFile(atPath: AppPaths.installedBridge.path) }

    func refreshHookStatus() {
        hookStatus = try? Installer().status()
    }
}
