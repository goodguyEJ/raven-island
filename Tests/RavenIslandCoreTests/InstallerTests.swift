import Foundation
import Testing
@testable import RavenIslandCore

@Suite struct InstallerTests {
    let dir: URL
    let settings: URL
    var previous: URL { dir.appendingPathComponent("previous-statusline.json") }
    func installer() -> Installer { Installer(settingsURL: settings, previousStatusLineURL: previous) }

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ravenisland-inst-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        settings = dir.appendingPathComponent("settings.json")
    }

    func write(_ json: String) throws { try Data(json.utf8).write(to: settings) }
    func read() throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any])
    }
    func backups() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains("ravenisland-backup") }
    }

    static let existing = """
    {"model":"opus","theme":"dark","permissions":{"allow":["Bash(ls:*)"]},
     "statusLine":{"type":"command","command":"/usr/local/bin/other-statusline"},
     "hooks":{
       "PermissionRequest":[{"matcher":"*","hooks":[{"type":"command","command":"/opt/other/tool-bridge --x","timeout":86400}]}],
       "Stop":[{"hooks":[{"type":"command","command":"say done"}]}],
       "ConfigChange":[{"hooks":[{"type":"command","command":"echo changed"}]}]
     }}
    """

    @Test func installPreservesEverythingElse() throws {
        try write(Self.existing)
        let installer = installer()
        let change = try installer.install()
        #expect(change.changed)
        #expect(try backups().count == 1)
        // The backup is byte-identical to the original.
        #expect(try Data(contentsOf: #require(change.backup)) == Data(Self.existing.utf8))

        let root = try read()
        #expect(root["model"] as? String == "opus")
        #expect((root["permissions"] as? [String: Any])?["allow"] as? [String] == ["Bash(ls:*)"])
        let hooks = try #require(root["hooks"] as? [String: Any])
        #expect((hooks["ConfigChange"] as? [Any])?.count == 1)
        #expect((hooks["Stop"] as? [Any])?.count == 2)                 // theirs + ours
        #expect((hooks["PermissionRequest"] as? [Any])?.count == 2)

        let status = try installer.status()
        #expect(status.isFullyInstalled)
        #expect(status.installed.count == Installer.events.count)
        #expect(status.otherPermissionHooks == ["/opt/other/tool-bridge --x"])
        // The status line is the user's and stays that way.
        #expect(!status.statusLineInstalled)
        #expect(status.statusLine == "/usr/local/bin/other-statusline")
        #expect(!FileManager.default.fileExists(atPath: previous.path))

        // Blocking hooks (permission requests, and questions via PreToolUse) carry the long timeout.
        for event in ["PermissionRequest", "PreToolUse"] {
            let ours = try #require((hooks[event] as? [[String: Any]])?.last?["hooks"] as? [[String: Any]])
            #expect(ours.first?["timeout"] as? Int == 86_400, "\(event)")
            #expect((ours.first?["command"] as? String)?.contains(Installer.marker) == true)
        }
    }

    @Test func installIsIdempotent() throws {
        try write(Self.existing)
        let installer = installer()
        try installer.install()
        let first = try Data(contentsOf: settings)
        let again = try installer.install()
        #expect(!again.changed)
        #expect(again.backup == nil)
        #expect(try Data(contentsOf: settings) == first)
        #expect(try backups().count == 1)
    }

    @Test func uninstallRestoresOriginalContent() throws {
        try write(Self.existing)
        let installer = installer()
        try installer.install()
        let change = try installer.uninstall()
        #expect(change.changed)
        let original = try #require(JSONSerialization.jsonObject(with: Data(Self.existing.utf8)) as? [String: Any])
        #expect(NSDictionary(dictionary: try read()).isEqual(to: original))
        #expect(try !installer.uninstall().changed)
    }

    @Test func createsSettingsWhenMissing() throws {
        let installer = installer()
        #expect(try installer.status().settingsExists == false)
        let change = try installer.install()
        #expect(change.changed)
        #expect(change.backup == nil)
        #expect(try installer.status().isFullyInstalled)
        try installer.uninstall()
        #expect(try read().isEmpty)
    }

    @Test func installAddsNoStatusLine() throws {
        try write(#"{"model":"opus"}"#)
        try installer().install()
        #expect(try read()["statusLine"] == nil)
        #expect(try installer().status().isFullyInstalled)
    }

    /// Versions that showed usage ran their helper in the status line slot; install gives the slot back.
    @Test func installGivesBackTheStatusLineAnOlderVersionTook() throws {
        try write(#"{"statusLine":{"type":"command","command":"B=\"$HOME/.ravenisland/bin/ravenisland-bridge\"; [ -x \"$B\" ] && exec \"$B\" statusline 2>/dev/null; exit 0","refreshInterval":15}}"#)
        try Data(#"{"type":"command","command":"bash ~/line.sh","refreshInterval":15}"#.utf8).write(to: previous)
        #expect(try installer().install().changed)
        let line = try #require(try read()["statusLine"] as? [String: Any])
        #expect(line["command"] as? String == "bash ~/line.sh")
        #expect(line["refreshInterval"] as? Int == 15)
        #expect(!FileManager.default.fileExists(atPath: previous.path))
        #expect(try !installer().install().changed)
    }

    /// Installing into another settings file must not lose what the main one still needs to give back.
    @Test func installKeepsTheRememberedStatusLineWhenItGivesNothingBack() throws {
        try write(#"{"model":"opus"}"#)
        try Data(#"{"type":"command","command":"bash ~/line.sh"}"#.utf8).write(to: previous)
        #expect(try installer().install().changed)
        #expect(FileManager.default.fileExists(atPath: previous.path))
    }

    @Test func installClearsTheSlotAnOlderVersionTookWhenNothingWasThere() throws {
        try write(#"{"statusLine":{"type":"command","command":"\"$HOME/.ravenisland/bin/ravenisland-bridge\" statusline 2>/dev/null || true"}}"#)
        try installer().install()
        #expect(try read()["statusLine"] == nil)
    }

    @Test func invalidJSONIsLeftUntouched() throws {
        let broken = "{ this is not json"
        try write(broken)
        let installer = installer()
        #expect(throws: Installer.InstallError.self) { try installer.install() }
        #expect(try String(contentsOf: settings, encoding: .utf8) == broken)
        #expect(try backups().isEmpty)
    }

    @Test func olderEntryWithoutTimeoutIsReplaced() throws {
        try write(#"{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"\"$HOME/.ravenisland/bin/ravenisland-bridge\" hook claude 2>/dev/null || true"}]}]}}"#)
        try installer().install()
        let groups = try #require((try read()["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]])
        #expect(groups.count == 1)
        #expect(((groups[0]["hooks"] as? [[String: Any]])?.first?["timeout"] as? Int) == 86_400)
    }

    @Test func staleOwnEntriesAreReplacedNotDuplicated() throws {
        try write(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/old/path/.ravenisland/bin/ravenisland-bridge hook"}]}]}}"#)
        try installer().install()
        let stop = try #require((try read()["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])
        #expect(stop.count == 1)
        #expect(((stop[0]["hooks"] as? [[String: Any]])?.first?["command"] as? String) == Installer.hookCommand)
    }

    @Test func symlinkedSettingsStayASymlink() throws {
        let real = dir.appendingPathComponent("dotfiles-settings.json")
        try Data(Self.existing.utf8).write(to: real)
        try FileManager.default.createSymbolicLink(at: settings, withDestinationURL: real)
        let change = try installer().install()
        let isLink = (try FileManager.default.attributesOfItem(atPath: settings.path)[.type] as? FileAttributeType) == .typeSymbolicLink
        #expect(isLink)
        #expect(try String(contentsOf: real, encoding: .utf8).contains(Installer.marker))      // the real file got the hooks
        #expect(try Data(contentsOf: #require(change.backup)) == Data(Self.existing.utf8))   // backup holds contents, not a link
        try installer().uninstall()
        #expect(try !String(contentsOf: real, encoding: .utf8).contains(Installer.marker))
    }

    @Test func otherCommandsSharingOurGroupSurvive() throws {
        try write(#"{"hooks":{"Stop":[{"matcher":"x","hooks":[{"type":"command","command":"~/.ravenisland/bin/ravenisland-bridge hook claude"},{"type":"command","command":"say done"}]}]}}"#)
        try installer().install()
        try installer().uninstall()
        let stop = try #require((try read()["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])
        #expect(stop.count == 1)
        #expect(stop[0]["matcher"] as? String == "x")
        #expect((stop[0]["hooks"] as? [[String: Any]])?.map { $0["command"] as? String } == ["say done"])
    }

    @Test func oldBackupsArePruned() throws {
        try write(Self.existing)
        for i in 0..<8 {
            try installer().install(now: Date(timeIntervalSince1970: 1_800_000_000 + Double(i) * 60))
            try installer().uninstall(now: Date(timeIntervalSince1970: 1_800_000_030 + Double(i) * 60))
        }
        #expect(try backups().count == Installer.backupsKept)
    }

    @Test func helperIsCopiedAndRequired() throws {
        let dest = dir.appendingPathComponent("bin/ravenisland-bridge")
        #expect(throws: Installer.InstallError.self) {
            try Installer.installBridge(from: dir.appendingPathComponent("missing"), to: dest)
        }
        let source = dir.appendingPathComponent("helper")
        try Data("#!/bin/sh\n".utf8).write(to: source)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source.path)
        try Installer.installBridge(from: source, to: dest)
        try Installer.installBridge(from: source, to: dest)   // replacing an existing copy works too
        #expect(FileManager.default.isExecutableFile(atPath: dest.path))
    }

    @Test func upgradingFromTheEarlierNameLeavesNoDuplicates() throws {
        let legacy = dir.appendingPathComponent("legacy-crowsnest")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data(#"{"type":"command","command":"bash ~/line.sh","refreshInterval":15}"#.utf8)
            .write(to: legacy.appendingPathComponent("previous-statusline.json"))
        let old = #"B=\"$HOME/.crowsnest/bin/crowsnest-bridge\"; [ -x \"$B\" ] && exec \"$B\" hook claude 2>/dev/null; exit 0"#
        let oldLine = #"B=\"$HOME/.crowsnest/bin/crowsnest-bridge\"; [ -x \"$B\" ] && exec \"$B\" statusline 2>/dev/null; exit 0"#
        try write(#"{"statusLine":{"type":"command","command":"\#(oldLine)"},"hooks":{"Stop":[{"hooks":[{"type":"command","command":"\#(old)"}]},{"hooks":[{"type":"command","command":"say done"}]}]}}"#)
        var upgrader = installer()
        upgrader.legacyRoot = legacy
        try upgrader.install()

        let root = try read()
        let stop = try #require((root["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])
        let commands = stop.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
        #expect(commands.filter { $0.contains("crowsnest") }.isEmpty)
        #expect(commands.filter { $0.contains(Installer.marker) }.count == 1)
        #expect(commands.contains("say done"))
        // The status line the earlier version took is given back.
        let line = try #require(root["statusLine"] as? [String: Any])
        #expect(line["command"] as? String == "bash ~/line.sh")
        #expect(line["refreshInterval"] as? Int == 15)
        #expect(!FileManager.default.fileExists(atPath: previous.path))
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
    }

    @Test func uninstallingAnOldInstallRestoresTheStatusLine() throws {
        let legacy = dir.appendingPathComponent("legacy-only")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data(#"{"type":"command","command":"bash ~/mine.sh"}"#.utf8).write(to: legacy.appendingPathComponent("previous-statusline.json"))
        try write(#"{"statusLine":{"type":"command","command":"B=\"$HOME/.crowsnest/bin/crowsnest-bridge\"; exec \"$B\" statusline"}}"#)
        var uninstaller = installer()
        uninstaller.legacyRoot = legacy
        try uninstaller.uninstall()
        #expect((try read()["statusLine"] as? [String: Any])?["command"] as? String == "bash ~/mine.sh")
    }

    @Test func upgradingKeepsTheUsersSoundPacks() throws {
        let legacy = dir.appendingPathComponent("legacy-sounds")
        let pack = legacy.appendingPathComponent("sounds/Retro")
        try FileManager.default.createDirectory(at: pack, withIntermediateDirectories: true)
        try Data("RIFF".utf8).write(to: pack.appendingPathComponent("done.wav"))
        try FileManager.default.createDirectory(at: legacy.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try write(#"{"model":"opus"}"#)
        var upgrader = installer()
        upgrader.legacyRoot = legacy
        try upgrader.install()
        let moved = previous.deletingLastPathComponent().appendingPathComponent("sounds/Retro/done.wav")
        #expect(FileManager.default.fileExists(atPath: moved.path))
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
    }

    @Test func unknownFilesInTheOldFolderAreLeftAlone() throws {
        let legacy = dir.appendingPathComponent("legacy-other")
        try FileManager.default.createDirectory(at: legacy.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: legacy.appendingPathComponent("notes.txt"))
        try write(#"{"model":"opus"}"#)
        var upgrader = installer()
        upgrader.legacyRoot = legacy
        try upgrader.install()
        #expect(FileManager.default.fileExists(atPath: legacy.appendingPathComponent("notes.txt").path))
        #expect(!FileManager.default.fileExists(atPath: legacy.appendingPathComponent("bin").path))
    }
}
