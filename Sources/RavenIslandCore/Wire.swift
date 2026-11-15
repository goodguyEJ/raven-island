import Foundation

public struct AncestorProcess: Codable, Equatable, Sendable {
    public var pid: Int32
    public var name: String
    public init(pid: Int32, name: String) { self.pid = pid; self.name = name }
}

/// Where a session is running, captured by the bridge from its own environment.
public struct TerminalContext: Codable, Equatable, Sendable {
    public var termProgram: String?
    public var tty: String?
    public var tmux: String?
    public var tmuxPane: String?
    public var ancestors: [AncestorProcess]
    public var agentPid: Int32?
    public var host: String?

    public init(termProgram: String? = nil, tty: String? = nil, tmux: String? = nil, tmuxPane: String? = nil,
                ancestors: [AncestorProcess] = [], agentPid: Int32? = nil, host: String? = nil) {
        self.termProgram = termProgram; self.tty = tty; self.tmux = tmux; self.tmuxPane = tmuxPane
        self.ancestors = ancestors; self.agentPid = agentPid; self.host = host
    }
}

/// bridge → app
public struct Envelope: Codable, Equatable, Sendable {
    public static let version = 1
    public var v: Int
    public var agent: String
    public var event: String
    public var blocking: Bool
    public var payload: JSONValue
    public var context: TerminalContext

    public init(agent: String, event: String, blocking: Bool, payload: JSONValue, context: TerminalContext) {
        self.v = Self.version; self.agent = agent; self.event = event
        self.blocking = blocking; self.payload = payload; self.context = context
    }

    public var sessionID: String? { payload["session_id"]?.string }

    /// Fast decode (see `JSONValue.parse`). Nil for anything that isn't a well-formed envelope.
    public static func decode(_ data: Data) -> Envelope? {
        guard let root = JSONValue.parse(data), let v = root["v"]?.number, let agent = root["agent"]?.string,
              let event = root["event"]?.string, let blocking = root["blocking"]?.bool, let payload = root["payload"],
              let contextValue = root["context"],
              let contextData = try? JSONEncoder().encode(contextValue),
              let context = try? JSONDecoder().decode(TerminalContext.self, from: contextData) else { return nil }
        var envelope = Envelope(agent: agent, event: event, blocking: blocking, payload: payload, context: context)
        envelope.v = Int(v)
        return envelope
    }
}

/// Keys of a hook payload that Raven Island never uses and that can be very large (a tool's full
/// output, the agent's last message). The bridge drops them before sending, so a big search result
/// costs nothing.
public enum PayloadTrim {
    public static let droppedKeys: Set<String> = ["tool_response", "last_assistant_message", "transcript_path"]

    /// Parses stdin, removes the dropped keys before the (comparatively slow) conversion, and returns the rest.
    public static func parse(_ data: Data) -> JSONValue? {
        guard var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        for key in droppedKeys { object[key] = nil }
        return JSONValue(foundation: object)
    }
}

/// app → bridge, for blocking events only.
public struct Reply: Codable, Equatable, Sendable {
    public var v: Int
    /// Exact text the bridge prints for the agent to read.
    public var stdout: String?
    /// Print nothing; the agent falls back to its normal behaviour.
    public var passthrough: Bool?
    /// Not an answer: the app's main thread has the request on screen and the bridge should keep waiting.
    /// A bridge that gets neither this nor an answer within a couple of seconds gives up and passes through,
    /// so a hung app cannot hold a permission request hostage.
    public var ack: Bool?

    public static let passthroughReply = Reply(v: Envelope.version, stdout: nil, passthrough: true)
    public static let ackReply = Reply(v: Envelope.version, stdout: nil, passthrough: nil, ack: true)
    public init(v: Int = Envelope.version, stdout: String?, passthrough: Bool? = nil, ack: Bool? = nil) {
        self.v = v; self.stdout = stdout; self.passthrough = passthrough; self.ack = ack
    }
}

/// Event name the bridge uses when forwarding status line input (not a Claude Code hook event).
public enum StatusLineEvent {
    public static let name = "StatusLine"
}

/// Events for which the bridge waits for a reply.
/// Internal requests from the `ravenisland-bridge` CLI to the app (not hook events).
public enum ControlEvent {
    public static let agent = "ravenisland"
    public static let sessions = "sessions"
    public static let pending = "pending"
    public static let resolve = "resolve"
    public static let jump = "jump"
    public static let diagnostics = "diagnostics"
}

public enum BlockingEvents {
    public static func isBlocking(event: String, payload: JSONValue) -> Bool {
        if event == "PermissionRequest" { return true }
        // Questions are answered from the PreToolUse hook, so that one call has to wait too.
        return event == "PreToolUse" && payload["tool_name"]?.string == "AskUserQuestion"
    }
}

public enum AppPaths {
    /// Debug builds honour `RAVENISLAND_HOME` so tests can run beside the real app. Release builds ignore it:
    /// the environment must not be able to redirect the socket that carries approval decisions.
    public static var root: URL {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["RAVENISLAND_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        #endif
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ravenisland", isDirectory: true)
    }
    public static var socket: URL { root.appendingPathComponent("ravenisland.sock") }
    /// The app's executable path, written by the app at launch. The helper only accepts decisions from
    /// a process running exactly this file.
    public static var appExecutableRecord: URL { root.appendingPathComponent("app-path") }
    public static var binDir: URL { root.appendingPathComponent("bin", isDirectory: true) }
    public static var installedBridge: URL { binDir.appendingPathComponent("ravenisland-bridge") }
    public static var previousStatusLine: URL { root.appendingPathComponent("previous-statusline.json") }
    /// The app's folder under its earlier name (Crow's Nest). Nil in test builds pointed elsewhere, so
    /// tests never touch a real install.
    public static var legacyRoot: URL? {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["RAVENISLAND_HOME"], !override.isEmpty { return nil }
        #endif
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".crowsnest", isDirectory: true)
    }
    public static var claudeSettings: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    public static func ensureRoot() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        // An existing folder keeps whatever mode it had; make sure only the user can reach the socket.
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    }
}
