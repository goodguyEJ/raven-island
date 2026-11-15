import AppKit
import SwiftUI
import RavenIslandCore

/// A plain-text snapshot of Raven Island's state for troubleshooting. Deliberately leaves out anything a
/// session said or ran: no prompts, commands, file paths, or project names.
@MainActor
enum Diagnostics {
    static func report(model: AppModel, settings: Settings) -> String {
        var lines: [String] = []
        let info = Bundle.main.infoDictionary ?? [:]
        lines.append("Raven Island diagnostic report")
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
            lines.append("  status line: \(status.statusLineInstalled ? "Raven Island" : (status.statusLine == nil ? "not set" : "another command"))")
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
        panel.nameFieldStringValue = "ravenisland-diagnostics.txt"
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? report(model: model, settings: settings).write(to: url, atomically: true, encoding: .utf8)
    }
}

/// `Raven Island --render-icon DIR` writes the app icon as an .iconset folder for `iconutil`.
@MainActor
enum AppIconRenderer {
    /// The logo: a raven standing on a small pixel island, under the moon, on a night sky.
    /// A 24×24 pixel scene; each character is one pixel (see `colors`).
    static let scene: [String] = [
        "........................",
        "...W...............MM...",
        "..................MMMM..",
        ".................MMM....",
        ".................MMM....",
        "..................MMMM..",
        "...................MM...",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "......GGGG..............",
        "....LLLLLLLLLLLL........",
        "...LLLLLLLLLLLLLLL......",
        "~~DDDDDDDDDDDDDDDDDD~~~~",
        "~~~~~~~~~~~~~~~~~~~~~~~~",
        "w~~~~~w~~~~~~~~w~~~~~~~w",
        "~~~~~~~~~~~~~~~~~~~~~~~~",
    ]

    static let colors: [Character: Color] = [
        "W": .white, "M": Color(red: 0.96, green: 0.90, blue: 0.72),
        "G": Color(red: 0.32, green: 0.75, blue: 0.42), "L": Color(red: 0.91, green: 0.78, blue: 0.48),
        "D": Color(red: 0.76, green: 0.60, blue: 0.33), "~": Color(red: 0.18, green: 0.42, blue: 0.70),
        "w": Color(red: 0.55, green: 0.78, blue: 0.95),
    ]

    static func logo(side: CGFloat) -> some View {
        let tile = side * 0.82
        let px = tile / 24
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: tile * 0.225, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.10, green: 0.12, blue: 0.30), Color(red: 0.25, green: 0.16, blue: 0.40)],
                                     startPoint: .top, endPoint: .bottom))
            Canvas { context, _ in
                for (r, row) in scene.enumerated() {
                    for (c, pixel) in row.enumerated() {
                        guard let fill = colors[pixel] else { continue }
                        context.fill(Path(CGRect(x: CGFloat(c) * px, y: CGFloat(r) * px, width: px + 0.5, height: px + 0.5)), with: .color(fill))
                    }
                }
                // The raven stands on the sand, its feet on row 18.
                let raven = PixelSprites.walkFrames(persona: PixelSprites.personas[0])[0]
                var sub = context
                sub.translateBy(x: 4 * px, y: 3 * px)
                PixelBot.draw(raven, persona: PixelSprites.personas[0], in: &sub, size: CGSize(width: px * CGFloat(PixelSprites.width), height: px * 16))
            }
        }
        .frame(width: tile, height: tile)
        .clipShape(RoundedRectangle(cornerRadius: tile * 0.225, style: .continuous))
        .frame(width: side, height: side)
    }

    static func write(to dir: String) {
        let out = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let sizes: [(String, CGFloat)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024),
        ]
        for (name, side) in sizes {
            let renderer = ImageRenderer(content: logo(side: side))
            renderer.scale = 1
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: out.appendingPathComponent(name + ".png"))
        }
        print("Wrote icon set to \(out.path)")
    }
}
