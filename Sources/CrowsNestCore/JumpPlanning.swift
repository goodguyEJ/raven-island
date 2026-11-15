import Foundation

/// The pure parts of "jump to terminal": no AppKit, so they can be unit-tested.
public enum JumpPlanning {
    /// Bundle ids of editors built on VS Code, with the folder name each uses under Application Support.
    public static let vscodeFamily: [String: String] = [
        "com.microsoft.VSCode": "Code",
        "com.microsoft.VSCodeInsiders": "Code - Insiders",
        "com.vscodium": "VSCodium",
        "com.todesktop.230313mzl4w4u92": "Cursor",
        "com.exafunction.windsurf": "Windsurf",
    ]

    /// Used only when the session's process tree can no longer be inspected.
    public static let bundleForTermProgram: [String: String] = [
        "ghostty": "com.mitchellh.ghostty",
        "vscode": "com.microsoft.VSCode",
        "Apple_Terminal": "com.apple.Terminal",
        "iTerm.app": "com.googlecode.iterm2",
        "WarpTerminal": "dev.warp.Warp-Stable",
        "WezTerm": "com.github.wez.wezterm",
    ]

    /// Only device paths like /dev/ttys004 are ever interpolated into a script.
    public static func isSafeTTY(_ tty: String) -> Bool {
        tty.range(of: #"\A/dev/tty[a-z0-9]+\z"#, options: .regularExpression) != nil
    }

    public static func ghosttyScript(tty: String) -> String? {
        guard isSafeTTY(tty) else { return nil }
        return """
        tell application "Ghostty"
            set matches to (every terminal whose tty is "\(tty)")
            if (count of matches) is 0 then return "not-found"
            focus (item 1 of matches)
            activate
            return "focused"
        end tell
        """
    }

    public static func appleTerminalScript(tty: String) -> String? {
        guard isSafeTTY(tty) else { return nil }
        return """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then
                        set selected of t to true
                        set index of w to 1
                        activate
                        return "focused"
                    end if
                end repeat
            end repeat
            return "not-found"
        end tell
        """
    }

    /// Folders open in a VS Code-family editor, read from its window-state file.
    public static func openFolders(inStorage data: Data) -> [String] {
        guard let root = JSONValue.parse(data), let state = root["windowsState"] else { return [] }
        var windows = state["openedWindows"]?.array ?? []
        if let last = state["lastActiveWindow"] { windows.append(last) }
        var folders: [String] = []
        for w in windows {
            guard let uri = w["folder"]?.string, let url = URL(string: uri), url.isFileURL else { continue }
            let path = url.path
            if !folders.contains(path) { folders.append(path) }
        }
        return folders
    }

    /// The open folder that contains `cwd`, preferring the deepest match.
    public static func workspaceFolder(for cwd: String, among folders: [String]) -> String? {
        let target = URL(fileURLWithPath: cwd).standardizedFileURL.path
        return folders
            .map { URL(fileURLWithPath: $0).standardizedFileURL.path }
            .filter { target == $0 || target.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
            .max { $0.count < $1.count }
    }

    /// `TMUX` looks like "/private/tmp/tmux-501/default,1234,0"; the socket is the first field.
    public static func tmuxSocket(fromEnv tmux: String) -> String? {
        let socket = tmux.split(separator: ",").first.map(String.init) ?? ""
        return socket.hasPrefix("/") ? socket : nil
    }

    /// A GUI app's PATH has no Homebrew folders, so look in the usual places.
    public static func tmuxExecutable(exists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"].first(where: exists)
    }

    public static func isSafeTmuxPane(_ pane: String) -> Bool {
        pane.range(of: #"\A%[0-9]+\z"#, options: .regularExpression) != nil
    }
}
