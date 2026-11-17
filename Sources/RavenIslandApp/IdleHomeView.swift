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
    var tint: Color?
    var badge: NSImage?
    var controlsAllowed: Bool
    var agenda: [AgendaEvent]
    var width: CGFloat
    var animated: Bool
    var onMusic: (MusicCommand) -> Void
    var onOpenPlayer: () -> Void
    var onOpenCalendar: () -> Void
    var calendarPrompt: CalendarPrompt? = nil
    var onCalendarPrompt: () -> Void = {}

    private var track: NowPlaying? { idleHome.hasTrack ? nowPlaying : nil }
    /// Without artwork, or with artwork that has no real colour, the player's colour carries through.
    private var accent: Color { tint ?? track.map { SpinningRecord.color(for: $0.app) } ?? .white }
    /// Without the calendar the music half would sit beside an empty space.
    private var prompt: CalendarPrompt? { track != nil && !idleHome.showsAgendaHalf ? calendarPrompt : nil }

    var body: some View {
        HStack(spacing: 0) {
            if let track {
                musicHalf(track).frame(maxWidth: .infinity, alignment: .leading)
            }
            if track != nil, idleHome.showsAgendaHalf || prompt != nil {
                Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: NotchGeometry.idleHomeHeight - 28)
                    .padding(.horizontal, 14)
            }
            if idleHome.showsAgendaHalf {
                agendaHalf.frame(width: track == nil ? nil : width * 0.4, alignment: .leading)
                    .frame(maxWidth: track == nil ? .infinity : nil, alignment: .leading)
            } else if let prompt {
                CalendarPromptCard(prompt: prompt, action: onCalendarPrompt).frame(width: width * 0.4)
            }
        }
        .frame(width: width, height: NotchGeometry.idleHomeHeight)
    }

    private func musicHalf(_ track: NowPlaying) -> some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                if artwork != nil {
                    IdleArtwork(artwork: artwork, size: 56).id(artwork).transition(.opacity)
                } else {
                    SpinningRecord(app: track.app, playing: track.isPlaying, animated: animated, size: 56)
                }
                if let badge {
                    Image(nsImage: badge).resizable().frame(width: 18, height: 18)
                        .padding(1.5).background(Circle().fill(.black))
                        .offset(x: 3, y: -3)
                        .accessibilityLabel(track.app.displayName)
                }
            }
            .onTapGesture(perform: onOpenPlayer)
            .animation(Motion.fade, value: artwork)
            VStack(alignment: .leading, spacing: 2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(TextSafety.visible(track.title))
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    if !track.artist.isEmpty {
                        Text(TextSafety.visible(track.artist))
                            .font(.system(size: 11.5)).foregroundStyle(accent)
                    }
                }
                .contentTransition(.opacity)
                .animation(Motion.fade, value: track.title)
                .animation(Motion.fade, value: accent)
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
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func control(_ symbol: String, _ label: String, _ command: MusicCommand, size: CGFloat) -> some View {
        MusicControlButton(symbol: symbol, label: label, allowed: controlsAllowed, size: size) { onMusic(command) }
    }

    @ViewBuilder private func progress(_ track: NowPlaying) -> some View {
        if let duration = track.duration {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in progressRow(track.position(at: timeline.date), duration) }
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
                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(accent)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    Capsule().fill(accent).frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 3)
            .accessibilityElement()
            .accessibilityLabel("Progress")
            .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
            Text("-" + Self.clock(max(0, duration - position)))
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private var agendaHalf: some View {
        AgendaWeekView(events: agenda, onOpenCalendar: onOpenCalendar)
            .padding(.vertical, 8)
    }
}

struct AgendaWeekView: View {
    var events: [AgendaEvent]
    var onOpenCalendar: () -> Void
    /// Lets snapshots show a day other than today selected.
    var selectedOverride: Date? = nil
    @State private var picked: (day: Date, today: Date)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var strip

