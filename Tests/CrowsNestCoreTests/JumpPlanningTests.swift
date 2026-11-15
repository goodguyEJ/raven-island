import Foundation
import Testing
@testable import CrowsNestCore

@Suite struct JumpPlanningTests {
    @Test func onlyRealTTYPathsReachAScript() {
        #expect(JumpPlanning.isSafeTTY("/dev/ttys004"))
        #expect(!JumpPlanning.isSafeTTY("/dev/ttys004\" \n do shell script \"rm -rf ~"))
        #expect(!JumpPlanning.isSafeTTY("ttys004"))
        #expect(!JumpPlanning.isSafeTTY("/dev/ttys004\n"))        // a trailing newline must not slip through
        #expect(!JumpPlanning.isSafeTmuxPane("%3\n"))
        #expect(JumpPlanning.tmuxExecutable(exists: { $0 == "/usr/local/bin/tmux" }) == "/usr/local/bin/tmux")
        #expect(JumpPlanning.tmuxExecutable(exists: { _ in false }) == nil)
        #expect(JumpPlanning.ghosttyScript(tty: "/dev/ttys012")?.contains(#"whose tty is "/dev/ttys012""#) == true)
        #expect(JumpPlanning.ghosttyScript(tty: "\"; quit; \"") == nil)
        #expect(JumpPlanning.appleTerminalScript(tty: "/dev/ttys001") != nil)
        #expect(JumpPlanning.isSafeTmuxPane("%12"))
        #expect(!JumpPlanning.isSafeTmuxPane("%1; kill-server"))
    }

    @Test func tmuxSocketFromEnvironment() {
        #expect(JumpPlanning.tmuxSocket(fromEnv: "/private/tmp/tmux-501/default,1234,0") == "/private/tmp/tmux-501/default")
        #expect(JumpPlanning.tmuxSocket(fromEnv: "") == nil)
        #expect(JumpPlanning.tmuxSocket(fromEnv: "relative,1,0") == nil)
    }

    @Test func vscodeOpenFolders() {
        let storage = #"""
        {"windowsState":{"lastActiveWindow":{"folder":"file:///Users/dev/code/api-server","backupPath":"x","uiState":{}},
          "openedWindows":[{"folder":"file:///Users/dev/code/web%20app"},{"backupPath":"empty-window"},
                           {"folder":"vscode-remote://ssh-remote+box/home/dev"},{"folder":"file:///Users/dev/code/api-server"}]}}
        """#
        let folders = JumpPlanning.openFolders(inStorage: Data(storage.utf8))
        #expect(folders == ["/Users/dev/code/web app", "/Users/dev/code/api-server"])   // remote and empty windows skipped, no duplicates
        #expect(JumpPlanning.openFolders(inStorage: Data("{}".utf8)).isEmpty)
        #expect(JumpPlanning.openFolders(inStorage: Data("garbage".utf8)).isEmpty)
    }

    @Test func workspaceMatching() {
        let folders = ["/Users/dev/code", "/Users/dev/code/api-server", "/Users/dev/code/api"]
        #expect(JumpPlanning.workspaceFolder(for: "/Users/dev/code/api-server/src/routes", among: folders) == "/Users/dev/code/api-server")
        #expect(JumpPlanning.workspaceFolder(for: "/Users/dev/code/api-server", among: folders) == "/Users/dev/code/api-server")
        // "api" must not match "api-server" just because the text starts the same.
        #expect(JumpPlanning.workspaceFolder(for: "/Users/dev/code/api-server2", among: ["/Users/dev/code/api-server"]) == nil)
        #expect(JumpPlanning.workspaceFolder(for: "/somewhere/else", among: folders) == nil)
    }
}
