import SwiftUI
import AppKit
import RavenIslandCore

/// Facts the setup window needs about this Mac. Read off the main thread.
struct SetupFacts {
    var claudeCodeFound: Bool
    var otherApprovalTools: Int
    var currentStatusLine: String?

    static func gather(status: Installer.Status?) -> SetupFacts {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let candidates = ["/opt/homebrew/bin/claude", "/usr/local/bin/claude",
                          home.appendingPathComponent(".local/bin/claude").path,
                          home.appendingPathComponent(".claude/local/claude").path]
        let found = candidates.contains { fm.isExecutableFile(atPath: $0) }
            || fm.fileExists(atPath: home.appendingPathComponent(".claude").path)
        return SetupFacts(claudeCodeFound: found, otherApprovalTools: status?.otherPermissionHooks.count ?? 0,
                          currentStatusLine: status?.statusLineInstalled == true ? nil : status?.statusLine)
    }
}

/// Shown on first launch when Raven Island isn't connected to Claude Code yet, and from the menu.
/// Says exactly what will change before anything does.
struct SetupView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: Settings
    var facts: SetupFacts
    var close: () -> Void

    @State private var useStatusLine = true
    @State private var watchOnly = false
    @State private var result: String?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                PixelBot(state: .done, persona: PixelSprites.personas[0], size: 44, animated: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect Raven Island to Claude Code").font(.title3.bold())
                    Text("Nothing changes until you click Connect.").foregroundStyle(.secondary)
                }
            }

            if !facts.claudeCodeFound {
                Label("Claude Code doesn't seem to be installed. Raven Island works with Claude Code only.",
                      systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("What this changes").font(.headline)
                bullet("Adds 14 hooks to ~/.claude/settings.json. A backup is saved next to it first, and your other settings and hooks are left alone.")
                bullet("Copies a small helper to ~/.ravenisland. Claude Code runs it on each event; it takes about 5 ms and does nothing when this app is closed.")
                bullet("Nothing leaves your Mac: no network connections, and nothing a session says is saved.")
                bullet("Undo any time: Settings → Integrations → Uninstall.")
            }

            Divider()

            Toggle(isOn: $useStatusLine) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show my usage limits")
                    Text(facts.currentStatusLine == nil
                         ? "Reads them from Claude Code's status line. Pro and Max plans only."
                         : "Reads them from Claude Code's status line, then runs your current status line so it looks the same. Pro and Max plans only.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }

            Picker("Approvals", selection: $watchOnly) {
                Text("Answer them from the notch").tag(false)
                Text("Watch only: approvals stay in the terminal").tag(true)
            }
            .pickerStyle(.radioGroup)

            if facts.otherApprovalTools > 0 {
                Label("Another tool is also set up to answer Claude Code's permission prompts. If both run, both will ask. Watch only avoids that.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }

            if let result {
                Text(result).font(.callout).foregroundStyle(failed ? .red : .green).fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button(result == nil || failed ? "Not now" : "Close") { close() }
                Spacer()
                if result == nil || failed {
                    Button("Connect") { connect() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(22)
        .frame(width: 480)
        .onAppear { watchOnly = facts.otherApprovalTools > 0 }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("•")
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
    }

    private func connect() {
        do {
            let change = try model.installIntegration(statusLine: useStatusLine)
            settings.answersFromPanel = !watchOnly
            failed = false
            result = "Connected. Sessions appear in the notch as soon as they do something."
                + (change.backup.map { " Settings backup: \($0.lastPathComponent)" } ?? "")
        } catch {
            failed = true
            result = "Couldn't connect: \(error)"
        }
    }
}
