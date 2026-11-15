import Foundation

/// Adds and removes Crow's Nest's hook entries in a Claude Code settings file.
/// Never replaces the file wholesale: existing keys and other tools' hooks are preserved,
/// and a timestamped backup is written before any change.
public struct Installer {
    /// Any hook command containing this belongs to Crow's Nest.
    public static let marker = "/.crowsnest/bin/crowsnest-bridge"

    /// `exec` makes the helper the hook process itself, so when Claude Code cancels a hook the helper
    /// goes with it. A missing helper exits 0 so Claude Code is never affected.
    public static let hookCommand = #"B="$HOME/.crowsnest/bin/crowsnest-bridge"; [ -x "$B" ] && exec "$B" hook claude 2>/dev/null; exit 0"#
    public static let statusLineCommand = #"B="$HOME/.crowsnest/bin/crowsnest-bridge"; [ -x "$B" ] && exec "$B" statusline 2>/dev/null; exit 0"#

    /// Events we listen to, with an explicit timeout (seconds) where the default is too short.
    public static let events: [(name: String, timeout: Int?)] = [
        ("SessionStart", nil), ("UserPromptSubmit", nil), ("PreToolUse", nil), ("PostToolUse", nil),
        ("PostToolUseFailure", nil), ("PermissionRequest", 86_400), ("Notification", nil),
        ("SubagentStart", nil), ("SubagentStop", nil), ("PreCompact", nil), ("PostCompact", nil),
        ("Stop", nil), ("StopFailure", nil), ("SessionEnd", nil),
    ]

    public enum InstallError: Error, CustomStringConvertible {
        case invalidSettings(String)
        public var description: String {
            switch self { case .invalidSettings(let why): return "Settings file left untouched: \(why)" }
        }
    }

    public struct Status: Equatable {
        public var settingsExists: Bool
        public var installed: [String]
        public var missing: [String]
        /// Commands from other tools on PermissionRequest; two tools must not both answer it.
        public var otherPermissionHooks: [String]
        public var statusLine: String?
        /// True when the status line slot runs Crow's Nest's helper (which then runs the previous command).
        public var statusLineInstalled: Bool { statusLine?.contains(Installer.marker) == true }
        public var isFullyInstalled: Bool { missing.isEmpty }
    }

    public struct Change: Equatable {
        public var changed: Bool
        public var backup: URL?
    }

    public var settingsURL: URL
    /// Where the status line that was configured before Crow's Nest is remembered, so it can keep
    /// running underneath ours and be put back on uninstall.
    public var previousStatusLineURL: URL

    public init(settingsURL: URL = AppPaths.claudeSettings,
                previousStatusLineURL: URL = AppPaths.previousStatusLine) {
        self.settingsURL = settingsURL
        self.previousStatusLineURL = previousStatusLineURL
    }

    // MARK: Status line

    static func isOurStatusLine(_ value: Any?) -> Bool {
        ((value as? [String: Any])?["command"] as? String)?.contains(marker) == true
    }

    /// Takes over the status line slot. Returns the previous entry if there was one to remember.
    static func withStatusLine(_ root: [String: Any]) -> (root: [String: Any], previous: [String: Any]?) {
        guard !isOurStatusLine(root["statusLine"]) else { return (root, nil) }
        var root = root
        let previous = root["statusLine"] as? [String: Any]
        var ours: [String: Any] = ["type": "command", "command": statusLineCommand]
        // Keep the user's display options so their status line behaves as before.
        for key in ["padding", "refreshInterval"] { if let value = previous?[key] { ours[key] = value } }
        root["statusLine"] = ours
        return (root, previous)
    }

    /// Puts back the remembered status line, or clears the slot if there was none.
    static func withoutStatusLine(_ root: [String: Any], previous: [String: Any]?) -> [String: Any] {
        guard isOurStatusLine(root["statusLine"]) else { return root }
        var root = root
        root["statusLine"] = previous
        return root
    }

