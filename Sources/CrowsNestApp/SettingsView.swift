import SwiftUI
import AppKit
import CrowsNestCore

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var model: AppModel
    var preview: (SoundEvent) -> Void
    var exportDiagnostics: () -> Void = {}

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            sounds.tabItem { Label("Sounds", systemImage: "speaker.wave.2") }
            integrations.tabItem { Label("Integrations", systemImage: "link") }
            about.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 500, height: 630)
    }

    // MARK: General

    private var general: some View {
        Form {
            Section("Startup") {
                Toggle("Open Crow's Nest when I log in", isOn: Binding(
                    get: { settings.launchAtLogin }, set: { settings.setLaunchAtLogin($0) }))
                if let error = settings.launchAtLoginError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Section("Panel") {
                Picker("Show on", selection: $settings.displayMode) {
                    Text("Built-in display").tag("auto")
                    Text("Display with the menu bar").tag("primary")
                }
                Toggle("Open the panel when a session needs me", isOn: $settings.autoExpand)
                Toggle("Hide the panel from screen sharing and recordings", isOn: $settings.hideFromScreenSharing)
                Toggle("Show pixel characters", isOn: $settings.showCharacters)
                Toggle("Characters stroll by the notch when nothing is running", isOn: $settings.strollWhenIdle)
                    .disabled(!settings.showCharacters)
                Toggle("Show usage limits", isOn: $settings.showUsage)
                Toggle("Answer requests from the panel", isOn: $settings.answersFromPanel)
                Text("When off, Crow's Nest only watches. Approvals, questions, and plans stay in the terminal.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Session list") {
                Picker("Clear finished and unused sessions", selection: $settings.autoClearMinutes) {
                    Text("After 1 minute").tag(1)
                    Text("After 5 minutes").tag(5)
                    Text("After 15 minutes").tag(15)
                    Text("After 1 hour").tag(60)
                    Text("Only when I clear them").tag(0)
                }
                Toggle("Clear a finished session when I jump to it", isOn: $settings.clearOnJump)
                Text("A cleared session comes back if it does something new.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Shortcuts") {
                Toggle("Allow with ⌃⌥Y and deny with ⌃⌥N", isOn: $settings.shortcutsEnabled)
                Text("Active only while a request card is showing.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Sounds

    private var sounds: some View {
        Form {
            Section {
                Toggle("Play sounds", isOn: $settings.soundsEnabled)
                HStack {
                    Text("Volume")
                    Slider(value: $settings.volume, in: 0...1)
                }
                Picker("Sound pack", selection: $settings.soundPack) {
                    ForEach(settings.availablePacks, id: \.self) { Text($0).tag($0) }
                }
                HStack {
                    Text("A pack is a folder with files named approval, question, done, and error.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Folder") {
                        try? FileManager.default.createDirectory(at: Settings.soundsFolder, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(Settings.soundsFolder)
                    }
                }
            }
            Section("Events") {
                ForEach(SoundEvent.allCases, id: \.self) { event in
                    HStack {
                        Toggle(event.label, isOn: Binding(get: { settings.isOn(event) }, set: { settings.set(event, on: $0) }))
                        Spacer()
                        Button("Play") { preview(event) }
                    }
                }
            }
            Section("Quiet hours") {
                Toggle("Silence sounds during quiet hours", isOn: $settings.quietHoursEnabled)
                HStack {
                    hourPicker("From", $settings.quietStart)
                    hourPicker("to", $settings.quietEnd)
                }
                .disabled(!settings.quietHoursEnabled)
            }
        }
        .formStyle(.grouped)
    }

    private func hourPicker(_ label: String, _ value: Binding<Int>) -> some View {
        Picker(label, selection: value) {
            ForEach(0..<24, id: \.self) { h in Text(String(format: "%02d:00", h)).tag(h) }
        }
    }

    // MARK: Integrations

    @State private var integrationMessage: String?

    private var integrations: some View {
        Form {
            Section("Claude Code") {
                if let status = model.hookStatus {
                    LabeledContent("Hooks") {
                        Label(status.isFullyInstalled ? "Installed" : "\(status.installed.count) of \(Installer.events.count) installed",
                              systemImage: status.isFullyInstalled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(status.isFullyInstalled ? .green : .orange)
                    }
                    LabeledContent("Usage display") {
                        Text(status.statusLineInstalled ? "On (via the status line)" : "Off — reinstall to enable")
                            .foregroundStyle(status.statusLineInstalled ? .primary : .secondary)
                    }
                    if !status.otherPermissionHooks.isEmpty {
                        Text("Another tool is also set to answer permission requests (\(status.otherPermissionHooks.count) hook). If both apps run, both will show a prompt.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                } else {
                    Text("Could not read Claude Code's settings file.").foregroundStyle(.secondary)
                }
                HStack {
                    Button(model.hookStatus?.isFullyInstalled == true ? "Reinstall" : "Install") { runInstaller(install: true) }
                    Button("Uninstall") { runInstaller(install: false) }
                        .disabled(model.hookStatus?.installed.isEmpty ?? true)
                    Spacer()
                    Button("Refresh") { model.refreshHookStatus() }
                }
                if let integrationMessage {
                    Text(integrationMessage).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Text("Installing backs up settings.json first and leaves other hooks in place.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { model.refreshHookStatus() }
    }

    private func runInstaller(install: Bool) {
        do {
            let change = install ? try model.installIntegration() : try model.uninstallIntegration()
            integrationMessage = change.changed
                ? (install ? "Hooks installed." : "Hooks removed.") + (change.backup.map { " Backup: \($0.lastPathComponent)" } ?? "")
                : "Nothing needed changing."
        } catch {
            integrationMessage = "\(error)"
        }
    }

    // MARK: About

    private var about: some View {
        VStack(spacing: 10) {
            Image(systemName: "bird.fill").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("Crow's Nest").font(.title2.bold())
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                .foregroundStyle(.secondary)
            Text("A lookout in your notch for Claude Code sessions.").foregroundStyle(.secondary)
            HStack {
                Link("Website and source", destination: URL(string: "https://github.com/goodguyEJ/crows-nest")!)
                Text("·").foregroundStyle(.tertiary)
                Link("Check for updates", destination: URL(string: "https://github.com/goodguyEJ/crows-nest/releases")!)
            }
            .font(.callout)
            Text("\(model.sessions.count) session\(model.sessions.count == 1 ? "" : "s") · \(model.eventCount) events since launch")
                .font(.caption).foregroundStyle(.tertiary)
            Button("Export Diagnostic Report…", action: exportDiagnostics).padding(.top, 6)
            Text("Contains settings, hook status, and event names. No prompts, commands, or file paths.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
