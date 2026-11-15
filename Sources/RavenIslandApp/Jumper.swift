import AppKit
import RavenIslandCore

/// Brings the terminal that owns a session to the front, as precisely as that terminal allows.
@MainActor
enum Jumper {
    /// Returns a short description of what was done, for the event log and the CLI.
    @discardableResult
    static func jump(to session: Session) -> String {
        let context = session.context
        let chain = context.ancestors.map(\.pid)

        // Inside tmux the process tree leads to the tmux server, not the terminal: select the pane,
        // then follow the attached client to find the terminal app.
        var notes: [String] = []
        if let pane = context.tmuxPane, let env = context.tmux,
           let socket = JumpPlanning.tmuxSocket(fromEnv: env), JumpPlanning.isSafeTmuxPane(pane),
           let tmux = JumpPlanning.tmuxExecutable() {
            // Off the main thread and time-limited: a stuck tmux server must not freeze the panel.
            let termProgram = context.termProgram
            DispatchQueue.global(qos: .userInitiated).async {
                _ = run(tmux, ["-S", socket, "select-window", "-t", pane], timeout: 2)
                _ = run(tmux, ["-S", socket, "select-pane", "-t", pane], timeout: 2)
                var clientChain: [Int32] = []
                if let clients = run(tmux, ["-S", socket, "list-clients", "-F", "#{client_pid}"], timeout: 2),
                   let pid = clients.split(separator: "\n").first.flatMap({ Int32($0) }) {
                    clientChain = ProcessTree.ancestors(of: pid).chain.map(\.pid)
                }
                DispatchQueue.main.async {
                    if let app = owningApp(chain: clientChain, termProgram: termProgram) { open(app, with: []) }
                }
            }
            return "selected tmux pane \(pane)"
        }

        guard let app = owningApp(chain: chain, termProgram: context.termProgram) else {
            return "No terminal found for this session"
        }
        let bundleID = app.bundleID ?? ""
        let name = app.name

        if bundleID == "com.mitchellh.ghostty", let tty = context.tty,
           let script = JumpPlanning.ghosttyScript(tty: tty) {
            runScript(script, fallback: app)
            notes.append("asked Ghostty to focus \(tty)")
        } else if bundleID == "com.apple.Terminal", let tty = context.tty,
                  let script = JumpPlanning.appleTerminalScript(tty: tty) {
            runScript(script, fallback: app)
            notes.append("asked Terminal to select \(tty)")
        } else if let support = JumpPlanning.vscodeFamily[bundleID], let cwd = session.cwd,
                  let folder = workspaceFolder(appSupportName: support, cwd: cwd) {
            // Opening a folder that is already open focuses its window instead of making a new one.
            open(app, with: [URL(fileURLWithPath: folder, isDirectory: true)])
            notes.append("focused the \(name) window for \(URL(fileURLWithPath: folder).lastPathComponent)")
        } else {
            open(app, with: [])
            notes.append("brought \(name) to the front")
        }
        return notes.joined(separator: "; ")
    }

    // MARK: Finding the app

    struct TargetApp {
        var url: URL
        var bundleID: String?
        var name: String
    }

    /// The nearest ancestor process that is a regular (Dock-visible) app.
    static func owningApp(chain: [Int32], termProgram: String?) -> TargetApp? {
        for pid in chain {
            guard let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular,
                  let url = app.bundleURL else { continue }
            return TargetApp(url: url, bundleID: app.bundleIdentifier, name: app.localizedName ?? url.lastPathComponent)
        }
        // The process tree is gone (e.g. the event was captured before a restart): go by the terminal's name.
        if let term = termProgram, let bundleID = JumpPlanning.bundleForTermProgram[term],
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return TargetApp(url: url, bundleID: bundleID, name: url.deletingPathExtension().lastPathComponent)
        }
        return nil
    }

    private static func workspaceFolder(appSupportName: String, cwd: String) -> String? {
        let storage = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(appSupportName)/User/globalStorage/storage.json")
        guard let data = try? Data(contentsOf: storage) else { return nil }
        return JumpPlanning.workspaceFolder(for: cwd, among: JumpPlanning.openFolders(inStorage: data))
    }

    // MARK: Doing it

    private static func open(_ app: TargetApp, with urls: [URL]) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        if urls.isEmpty {
            NSWorkspace.shared.openApplication(at: app.url, configuration: config)
        } else {
            NSWorkspace.shared.open(urls, withApplicationAt: app.url, configuration: config)
        }
    }

    /// Runs an AppleScript off the main thread. If it fails or finds nothing (for example the user
    /// has not allowed Raven Island to control that app), fall back to just bringing the app forward.
    private static func runScript(_ source: String, fallback app: TargetApp) {
        DispatchQueue.global(qos: .userInitiated).async {
            let output = run("/usr/bin/osascript", ["-e", source], timeout: 20)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if output != "focused" {
                DispatchQueue.main.async { open(app, with: []) }
            }
        }
    }

    /// Runs a tool and returns its stdout, or nil if it could not run, exited non-zero, or ran past `timeout`.
    nonisolated static func run(_ tool: String, _ arguments: [String], timeout: TimeInterval = 10) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()
        return process.terminationStatus == 0 ? String(data: data, encoding: .utf8) : nil
    }
}
