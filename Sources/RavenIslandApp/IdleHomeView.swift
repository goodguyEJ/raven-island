import SwiftUI
import RavenIslandCore

struct IdleArtwork: View {
    var artwork: NSImage?
    var size: CGFloat

    var body: some View {
        Group {
            if let artwork {
                Image(nsImage: artwork).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.white.opacity(0.12))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Three small bars beside the artwork. Decorative: they move while playing, not with the audio.
struct PlayingBars: View {
    var moving: Bool
    var height: CGFloat
    private static let rest: [CGFloat] = [0.4, 0.75, 0.55]

    var body: some View {
        if moving {
            TimelineView(.periodic(from: .now, by: 0.28)) { timeline in
                let tick = Int(timeline.date.timeIntervalSinceReferenceDate / 0.28)
                bars { i in 0.3 + 0.7 * CGFloat((tick * (i + 3) + i * 5) % 7) / 6 }
                    .animation(.easeInOut(duration: 0.28), value: tick)
            }
        } else {
            bars { Self.rest[$0] }
        }
    }

    private func bars(_ level: @escaping (Int) -> CGFloat) -> some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(0..<3, id: \.self) { i in
                Capsule().fill(.white.opacity(0.8)).frame(width: 2, height: height * level(i))
            }
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

struct IdleMusicWing: View {
    var artwork: NSImage?
    var playing: Bool
    var size: CGFloat
    var animated: Bool

    var body: some View {
        HStack(spacing: 3) {
            IdleArtwork(artwork: artwork, size: size)
            PlayingBars(moving: playing && animated, height: size * 0.6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(playing ? "Music playing" : "Music paused")
    }
}

struct IdleAgendaWing: View {
    var label: String

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white.opacity(0.85))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityLabel(label == "now" ? "Event in progress" : "Next event at \(label)")
    }
}

struct IdleHomePanel: View {
    var idleHome: IdleHome
    var nowPlaying: NowPlaying?
    var artwork: NSImage?
    var controlsAllowed: Bool
    var agenda: [AgendaEvent]
    var width: CGFloat
    var animated: Bool
    var onMusic: (MusicCommand) -> Void
    var onOpenPlayer: () -> Void
    var onOpenCalendar: () -> Void

    private var track: NowPlaying? { idleHome.hasTrack ? nowPlaying : nil }

    var body: some View {
        HStack(spacing: 0) {
            if let track {
                musicHalf(track).frame(maxWidth: .infinity, alignment: .leading)
            }
            if track != nil, idleHome.showsAgendaHalf {
                Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: NotchGeometry.idleHomeHeight - 28)
                    .padding(.horizontal, 14)
            }
            if idleHome.showsAgendaHalf {
                agendaHalf.frame(width: track == nil ? nil : width * 0.4, alignment: .leading)
                    .frame(maxWidth: track == nil ? .infinity : nil, alignment: .leading)
            }
        }
        .frame(width: width, height: NotchGeometry.idleHomeHeight)
    }

    private func musicHalf(_ track: NowPlaying) -> some View {
        HStack(spacing: 12) {
            IdleArtwork(artwork: artwork, size: 56)
                .onTapGesture(perform: onOpenPlayer)
            VStack(alignment: .leading, spacing: 2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(TextSafety.visible(track.title))
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    if !track.artist.isEmpty {
                        Text(TextSafety.visible(track.artist))
                            .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.58))
                    }
                }
                .lineLimit(1).truncationMode(.tail)
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpenPlayer)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Opens \(track.app.displayName)")
                progress(track)
                    .padding(.top, 5)
                HStack(spacing: 22) {
                    control("backward.fill", "Previous track", .previous, size: 22)
                    control(track.isPlaying ? "pause.fill" : "play.fill", track.isPlaying ? "Pause" : "Play", .playPause, size: 30)
                    control("forward.fill", "Next track", .next, size: 22)
                }
                .frame(maxWidth: 220)
            }
        }
    }

    private func control(_ symbol: String, _ label: String, _ command: MusicCommand, size: CGFloat) -> some View {
        MusicControlButton(symbol: symbol, label: label, allowed: controlsAllowed, size: size) { onMusic(command) }
    }

    @ViewBuilder private func progress(_ track: NowPlaying) -> some View {
        if let duration = track.duration {
            if animated {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in progressRow(track.position(at: timeline.date), duration) }
            } else {
                progressRow(track.position(at: Date()), duration)
            }
        }
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func progressRow(_ position: TimeInterval, _ duration: TimeInterval) -> some View {
        let fraction = duration > 0 ? position / duration : 0
        return HStack(spacing: 7) {
            Text(Self.clock(position))
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    Capsule().fill(.white.opacity(0.75)).frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 3)
            .accessibilityElement()
            .accessibilityLabel("Progress")
            .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
            Text("-" + Self.clock(max(0, duration - position)))
        }
        .font(.system(size: 10.5).monospacedDigit())
        .foregroundStyle(.white.opacity(0.55))
        .frame(maxWidth: 220)
    }

    private var agendaHalf: some View {
        AgendaTimelineView(events: agenda, onOpenCalendar: onOpenCalendar)
            .padding(.vertical, 8)
    }
}

struct AgendaTimelineView: View {
    var events: [AgendaEvent]
    var onOpenCalendar: () -> Void

