import Foundation
import RavenIslandCore

// ravenisland-bridge: run by the agent as a hook command. It must never break the agent:
// every failure path exits 0 with no output, which leaves the agent's normal behaviour in place.

/// Only a process running the real app may receive events or answer requests. The app records its
/// executable path at launch; anything else listening on the socket (for example a process that
/// replaced the socket file) is ignored and Claude Code behaves as if Raven Island were not there.
func isTrustedPeer(fd: Int32) -> Bool {
    guard let pid = UnixSocket.peerPID(fd: fd), let path = UnixSocket.executablePath(pid: pid) else { return false }
    var allowed: [String] = []
    if let recorded = try? String(contentsOf: AppPaths.appExecutableRecord, encoding: .utf8) {
        allowed.append(URL(fileURLWithPath: recorded.trimmingCharacters(in: .whitespacesAndNewlines)).resolvingSymlinksInPath().path)
    }
    #if DEBUG
    // Test builds: the app binary sitting next to this helper.
    let me = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    allowed.append(me.deletingLastPathComponent().appendingPathComponent("RavenIslandApp").resolvingSymlinksInPath().path)
    #endif
    return allowed.contains(path)
}

func runHook(agent: String) -> Never {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    // Large fields the app never uses (a tool's full output) are dropped before anything else.
    guard let payload = PayloadTrim.parse(input), let event = payload["hook_event_name"]?.string else { exit(0) }

    let env = ProcessInfo.processInfo.environment
    let (chain, tty) = ProcessTree.ancestors()
    let context = TerminalContext(
        termProgram: env["TERM_PROGRAM"], tty: tty, tmux: env["TMUX"], tmuxPane: env["TMUX_PANE"],
        ancestors: chain, agentPid: ProcessTree.agentPid(in: chain), host: nil)
    let blocking = BlockingEvents.isBlocking(event: event, payload: payload)
    let envelope = Envelope(agent: agent, event: event, blocking: blocking, payload: payload, context: context)
    let parent = getppid()

    do {
        let fd = try UnixSocket.connect(path: AppPaths.socket.path)
        defer { close(fd) }
        guard isTrustedPeer(fd: fd) else { exit(0) }
        UnixSocket.setTimeouts(fd: fd, sendMs: 150, recvMs: 0)
        try UnixSocket.sendFrame(fd: fd, try JSONEncoder().encode(envelope))
        guard blocking else { exit(0) }
        // The app acknowledges at once, then sends a heartbeat every second from its main thread while
        // the card is up. Silence (2 s before the first, 3 s between heartbeats) means it is hung:
        // pass through so Claude Code's own prompt takes over.
        var timeoutMs = 2000
        while true {
            UnixSocket.setTimeouts(fd: fd, sendMs: 150, recvMs: timeoutMs)
            let reply = try JSONDecoder().decode(Reply.self, from: try UnixSocket.readFrame(fd: fd))
            if reply.ack == true {
                // If Claude Code went away without cancelling us, stop waiting.
                if getppid() != parent { exit(0) }
                timeoutMs = 3000
                continue
            }
            if reply.passthrough != true, let out = reply.stdout, !out.isEmpty,
               ReplyPolicy.isAcceptable(out, for: payload) {
                FileHandle.standardOutput.write(Data(out.utf8))
            }
            break
        }
    } catch {
        // App not running, hung, or it hung up: say nothing.
    }
    exit(0)
}

/// Sends a request to the running app and prints its answer.
func runControl(_ event: String, payload: [String: JSONValue] = [:]) -> Never {
    let envelope = Envelope(agent: ControlEvent.agent, event: event, blocking: true,
                            payload: .object(payload), context: TerminalContext())
    do {
        let fd = try UnixSocket.connect(path: AppPaths.socket.path)
        defer { close(fd) }
        UnixSocket.setTimeouts(fd: fd, sendMs: 500, recvMs: 2000)
        try UnixSocket.sendFrame(fd: fd, try JSONEncoder().encode(envelope))
        let reply = try JSONDecoder().decode(Reply.self, from: try UnixSocket.readFrame(fd: fd))
        print(reply.stdout ?? "", terminator: "")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("Raven Island is not running.\n".utf8))
        exit(1)
    }
}

/// Runs as Claude Code's status line command: passes the usage data to Raven Island, then runs whatever
/// status line was configured before, so the line the user sees is unchanged.
func runStatusLine() -> Never {
    // The chained command may exit without reading its input; that must not kill us.
    signal(SIGPIPE, SIG_IGN)
    let input = FileHandle.standardInput.readDataToEndOfFile()
    if let payload = JSONValue.parse(input), payload["rate_limits"] != nil,
       let fd = try? UnixSocket.connect(path: AppPaths.socket.path) {
        UnixSocket.setTimeouts(fd: fd, sendMs: 100, recvMs: 0)
        let envelope = Envelope(agent: "claude", event: StatusLineEvent.name, blocking: false,
                                payload: payload, context: TerminalContext())
        if let body = try? JSONEncoder().encode(envelope) { try? UnixSocket.sendFrame(fd: fd, body) }
        close(fd)
    }
    if let data = try? Data(contentsOf: AppPaths.previousStatusLine),
       let previous = JSONValue.parse(data), let command = previous["command"]?.string,
       !Installer.isOurCommand(command) {   // never chain to ourselves
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        let stdin = Pipe()
        process.standardInput = stdin
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.nullDevice
        if (try? process.run()) != nil {
            stdin.fileHandleForWriting.write(input)
            try? stdin.fileHandleForWriting.close()
            process.waitUntilExit()
        }
    }
    exit(0)
}