    func loadPreviousStatusLine() -> [String: Any]? {
        guard let data = try? Data(contentsOf: previousStatusLineURL) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: Pure transforms

    static func commands(in group: Any) -> [String] {
        guard let g = group as? [String: Any], let hooks = g["hooks"] as? [[String: Any]] else { return [] }
        return hooks.compactMap { $0["command"] as? String }
    }

    static func isOurs(_ group: Any) -> Bool {
        commands(in: group).contains { $0.contains(marker) }
    }

    /// Removes only Crow's Nest's own commands. A group that held nothing else disappears; a group that
    /// also holds someone else's command keeps it.
    static func strippingOurs(_ groups: [Any]) -> [Any] {
        groups.compactMap { group -> Any? in
            guard isOurs(group), var g = group as? [String: Any], let hooks = g["hooks"] as? [[String: Any]] else { return group }
            let rest = hooks.filter { !(($0["command"] as? String)?.contains(marker) ?? false) }
            if rest.isEmpty { return nil }
            g["hooks"] = rest
            return g
        }
    }

    static func ourGroup(timeout: Int?) -> [String: Any] {
        var hook: [String: Any] = ["type": "command", "command": hookCommand]
        if let timeout { hook["timeout"] = timeout }
        return ["hooks": [hook]]
    }

    public static func merged(_ root: [String: Any]) -> [String: Any] {
        var root = root
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for (event, timeout) in events {
            var groups = strippingOurs(hooks[event] as? [Any] ?? [])
            groups.append(ourGroup(timeout: timeout))
            hooks[event] = groups
        }
        root["hooks"] = hooks
        return root
    }

    public static func removed(_ root: [String: Any]) -> [String: Any] {
        var root = root
        guard var hooks = root["hooks"] as? [String: Any] else { return root }
        for (event, value) in hooks {
            guard let all = value as? [Any] else { continue }
            let groups = strippingOurs(all)
            if groups.isEmpty { hooks[event] = nil } else { hooks[event] = groups }
        }
        if hooks.isEmpty { root["hooks"] = nil } else { root["hooks"] = hooks }
        return root
    }

    public static func status(of root: [String: Any], exists: Bool) -> Status {
        let hooks = root["hooks"] as? [String: Any] ?? [:]
        var installed: [String] = [], missing: [String] = []
        for (event, _) in events {
            let groups = hooks[event] as? [Any] ?? []
            if groups.contains(where: isOurs) { installed.append(event) } else { missing.append(event) }
        }
        let others = (hooks["PermissionRequest"] as? [Any] ?? [])
            .filter { !isOurs($0) }.flatMap(commands(in:))
        let statusLine = (root["statusLine"] as? [String: Any])?["command"] as? String
        return Status(settingsExists: exists, installed: installed, missing: missing,
                      otherPermissionHooks: others, statusLine: statusLine)
    }

    // MARK: File operations

    /// The real file behind `settingsURL`. If the settings file is a symlink (a dotfiles setup), reads,
    /// backups, and writes all go to its target so the link itself is never replaced.
    var targetURL: URL { settingsURL.resolvingSymlinksInPath() }

    func load() throws -> (root: [String: Any], exists: Bool) {
        let settingsURL = targetURL
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return ([:], false) }
        let data = try Data(contentsOf: settingsURL)
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return ([:], true) }
        guard let obj = try? JSONSerialization.jsonObject(with: data) else {
            throw InstallError.invalidSettings("\(settingsURL.path) is not valid JSON")
        }
        guard let root = obj as? [String: Any] else {
            throw InstallError.invalidSettings("\(settingsURL.path) is not a JSON object")
        }
        return (root, true)
    }

    public static let backupsKept = 5

    /// Keeps the newest few Crow's Nest backups; older ones are deleted so copies of the settings file
    /// (which can hold secrets) don't pile up.
    func pruneBackups() {
        let fm = FileManager.default
        let dir = targetURL.deletingLastPathComponent()
        let prefix = targetURL.lastPathComponent + ".crowsnest-backup-"
        let mine = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasPrefix(prefix) }.sorted()
        for name in mine.dropLast(Self.backupsKept) { try? fm.removeItem(at: dir.appendingPathComponent(name)) }
    }

    /// Copies the helper into `~/.crowsnest/bin`. Hooks point there, so installing them without it would
    /// leave every hook silently doing nothing.
    public static func installBridge(from source: URL, to dest: URL = AppPaths.installedBridge) throws {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: source.path) else {
            throw InstallError.invalidSettings("the helper was not found at \(source.path)")
        }
        guard source.resolvingSymlinksInPath().path != dest.resolvingSymlinksInPath().path else { return }
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmp = dest.appendingPathExtension("new")
        try? fm.removeItem(at: tmp)
        try fm.copyItem(at: source, to: tmp)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
        if fm.fileExists(atPath: dest.path) { _ = try fm.replaceItemAt(dest, withItemAt: tmp) }
        else { try fm.moveItem(at: tmp, to: dest) }
    }

    /// Remembers which executable is the real app, for the helper's peer check.
    public static func recordAppExecutable(_ executable: URL, to record: URL = AppPaths.appExecutableRecord) throws {
        try FileManager.default.createDirectory(at: record.deletingLastPathComponent(), withIntermediateDirectories: true)
        let path = executable.resolvingSymlinksInPath().path
        if (try? String(contentsOf: record, encoding: .utf8)) == path { return }
        try Data(path.utf8).write(to: record, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: record.path)
    }

    func write(_ root: [String: Any], hadFile: Bool, now: Date) throws -> URL? {
        let settingsURL = targetURL
        var backup: URL?
        let fm = FileManager.default
        if hadFile {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyyMMdd-HHmmss"
            var candidate = settingsURL.appendingPathExtension("crowsnest-backup-" + f.string(from: now))
            var n = 1
            while fm.fileExists(atPath: candidate.path) {
                n += 1
                candidate = settingsURL.appendingPathExtension("crowsnest-backup-\(f.string(from: now))-\(n)")
            }
            try fm.copyItem(at: settingsURL, to: candidate)
            backup = candidate
        } else {
            try fm.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        var data = try JSONSerialization.data(withJSONObject: root,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        let perms = (try? fm.attributesOfItem(atPath: settingsURL.path)[.posixPermissions]) as? NSNumber
        try data.write(to: settingsURL, options: .atomic)
        if let perms { try? fm.setAttributes([.posixPermissions: perms], ofItemAtPath: settingsURL.path) }
        pruneBackups()
        return backup
    }

    public func status() throws -> Status {
        let (root, exists) = try load()
        return Self.status(of: root, exists: exists)
    }

    @discardableResult
    public func install(statusLine: Bool = true, now: Date = Date()) throws -> Change {
        let (root, exists) = try load()
        var next = Self.merged(root)
        var previous: [String: Any]?
        var tookOverStatusLine = false
        if statusLine, !Self.isOurStatusLine(next["statusLine"]) {
            (next, previous) = Self.withStatusLine(next)
            tookOverStatusLine = true
        } else if statusLine, var ours = next["statusLine"] as? [String: Any] {
            // Already ours, perhaps from an older version: bring the command up to date and restore the
            // remembered display options.
            ours["command"] = Self.statusLineCommand
            let remembered = loadPreviousStatusLine()
            for key in ["padding", "refreshInterval"] where ours[key] == nil {
                if let value = remembered?[key] { ours[key] = value }
            }
            next["statusLine"] = ours
        }
        if exists, NSDictionary(dictionary: root).isEqual(to: next) { return Change(changed: false, backup: nil) }
        if tookOverStatusLine {
            // Remember (or forget) what was there before, ahead of changing the settings file.
            let fm = FileManager.default
            if let previous {
                try fm.createDirectory(at: previousStatusLineURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONSerialization.data(withJSONObject: previous, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
                    .write(to: previousStatusLineURL, options: .atomic)
            } else {
                try? fm.removeItem(at: previousStatusLineURL)
            }
        }
        return Change(changed: true, backup: try write(next, hadFile: exists, now: now))
    }

    @discardableResult
    public func uninstall(now: Date = Date()) throws -> Change {
        let (root, exists) = try load()
        guard exists else { return Change(changed: false, backup: nil) }
        let next = Self.withoutStatusLine(Self.removed(root), previous: loadPreviousStatusLine())
        if NSDictionary(dictionary: root).isEqual(to: next) { return Change(changed: false, backup: nil) }
        let change = Change(changed: true, backup: try write(next, hadFile: true, now: now))
        try? FileManager.default.removeItem(at: previousStatusLineURL)
        return change
    }
}
