import Foundation
import Testing
@testable import CrowsNestCore

@Suite struct InstallerTests {
    let dir: URL
    let settings: URL
    var previous: URL { dir.appendingPathComponent("previous-statusline.json") }
    func installer() -> Installer { Installer(settingsURL: settings, previousStatusLineURL: previous) }

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("crowsnest-inst-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        settings = dir.appendingPathComponent("settings.json")
    }

    func write(_ json: String) throws { try Data(json.utf8).write(to: settings) }
    func read() throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any])
    }
    func backups() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains("crowsnest-backup") }
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
        // The status line slot is ours now, and the previous command is remembered for chaining.
        #expect(status.statusLineInstalled)
        let remembered = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: previous)) as? [String: Any])
        #expect(remembered["command"] as? String == "/usr/local/bin/other-statusline")

        // Our permission hook carries the long timeout.
        let ours = try #require((hooks["PermissionRequest"] as? [[String: Any]])?.last?["hooks"] as? [[String: Any]])
        #expect(ours.first?["timeout"] as? Int == 86_400)
        #expect((ours.first?["command"] as? String)?.contains(Installer.marker) == true)
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

    @Test func statusLineCanBeLeftAlone() throws {
        try write(Self.existing)
        try installer().install(statusLine: false)
        let status = try installer().status()
        #expect(status.isFullyInstalled)
        #expect(!status.statusLineInstalled)
        #expect(status.statusLine == "/usr/local/bin/other-statusline")
        #expect(!FileManager.default.fileExists(atPath: previous.path))
    }

    @Test func statusLineWithNothingBefore() throws {
        try write(#"{"model":"opus"}"#)
        try installer().install()
        #expect(try installer().status().statusLineInstalled)
        #expect(!FileManager.default.fileExists(atPath: previous.path))
        try installer().uninstall()
        #expect(try read()["statusLine"] == nil)
        #expect(try read()["model"] as? String == "opus")
    }

    @Test func reinstallKeepsTheRememberedStatusLine() throws {
        try write(Self.existing)
        try installer().install()
        try installer().uninstall()
        try installer().install()
        try installer().install()
        let remembered = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: previous)) as? [String: Any])
        #expect(remembered["command"] as? String == "/usr/local/bin/other-statusline")   // never overwritten with our own
    }

    @Test func invalidJSONIsLeftUntouched() throws {
        let broken = "{ this is not json"
        try write(broken)
        let installer = installer()
        #expect(throws: Installer.InstallError.self) { try installer.install() }
        #expect(try String(contentsOf: settings, encoding: .utf8) == broken)
        #expect(try backups().isEmpty)
    }

    @Test func staleOwnEntriesAreReplacedNotDuplicated() throws {
        try write(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/old/path/.crowsnest/bin/crowsnest-bridge hook"}]}]}}"#)
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
        try write(#"{"hooks":{"Stop":[{"matcher":"x","hooks":[{"type":"command","command":"~/.crowsnest/bin/crowsnest-bridge hook claude"},{"type":"command","command":"say done"}]}]}}"#)
        try installer().install(statusLine: false)
        try installer().uninstall()
        let stop = try #require((try read()["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])
        #expect(stop.count == 1)
        #expect(stop[0]["matcher"] as? String == "x")
        #expect((stop[0]["hooks"] as? [[String: Any]])?.map { $0["command"] as? String } == ["say done"])
    }

    @Test func oldBackupsArePruned() throws {
        try write(Self.existing)
        for i in 0..<8 {
            try installer().install(statusLine: false, now: Date(timeIntervalSince1970: 1_800_000_000 + Double(i) * 60))
            try installer().uninstall(now: Date(timeIntervalSince1970: 1_800_000_030 + Double(i) * 60))
        }
        #expect(try backups().count == Installer.backupsKept)
    }

    @Test func helperIsCopiedAndRequired() throws {
        let dest = dir.appendingPathComponent("bin/crowsnest-bridge")
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

    @Test func statusLineDisplayOptionsAreKept() throws {
        try write(#"{"statusLine":{"type":"command","command":"bash ~/line.sh","refreshInterval":15,"padding":2}}"#)
        try installer().install()
        let line = try #require(try read()["statusLine"] as? [String: Any])
        #expect((line["command"] as? String)?.contains(Installer.marker) == true)
        #expect(line["refreshInterval"] as? Int == 15)
        #expect(line["padding"] as? Int == 2)
    }

    @Test func olderStatusLineEntryIsUpgraded() throws {
        try write(#"{"statusLine":{"type":"command","command":"\"$HOME/.crowsnest/bin/crowsnest-bridge\" statusline 2>/dev/null || true"}}"#)
        try Data(#"{"type":"command","command":"bash ~/line.sh","refreshInterval":15}"#.utf8).write(to: previous)
        let change = try installer().install()
        #expect(change.changed)
        let line = try #require(try read()["statusLine"] as? [String: Any])
        #expect(line["command"] as? String == Installer.statusLineCommand)
        #expect(line["refreshInterval"] as? Int == 15)
        #expect(try !installer().install().changed)   // idempotent after the upgrade
    }
}