    static let todayBlue = Color(red: 0.04, green: 0.52, blue: 1)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let week = AgendaWeek(now: context.date, calendar: .current)
            // A pick from before midnight no longer applies: back to today.
            let day = selectedOverride ?? picked.flatMap { $0.today == week.today ? $0.day : nil } ?? week.today
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 6) {
                    monthYear(week.today)
                    HStack(spacing: 0) {
                        ForEach(week.days, id: \.self) { d in dayButton(d, week: week, selected: d == day) }
                    }
                    .animation(reduceMotion ? Motion.fade : Motion.panel, value: day)
                }
                rows(for: day, week: week, now: context.date)
                    .animation(Motion.fade, value: day)
                Spacer(minLength: 0)
            }
        }
        .onAppear { picked = nil }
    }

    private func monthYear(_ today: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(today.formatted(.dateTime.month(.abbreviated))).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
            Text(today.formatted(.dateTime.year())).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
        }
        .frame(width: 36, alignment: .leading)
    }

    private func dayButton(_ day: Date, week: AgendaWeek, selected: Bool) -> some View {
        let isToday = day == week.today
        return Button { picked = (day, week.today) } label: {
            VStack(spacing: 2) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(isToday || selected ? 0.9 : 0.5))
                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(day < week.today ? 0.45 : 0.9))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(isToday ? Self.todayBlue : .clear))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .background { if selected { dayHighlight } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var dayHighlight: some View {
        let highlight = RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(0.1))
        if reduceMotion { highlight } else { highlight.matchedGeometryEffect(id: "selected", in: strip) }
    }

    @ViewBuilder private func rows(for day: Date, week: AgendaWeek, now: Date) -> some View {
        let list = week.events(on: day, from: events, now: now, calendar: .current)
        if list.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.checkmark").font(.system(size: 16)).foregroundStyle(.white.opacity(0.6))
                VStack(alignment: .leading, spacing: 1) {
                    Text(day == week.today ? "No events today" : "No events").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                    Text("Enjoy your free time!").font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.leading, 4)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(list.prefix(2).enumerated()), id: \.element.id) { index, event in
                    row(event, more: index == 1 ? list.count - 2 : 0)
                }
            }
        }
    }

    private func row(_ event: AgendaEvent, more: Int) -> some View {
        HStack(spacing: 6) {
            Text(Agenda.timeLabel(event.start, calendar: .current, locale: .current))
                .font(.system(size: 10.5, weight: .semibold).monospacedDigit()).foregroundStyle(.white.opacity(0.6))
                .lineLimit(1).frame(width: 52, alignment: .leading)
            RoundedRectangle(cornerRadius: 1).fill(Self.color(event)).frame(width: 3, height: 12)
            Text(TextSafety.visible(event.title)).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.9))
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            if more > 0 {
                Text("+\(more) more").font(.system(size: 10.5, weight: .medium)).foregroundStyle(.white.opacity(0.5)).fixedSize()
            }
        }
        .frame(height: 15)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenCalendar)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private static func color(_ event: AgendaEvent) -> Color {
        guard let rgb = event.color else { return SessionState.working.color }
        return Color(red: Double(rgb >> 16 & 0xFF) / 255, green: Double(rgb >> 8 & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }
}

struct MusicControlButton: View {
    var symbol: String
    var label: String
    var allowed: Bool
    var size: CGFloat = 12
    var action: () -> Void
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .font(.system(size: size, weight: .semibold))
                .frame(width: max(36, size + 16), height: max(36, size + 6))
                .foregroundStyle(.white.opacity(allowed ? (hovered ? 1 : 0.8) : 0.3))
                .background(Circle().fill(.white.opacity(hovered ? 0.16 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { hovered = $0 }
        .animation(Motion.hover, value: hovered)
        .animation(Motion.fade, value: symbol)
        .help(allowed ? label : "Allow Raven Island to control this app in System Settings → Privacy & Security → Automation")
        .accessibilityLabel(label)
    }
}

struct HeaderMiniPlayer: View {
    var nowPlaying: NowPlaying
    var allowed: Bool
    var animated: Bool
    /// The artwork's colour; the player's colour until there is one.
    var tint: Color?
    var onPlayPause: () -> Void
    var onOpenPlayer: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onOpenPlayer) {
                Marquee(text: TextSafety.visible(nowPlaying.title), color: tint ?? SpinningRecord.color(for: nowPlaying.app), animated: animated)
                    .padding(.horizontal, 4).padding(.vertical, 3)
                    .background(Capsule().fill(.white.opacity(hovered ? 0.16 : 0)))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
            .onHover { hovered = $0 }
            .animation(Motion.hover, value: hovered)
            .help("Open \(nowPlaying.app.displayName)")
            .frame(minWidth: 40, maxWidth: .infinity)
            .layoutPriority(-1)
            .accessibilityLabel("Now playing: \(TextSafety.visible(nowPlaying.title))")
            .accessibilityHint("Opens \(nowPlaying.app.displayName)")
            HeaderIconButton(symbol: nowPlaying.isPlaying ? "pause.fill" : "play.fill",
                             label: nowPlaying.isPlaying ? "Pause" : "Play", action: onPlayPause)
                .opacity(allowed ? 1 : 0.4)
        }
    }
}

struct Marquee: View {
    var text: String
    var color: Color
    var animated: Bool

    private static let font = NSFont.systemFont(ofSize: 11, weight: .medium)
    private static let speed: CGFloat = 25
    private static let pause: Double = 1.5
    private static let gap: CGFloat = 28

    private var label: some View {
        Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(color).lineLimit(1)
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

struct SpinningRecord: View {
    var app: MusicApp
    var playing: Bool
    var animated: Bool
    var size: CGFloat
    @State private var angle: Double = 0
    @State private var startedAt: Date?

    static func color(for app: MusicApp) -> Color {
        app == .spotify ? Color(red: 0x1D / 255.0, green: 0xB9 / 255.0, blue: 0x54 / 255.0)
                        : Color(red: 0xFA / 255.0, green: 0x2D / 255.0, blue: 0x48 / 255.0)
    }

    private var label: Color { Self.color(for: app) }

    var body: some View {
        Group {
            if playing && animated {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    disc.rotationEffect(.degrees(angle + context.date.timeIntervalSince(startedAt ?? context.date) * 180))
                }
                .onAppear { startedAt = Date() }
                .onDisappear { keepAngle() }
            } else {
                disc.rotationEffect(.degrees(angle))
            }
        }
        .onChange(of: playing) { _, nowPlaying in
            guard animated else { return }
            if nowPlaying { startedAt = Date() } else { keepAngle() }
        }
        .frame(width: size, height: size)
        .background(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).fill(.white.opacity(0.06)))
        .accessibilityHidden(true)
    }

    /// Holds the record where it stopped instead of snapping back.
    private func keepAngle() {
        if let startedAt { angle += Date().timeIntervalSince(startedAt) * 180 }
        startedAt = nil
    }

    private var disc: some View {
        ZStack {
            Circle().fill(Color(white: 0.07))
            ForEach([0.86, 0.72, 0.58], id: \.self) { r in
                Circle().stroke(.white.opacity(0.08), lineWidth: 0.8).frame(width: size * 0.9 * r, height: size * 0.9 * r)
            }
            Circle().fill(label).frame(width: size * 0.34, height: size * 0.34)
            Rectangle().fill(.white.opacity(0.35)).frame(width: size * 0.12, height: 1.5).offset(x: size * 0.08)
            Circle().fill(.black).frame(width: size * 0.06, height: size * 0.06)
        }
        .frame(width: size * 0.9, height: size * 0.9)
    }
}

/// The playing app's own icon, as macOS draws it; nothing is bundled.
enum PlayerBadge {
    @MainActor private static var cache: [MusicApp: NSImage?] = [:]

    @MainActor static func image(for app: MusicApp?) -> NSImage? {
        guard let app else { return nil }
        if let cached = cache[app] { return cached }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
        cache[app] = icon
        return icon
    }
}

/// Why the calendar side is missing, and the one step that fixes it.
enum CalendarPrompt: Equatable {
    case turnOn, allow, openSettings

    /// The words before and after "Calendar", which the card sets in bold.
    var message: (String, String) {
        switch self {
        case .turnOn: return ("Turn on ", " to see your week here.")
        case .allow: return ("Allow ", " access to see your week here.")
        case .openSettings: return ("", " access is off in System Settings.")
        }
    }

    var button: String {
        switch self {
        case .turnOn: return "Turn On"
        case .allow: return "Allow"
        case .openSettings: return "Open Settings"
        }
    }
}

struct CalendarPromptCard: View {
    var prompt: CalendarPrompt
    var action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.plus").font(.system(size: 22)).foregroundStyle(.white.opacity(0.6))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                (Text(prompt.message.0).foregroundStyle(.white.opacity(0.65))
                    + Text("Calendar").fontWeight(.bold).foregroundStyle(.white)
                    + Text(prompt.message.1).foregroundStyle(.white.opacity(0.65)))
                    .font(.system(size: 11.5))
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: action) {
                    Text(prompt.button).font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(Capsule().fill(AgendaWeekView.todayBlue))
                        .foregroundStyle(.white)
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }
}

/// Left of the header when no music shows there: today's date and the next event still to come today.
struct HeaderToday: View {
    var agenda: [AgendaEvent]
    var now: Date

    var body: some View {
        let next = Agenda.remainingToday(agenda, now: now, calendar: .current, limit: 1).first
        HStack(spacing: 5) {
            Text(now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
            if let next {
                Text(next.start <= now ? "Now" : Agenda.timeLabel(next.start, calendar: .current, locale: .current))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(AgendaWeekView.todayBlue)
                Text(TextSafety.visible(next.title))
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)).truncationMode(.tail)
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}