func settingsURL(_ args: [String]) -> URL {
    if let i = args.firstIndex(of: "--settings"), i + 1 < args.count {
        return URL(fileURLWithPath: args[i + 1])
    }
    return AppPaths.claudeSettings
}

func copySelfToInstallLocation() throws {
    try AppPaths.ensureRoot()
    let me = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    try Installer.installBridge(from: me)
    // Run from inside the app bundle: record the app as the trusted peer (the app also does this at launch).
    let app = me.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("MacOS/Raven Island")
    if me.deletingLastPathComponent().lastPathComponent == "Helpers", FileManager.default.isExecutableFile(atPath: app.path) {
        try Installer.recordAppExecutable(app)
    }
}

func printStatus(_ s: Installer.Status) {
    print("Hooks: \(s.installed.count)/\(Installer.events.count) installed" +
          (s.missing.isEmpty ? "" : " (missing: \(s.missing.joined(separator: ", ")))"))
    print("Bridge binary: " + (FileManager.default.isExecutableFile(atPath: AppPaths.installedBridge.path)
                               ? AppPaths.installedBridge.path : "not installed"))
    if !s.otherPermissionHooks.isEmpty {
        print("Note: another tool also handles permission requests. Only one should answer them:")
        for c in s.otherPermissionHooks { print("  " + c) }
    }
    if s.statusLineInstalled {
        var chained = "nothing"
        if let data = try? Data(contentsOf: AppPaths.previousStatusLine),
           let command = JSONValue.parse(data)?["command"]?.string { chained = command }
        print("Status line: Raven Island (for usage), then: \(chained)")
    } else if let line = s.statusLine {
        print("Status line: \(line) (usage display is off; run install to enable it)")
    } else {
        print("Status line: not set (usage display is off; run install to enable it)")
    }
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "hook":
    runHook(agent: args.count > 1 ? args[1] : "claude")
case "statusline":
    runStatusLine()
case "sessions":
    runControl(ControlEvent.sessions)
case "pending":
    runControl(ControlEvent.pending)
case "diagnostics":
    runControl(ControlEvent.diagnostics)
case "jump":
    runControl(ControlEvent.jump, payload: ["id": .string(args.count > 1 ? args[1] : "")])
#if DEBUG
case "resolve":
    // Test builds only. A release build must not let any local process (including the agent being
    // supervised) answer a waiting request.
    var payload: [String: JSONValue] = ["decision": .string(args.count > 1 ? args[1] : "")]
    if let i = args.firstIndex(of: "--id"), i + 1 < args.count { payload["id"] = .string(args[i + 1]) }
    if let i = args.firstIndex(of: "--message"), i + 1 < args.count { payload["message"] = .string(args[i + 1]) }
    runControl(ControlEvent.resolve, payload: payload)
#endif
case "install", "uninstall", "status":
    var installer = Installer(settingsURL: settingsURL(args))
    installer.legacyRoot = args.contains("--settings") ? nil : AppPaths.legacyRoot
    do {
        switch args[0] {
        case "install":
            try copySelfToInstallLocation()
            let change = try installer.install(statusLine: !args.contains("--no-statusline"))
            print(change.changed ? "Installed hooks in \(installer.settingsURL.path)" : "Hooks already installed; nothing changed.")
            if let b = change.backup { print("Backup: \(b.path)") }
        case "uninstall":
            let change = try installer.uninstall()
            print(change.changed ? "Removed Raven Island hooks from \(installer.settingsURL.path)" : "No Raven Island hooks found; nothing changed.")
            if let b = change.backup { print("Backup: \(b.path)") }
        default: break
        }
        printStatus(try installer.status())
    } catch {
        FileHandle.standardError.write(Data("ravenisland-bridge: \(error)\n".utf8))
        exit(1)
    }
default:
    print("""
    usage: ravenisland-bridge hook [agent]          read a hook event on stdin and forward it to Raven Island
           ravenisland-bridge install [--settings PATH] [--no-statusline]
           ravenisland-bridge statusline               status line command: report usage, then run the previous one
           ravenisland-bridge uninstall [--settings PATH]
           ravenisland-bridge status [--settings PATH]
           ravenisland-bridge sessions                 print the running app's session states as JSON (no prompts or paths)
           ravenisland-bridge pending                  list requests waiting for an answer (no contents)
           ravenisland-bridge jump SESSION-ID-PREFIX   bring that session's terminal to the front
           ravenisland-bridge diagnostics              print a troubleshooting report (no prompts or commands)
    """)
    exit(args.isEmpty || args.first == "help" || args.first == "--help" ? 0 : 2)
}
