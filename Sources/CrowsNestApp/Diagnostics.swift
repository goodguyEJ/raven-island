import AppKit
import SwiftUI
import CrowsNestCore

/// A plain-text snapshot of Crow's Nest's state for troubleshooting. Deliberately leaves out anything a
/// session said or ran: no prompts, commands, file paths, or project names.
@MainActor
enum Diagnostics {
    static func report(model: AppModel, settings: Settings) -> String {
        var lines: [String] = []
        let info = Bundle.main.infoDictionary ?? [:]
        lines.append("Crow's Nest diagnostic report")
        lines.append("Generated: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("Version: \(info["CFBundleShortVersionString"] as? String ?? "dev") (\(info["CFBundleVersion"] as? String ?? "-"))")
        lines.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("")
        lines.append("Displays:")
        for s in NSScreen.screens {
            lines.append("  \(Int(s.frame.width))x\(Int(s.frame.height)) notch=\(s.safeAreaInsets.top > 0) scale=\(s.backingScaleFactor)")
        }
        lines.append("")
        lines.append("Integration:")
        if let status = try? Installer().status() {
            lines.append("  hooks installed: \(status.installed.count)/\(Installer.events.count)" +
                         (status.missing.isEmpty ? "" : " (missing: \(status.missing.joined(separator: ", ")))"))
            lines.append("  status line: \(status.statusLineInstalled ? "Crow's Nest" : (status.statusLine == nil ? "not set" : "another command"))")
            lines.append("  other tools answering permission requests: \(status.otherPermissionHooks.count)")
        } else {
            lines.append("  could not read Claude Code settings")
        }
        lines.append("  bridge binary present: \(FileManager.default.isExecutableFile(atPath: AppPaths.installedBridge.path))")
        lines.append("")
        lines.append("Settings:")
        lines.append("  autoExpand=\(settings.autoExpand) answersFromPanel=\(settings.answersFromPanel) shortcuts=\(settings.shortcutsEnabled)")
        lines.append("  characters=\(settings.showCharacters) usage=\(settings.showUsage) display=\(settings.displayMode)")
        lines.append("  sounds=\(settings.soundsEnabled) volume=\(String(format: "%.2f", settings.volume)) pack=\(settings.soundPack == Settings.builtInPack ? "built-in" : "custom") quietHours=\(settings.quietHoursEnabled)")
        lines.append("  autoClearMinutes=\(settings.autoClearMinutes) clearOnJump=\(settings.clearOnJump)")
        lines.append("  launchAtLogin=\(settings.launchAtLogin)")
        lines.append("")
        lines.append("Sessions (\(model.sessions.count)), requests waiting: \(model.pending.count), events since launch: \(model.eventCount)")
        for s in model.sessions {
            let idle = Int(Date().timeIntervalSince(s.lastEventAt))
            lines.append("  \(s.id.prefix(8)) state=\(s.state.rawValue) agent=\(s.agent) term=\(s.context.termProgram ?? "-") tty=\(s.context.tty != nil) tmux=\(s.context.tmuxPane != nil) subagents=\(s.subagents) lastEvent=\(idle)s ago")
        }
        lines.append("")
        lines.append("Usage data: \(model.usage == nil ? "none" : "present")")
        lines.append("")
        lines.append("Recent events (newest last, names only):")
        let format = DateFormatter()
        format.dateFormat = "HH:mm:ss"
        for e in model.log.suffix(80) {
            // Tool names are kept; anything after "→" is a card title and may name a file, so it is dropped.
            let detail = e.event.hasPrefix("→") ? "" : " " + e.detail
            lines.append("  \(format.string(from: e.time)) \(e.session) \(e.event)\(detail)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func export(model: AppModel, settings: Settings) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "crowsnest-diagnostics.txt"
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? report(model: model, settings: settings).write(to: url, atomically: true, encoding: .utf8)
    }
}

/// `Crow's Nest --render-icon DIR` writes the app icon as an .iconset folder for `iconutil`.
@MainActor
enum AppIconRenderer {
    static func write(to dir: String) {
        let out = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let sizes: [(String, CGFloat)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024),
        ]
        for (name, side) in sizes {
            let inset = side * 0.09
            let tile = side - 2 * inset
            let view = ZStack {
                RoundedRectangle(cornerRadius: tile * 0.225, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.13, green: 0.14, blue: 0.20), Color(red: 0.04, green: 0.04, blue: 0.07)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: tile, height: tile)
                PixelBot(state: .done, persona: PixelSprites.personas[0], size: tile * 0.62, animated: false)
            }
            .frame(width: side, height: side)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: out.appendingPathComponent(name + ".png"))
        }
        print("Wrote icon set to \(out.path)")
    }
}
