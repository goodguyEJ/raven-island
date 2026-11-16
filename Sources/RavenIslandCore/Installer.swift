import Foundation

/// Adds and removes Raven Island's hook entries in a Claude Code settings file.
/// Never replaces the file wholesale: existing keys and other tools' hooks are preserved,
/// and a timestamped backup is written before any change.
public struct Installer {
    /// Any hook command containing this belongs to Raven Island.
    public static let marker = "/.ravenisland/bin/ravenisland-bridge"
    /// The helper's path under the app's earlier name. Entries pointing there are ours too: they are
    /// replaced on install and removed on uninstall, never left behind as duplicates.
    public static let legacyMarkers = ["/.crowsnest/bin/crowsnest-bridge"]

    public static func isOurCommand(_ command: String) -> Bool {
        command.contains(marker) || legacyMarkers.contains { command.contains($0) }
    }

    /// `exec` makes the helper the hook process itself, so when Claude Code cancels a hook the helper
    /// goes with it. A missing helper exits 0 so Claude Code is never affected.
    public static let hookCommand = #"B="$HOME/.ravenisland/bin/ravenisland-bridge"; [ -x "$B" ] && exec "$B" hook claude 2>/dev/null; exit 0"#

    /// Events we listen to, with an explicit timeout (seconds) where the default is too short.
    public static let events: [(name: String, timeout: Int?)] = [
        ("SessionStart", nil), ("UserPromptSubmit", nil), ("PreToolUse", 86_400), ("PostToolUse", nil),
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
        /// True when the status line slot still runs the helper, as versions that showed usage set it up.
        public var statusLineInstalled: Bool { statusLine.map(Installer.isOurCommand) == true }
        public var isFullyInstalled: Bool { missing.isEmpty }
    }

    public struct Change: Equatable {
        public var changed: Bool
        public var backup: URL?
    }

    public var settingsURL: URL
    /// Where versions that showed usage remembered the status line they replaced, so it can be put back.
    public var previousStatusLineURL: URL

    /// The app's folder under its earlier name, if this install should migrate from it: its remembered
    /// status line is carried over, and the folder is removed once nothing points at it.
    public var legacyRoot: URL?

    public init(settingsURL: URL = AppPaths.claudeSettings,
                previousStatusLineURL: URL = AppPaths.previousStatusLine) {
        self.settingsURL = settingsURL
        self.previousStatusLineURL = previousStatusLineURL
    }

    // MARK: Status line

    static func isOurStatusLine(_ value: Any?) -> Bool {
        ((value as? [String: Any])?["command"] as? String).map(isOurCommand) == true
    }

    /// Puts back the remembered status line, or clears the slot if there was none.
    static func withoutStatusLine(_ root: [String: Any], previous: [String: Any]?) -> [String: Any] {
        guard isOurStatusLine(root["statusLine"]) else { return root }
        var root = root
        root["statusLine"] = previous
        return root
    }

    /// Files the app itself put in its folder. Anything else (custom sound packs) belongs to the user.
    static let appOwnedFiles = ["bin", "crowsnest.sock", "app-path", "previous-statusline.json"]

    /// Once nothing points at the old folder: user sound packs move to the new folder, the app's own
    /// files go, and the folder itself goes only if that leaves it empty.
    func removeLegacyRootIfUnused() {
        let fm = FileManager.default
        guard let legacyRoot, fm.fileExists(atPath: legacyRoot.path),
              let data = try? Data(contentsOf: targetURL), let text = String(data: data, encoding: .utf8),
              !Self.legacyMarkers.contains(where: { text.contains($0) }) else { return }
        let oldSounds = legacyRoot.appendingPathComponent("sounds", isDirectory: true)
        let newSounds = previousStatusLineURL.deletingLastPathComponent().appendingPathComponent("sounds", isDirectory: true)
        if fm.fileExists(atPath: oldSounds.path), !fm.fileExists(atPath: newSounds.path) {
            try? fm.moveItem(at: oldSounds, to: newSounds)
        }
        for name in Self.appOwnedFiles { try? fm.removeItem(at: legacyRoot.appendingPathComponent(name)) }
        if (try? fm.contentsOfDirectory(atPath: legacyRoot.path))?.isEmpty == true {
            try? fm.removeItem(at: legacyRoot)
        }
    }

    /// Falls back to the old folder, so uninstalling an install never upgraded still puts the
    /// user's own status line back.
    func loadPreviousStatusLine() -> [String: Any]? {
        let candidates = [previousStatusLineURL] + (legacyRoot.map { [$0.appendingPathComponent("previous-statusline.json")] } ?? [])
        for url in candidates {
            if let data = try? Data(contentsOf: url) { return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] }
        }
        return nil
    }

    // MARK: Pure transforms

    static func commands(in group: Any) -> [String] {
        guard let g = group as? [String: Any], let hooks = g["hooks"] as? [[String: Any]] else { return [] }
        return hooks.compactMap { $0["command"] as? String }
    }

    static func isOurs(_ group: Any) -> Bool {
        commands(in: group).contains(where: isOurCommand)
    }

    /// Removes only Raven Island's own commands. A group that held nothing else disappears; a group that
    /// also holds someone else's command keeps it.
    static func strippingOurs(_ groups: [Any]) -> [Any] {
        groups.compactMap { group -> Any? in
            guard isOurs(group), var g = group as? [String: Any], let hooks = g["hooks"] as? [[String: Any]] else { return group }
            let rest = hooks.filter { !(($0["command"] as? String).map(isOurCommand) ?? false) }
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

    /// Keeps the newest few Raven Island backups; older ones are deleted so copies of the settings file
    /// (which can hold secrets) don't pile up.
    func pruneBackups() {
        let fm = FileManager.default
        let dir = targetURL.deletingLastPathComponent()
        let prefix = targetURL.lastPathComponent + ".ravenisland-backup-"
        let mine = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasPrefix(prefix) }.sorted()
        for name in mine.dropLast(Self.backupsKept) { try? fm.removeItem(at: dir.appendingPathComponent(name)) }
    }

    /// Copies the helper into `~/.ravenisland/bin`. Hooks point there, so installing them without it would
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
            var candidate = settingsURL.appendingPathExtension("ravenisland-backup-" + f.string(from: now))
            var n = 1
            while fm.fileExists(atPath: candidate.path) {
                n += 1
                candidate = settingsURL.appendingPathExtension("ravenisland-backup-\(f.string(from: now))-\(n)")
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
    public func install(now: Date = Date()) throws -> Change {
        let fm = FileManager.default
        if let legacyRoot, !fm.fileExists(atPath: previousStatusLineURL.path) {
            let old = legacyRoot.appendingPathComponent("previous-statusline.json")
            if fm.fileExists(atPath: old.path) {
                try fm.createDirectory(at: previousStatusLineURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: old, to: previousStatusLineURL)
            }
        }
        defer { removeLegacyRootIfUnused() }
        let (root, exists) = try load()
        let next = Self.withoutStatusLine(Self.merged(root), previous: loadPreviousStatusLine())
        if exists, NSDictionary(dictionary: root).isEqual(to: next) { return Change(changed: false, backup: nil) }
        let change = Change(changed: true, backup: try write(next, hadFile: exists, now: now))
        if Self.isOurStatusLine(root["statusLine"]) { try? fm.removeItem(at: previousStatusLineURL) }
        return change
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