    private static let nowColor = Color(red: 1, green: 0.27, blue: 0.23)
    private static let labelWidth: CGFloat = 34

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 3) {
                Text("Today").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white.opacity(0.45))
                if events.isEmpty {
                    Text("Nothing else today").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                    Spacer(minLength: 0)
                } else {
                    content(now: context.date)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenCalendar)
    }

    @ViewBuilder private func content(now: Date) -> some View {
        GeometryReader { proxy in
            let timeline = AgendaTimeline(events: events, now: now, calendar: .current,
                                          minimumHeight: 12 / max(proxy.size.height, 12))
            grid(timeline, size: proxy.size)
        }
        let timeline = AgendaTimeline(events: events, now: now, calendar: .current, minimumHeight: 0)
        if let later = timeline.later {
            Text("Later: \(Agenda.timeLabel(later.start, calendar: .current, locale: .current)) \(TextSafety.visible(later.title))")
                .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.6))
                .lineLimit(1).truncationMode(.tail)
        }
    }

    private func grid(_ timeline: AgendaTimeline, size: CGSize) -> some View {
        let y = { (date: Date) in CGFloat(date.timeIntervalSince(timeline.start) / AgendaTimeline.span) * size.height }
        let lane = size.width - Self.labelWidth
        return ZStack(alignment: .topLeading) {
            ForEach(timeline.hourMarks, id: \.self) { mark in
                HStack(spacing: 4) {
                    Text(mark.formatted(Date.FormatStyle(locale: .current, calendar: .current, timeZone: .current).hour()))
                        .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1).fixedSize()
                        .frame(width: Self.labelWidth - 4, alignment: .leading)
                    Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
                }
                .frame(height: 10)
                .offset(y: y(mark) - 5)
            }
            ForEach(timeline.blocks, id: \.event.id) { block in
                let columnWidth = lane / CGFloat(block.columns)
                EventBlock(event: block.event)
                    .frame(width: columnWidth - 2, height: CGFloat(block.height) * size.height - 1)
                    .offset(x: Self.labelWidth + CGFloat(block.column) * columnWidth, y: CGFloat(block.top) * size.height)
            }
            HStack(spacing: 0) {
                Circle().fill(Self.nowColor).frame(width: 5, height: 5)
                Rectangle().fill(Self.nowColor).frame(height: 1)
            }
            .frame(width: lane + 3)
            .offset(x: Self.labelWidth - 3, y: CGFloat(timeline.nowOffset) * size.height - 2.5)
            .accessibilityHidden(true)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
    }
}

private struct EventBlock: View {
    var event: AgendaEvent

    private var color: Color {
        guard let rgb = event.color else { return SessionState.working.color }
        return Color(red: Double(rgb >> 16 & 0xFF) / 255, green: Double(rgb >> 8 & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }

    var body: some View {
        HStack(spacing: 3) {
            Rectangle().fill(color).frame(width: 2)
            Text(TextSafety.visible(event.title))
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.92))
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(color.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Agenda.timeLabel(event.start, calendar: .current, locale: .current)) \(TextSafety.visible(event.title))")
    }
}

struct MusicControlButton: View {
    var symbol: String
    var label: String
    var allowed: Bool
    var size: CGFloat = 12
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: max(36, size + 16), height: max(36, size + 6))
                .foregroundStyle(.white.opacity(allowed ? (hovered ? 1 : 0.8) : 0.3))
                .background(Circle().fill(.white.opacity(hovered ? 0.16 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(allowed ? label : "Allow Raven Island to control this app in System Settings → Privacy & Security → Automation")
        .accessibilityLabel(label)
    }
}

struct HeaderMiniPlayer: View {
    var nowPlaying: NowPlaying
    /// No room for the name, when "Clear N done" shares the header.
    var compact: Bool
    var allowed: Bool
    var animated: Bool
    var onPlayPause: () -> Void
    var onOpenPlayer: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "music.note").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                .accessibilityHidden(true)
            if !compact {
                Marquee(text: TextSafety.visible(nowPlaying.title), animated: animated)
                    .frame(minWidth: 40, maxWidth: .infinity)
                    .layoutPriority(-1)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onOpenPlayer)
                    .accessibilityLabel("Now playing: \(TextSafety.visible(nowPlaying.title))")
                    .accessibilityAddTraits(.isButton)
            }
            HeaderIconButton(symbol: nowPlaying.isPlaying ? "pause.fill" : "play.fill",
                             label: nowPlaying.isPlaying ? "Pause" : "Play", action: onPlayPause)
                .opacity(allowed ? 1 : 0.4)
        }
    }
}

struct Marquee: View {
    var text: String
    var animated: Bool

    private static let font = NSFont.systemFont(ofSize: 11, weight: .medium)
    private static let speed: CGFloat = 25
    private static let pause: Double = 1.5
    private static let gap: CGFloat = 28

    private var label: some View {
        Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
    }

    var body: some View {
        let textWidth = ceil(NSAttributedString(string: text, attributes: [.font: Self.font]).size().width)
        GeometryReader { proxy in
            if animated, textWidth > proxy.size.width {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    let travel = textWidth + Self.gap
                    let cycle = Double(travel / Self.speed) + Self.pause
                    let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
                    HStack(spacing: Self.gap) { label; label }
                        .fixedSize()
                        .offset(x: t < Self.pause ? 0 : -CGFloat(t - Self.pause) * Self.speed)
                }
            } else {
                label.truncationMode(.tail).frame(width: proxy.size.width, alignment: .leading)
            }
        }
        .frame(height: 14)
        .clipped()
    }
}
