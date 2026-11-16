import AppKit
import SwiftUI
import Combine
import RavenIslandCore
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    let settings = Settings()
    lazy var sounds = SoundPlayer(settings: settings)
    lazy var music = MusicSource(settings: settings)
    lazy var calendar = CalendarSource(settings: settings)
    var settingsWindow: NSWindow?
    var setupWindow: NSWindow?
    var server: SocketServer?
    var statusItem: NSStatusItem?
    var debugWindow: NSWindow?
    var notch: NotchController?
    let hotKeys = HotKeys()
    var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let server = SocketServer(path: AppPaths.socket.path) { [weak self] envelope, connection in
            MainActor.assumeIsolated { self?.model.handle(envelope, connection: connection) }
        }
        do {
            try server.start()
        } catch SocketServer.StartError.alreadyRunning {
            NSApp.terminate(nil)   // another instance owns the socket
            return
        } catch {
            let alert = NSAlert()
            alert.messageText = "Raven Island could not open its socket"
            alert.informativeText = "\(error)"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        self.server = server
        model.start()
        if !CommandLine.arguments.contains("--test-mode") {
            music.start()
            calendar.start()
        }
        setUpStatusItem()
        notch = NotchController(model: model, settings: settings, music: music, calendar: calendar)
        notch?.onOpenSettings = { [weak self] below in self?.showSettings(below: below) }
        model.jump = { session in Jumper.jump(to: session) }
        model.diagnostics = { [weak self] in
            guard let self else { return "" }
            return Diagnostics.report(model: self.model, settings: self.settings, music: self.music, calendar: self.calendar)
        }
        notch?.onSelect = { [weak self] session in
            self?.model.open(session)
        }
        settings.$autoClearMinutes.sink { [weak self] minutes in
            self?.model.autoClearAfter = minutes > 0 ? TimeInterval(minutes * 60) : nil
        }.store(in: &subscriptions)
        settings.$clearOnJump.sink { [weak self] in self?.model.clearOnJump = $0 }.store(in: &subscriptions)

        // ⌃⌥Y / ⌃⌥N answer the card on screen. They exist only while a permission or plan card is showing.
        hotKeys.onAllow = { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let r = self.model.shortcutTarget(allowing: true) else { NSSound.beep(); return }
                self.model.resolve(r.id, .allow)
            }
        }
        hotKeys.onDeny = { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let r = self.model.shortcutTarget(allowing: false) else { NSSound.beep(); return }
                self.model.resolve(r.id, .deny(message: nil))
            }
        }
        model.$pending.combineLatest(settings.$shortcutsEnabled).receive(on: RunLoop.main).sink { [weak self] pending, enabled in
            self?.hotKeys.setEnabled(enabled && (pending.first.map { $0.kind != .question } ?? false))
        }.store(in: &subscriptions)

        settings.$answersFromPanel.sink { [weak self] in self?.model.answersFromPanel = $0 }.store(in: &subscriptions)
        model.onTransition = { [weak self] session, old in
            if let event = SoundEvent.forTransition(from: old, to: session.state) { self?.sounds.play(event) }
        }
        #if DEBUG
        if CommandLine.arguments.contains("--debug-window") { showDebugWindow() }
        #endif
        if CommandLine.arguments.contains("--settings") { showSettings() }
        // First launch, or the hooks were removed: offer to connect, once, unless the user said not now.
        if !CommandLine.arguments.contains("--test-mode"), !model.isConnected, !settings.setupDeferred {
            showSetup()
        }
        // Used by the end-to-end tests so a second instance stays quiet and leaves the shortcuts alone.
        if CommandLine.arguments.contains("--test-mode") {
            settings.soundsEnabled = false
            settings.shortcutsEnabled = false
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = MenuBarIcon.image()
        let menu = NSMenu()
        let summary = NSMenuItem(title: "No sessions", action: nil, keyEquivalent: "")
        summary.isEnabled = false
        menu.addItem(summary)
        let setup = NSMenuItem(title: "Not connected to Claude Code — Set Up…", action: #selector(showSetup), keyEquivalent: "")
        setup.target = self
        menu.addItem(setup)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings as () -> Void), keyEquivalent: ",").target = self
        #if DEBUG
        // The debug window shows prompts and paths; it is not part of release builds.
        menu.addItem(withTitle: "Show Debug Window", action: #selector(showDebugWindow), keyEquivalent: "d").target = self
        #endif
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Raven Island", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item

        model.$hookStatus.receive(on: RunLoop.main).sink { [weak self, weak setup] _ in
            setup?.isHidden = self?.model.isConnected ?? true
        }.store(in: &subscriptions)

        model.$sessions.receive(on: RunLoop.main).sink { [weak summary] sessions in
            let attention = sessions.filter { $0.state.needsAttention }.count
            item.button?.title = attention > 0 ? " \(attention)" : ""
            summary?.title = sessions.isEmpty ? "No sessions"
                : "\(sessions.count) session\(sessions.count == 1 ? "" : "s")" + (attention > 0 ? ", \(attention) need you" : "")
        }.store(in: &subscriptions)
    }

    @objc func showSetup() {
        model.refreshHookStatus()
        let facts = SetupFacts.gather(status: model.hookStatus)
        let window = setupWindow ?? NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Set Up Raven Island"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SetupView(model: model, settings: settings, facts: facts) { [weak self, weak window] in
            guard let self else { return }
            if !self.model.isConnected { self.settings.setupDeferred = true }
            window?.close()
        })
        window.center()
        setupWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showSettings() { showSettings(below: nil) }

    func showSettings(below panelFrame: CGRect?) {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 630),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Raven Island Settings"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsView(settings: settings, model: model, calendar: calendar, preview: { [weak self] event in
                self?.sounds.play(event, force: true)
            }, exportDiagnostics: { [weak self] in
                guard let self else { return }
                Diagnostics.export(model: self.model, settings: self.settings, music: self.music, calendar: self.calendar)
            }))
            window.center()
            settingsWindow = window
        }
        settings.refreshLaunchAtLogin()
        if let panelFrame, let window = settingsWindow,
           let visible = (NSScreen.screens.first { $0.frame.intersects(panelFrame) } ?? NSScreen.main)?.visibleFrame {
            let size = window.frame.size
            let x = min(max(panelFrame.midX - size.width / 2, visible.minX), visible.maxX - size.width)
            let y = max(min(panelFrame.minY - 12 - size.height, visible.maxY - size.height), visible.minY)
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showDebugWindow() {
        if debugWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = "Raven Island — Sessions"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: DebugView(model: model))
            window.center()
            debugWindow = window
        }
        model.refreshHookStatus()
        debugWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

MainActor.assumeIsolated {
    if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
        Snapshot.write(to: CommandLine.arguments[i + 1])
        exit(0)
    }
    // Used by scripts/uninstall.sh: remove the "open at login" registration, then exit.
    if CommandLine.arguments.contains("--unregister-login-item") {
        try? SMAppService.mainApp.unregister()
        exit(0)
    }
    if let i = CommandLine.arguments.firstIndex(of: "--render-icon"), i + 1 < CommandLine.arguments.count {
        AppIconRenderer.write(to: CommandLine.arguments[i + 1])
        exit(0)
    }
    // Writes the built-in sounds as WAV files: a starting point for a custom pack.
    if let i = CommandLine.arguments.firstIndex(of: "--export-sounds"), i + 1 < CommandLine.arguments.count {
        let dir = URL(fileURLWithPath: CommandLine.arguments[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for event in SoundEvent.allCases {
            try? ToneSynth.wav(ToneSynth.render(event)).write(to: dir.appendingPathComponent(event.rawValue + ".wav"))
        }
        print("Wrote \(SoundEvent.allCases.count) sounds to \(dir.path)")
        exit(0)
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
