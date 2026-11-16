import SwiftUI
import RavenIslandCore

/// One of the flock, drawn as pixel art. What it is doing shows what its session is doing.
struct PixelBot: View {
    enum Mode: Equatable {
        case state(SessionState, WorkKind)
        case walk
        case trick
        case listening(playing: Bool)
    }

    var mode: Mode
    var persona: Persona
    var size: CGFloat = 20
    var animated = true
    /// Mirror the drawing, for walking to the left.
    var flipped = false
    /// Draw exactly this frame instead of running the animation (the caller is already ticking).
    var fixedFrame: Int?
    @Environment(\.ravenHeadphones) private var headphones

    init(state: SessionState, work: WorkKind = .building, persona: Persona, size: CGFloat = 20, animated: Bool = true) {
        self.mode = .state(state, work); self.persona = persona; self.size = size; self.animated = animated
    }

    init(mode: Mode, persona: Persona, size: CGFloat = 20, animated: Bool = true, flipped: Bool = false, fixedFrame: Int? = nil) {
        self.mode = mode; self.persona = persona; self.size = size; self.animated = animated; self.flipped = flipped
        self.fixedFrame = fixedFrame
    }

    /// Frames are wider than they are tall: `size` is the height.
    static let aspect = CGFloat(PixelSprites.width) / CGFloat(PixelSprites.size)

    static func color(hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    static func paletteColor(_ pixel: Character, persona: Persona) -> Color? {
        (persona.colors[pixel] ?? PixelSprites.sharedColors[pixel]).map(color(hex:))
    }

    static func draw(_ frame: [String], persona: Persona, in context: inout GraphicsContext, size: CGSize) {
        let px = size.height / CGFloat(PixelSprites.size)
        for (r, row) in frame.enumerated() {
            for (c, pixel) in row.enumerated() {
                guard let fill = paletteColor(pixel, persona: persona) else { continue }
                // Slight overlap hides hairline seams between neighbouring pixels.
                let rect = CGRect(x: CGFloat(c) * px, y: CGFloat(r) * px, width: px + 0.6, height: px + 0.6)
                context.fill(Path(rect), with: .color(fill))
            }
        }
    }

    private var frames: [[String]] {
        switch mode {
        case .state(let state, let work): return PixelSprites.frames(for: state, persona: persona, work: work, headphones: headphones)
        case .walk: return PixelSprites.walkFrames(persona: persona, headphones: headphones)
        case .trick: return PixelSprites.trickFrames(persona: persona, headphones: headphones)
        case .listening(let playing): return PixelSprites.listeningFrames(persona: persona, playing: playing)
        }
    }

    private var frameDuration: Double {
        switch mode {
        case .state(let state, let work):
            if state == .working { return work == .building ? 0.22 : 0.4 }
            return PixelSprites.frameDuration(for: state)
        case .walk: return 0.25
        case .trick: return 0.28
        case .listening: return 0.5
        }
    }

    private var label: String {
        switch mode {
        case .state(let state, let work): return state == .working ? work.label : state.label
        case .walk: return "\(persona.name) the \(persona.role), keeping watch"
        case .trick: return "\(persona.name) the \(persona.role)"
        case .listening(let playing): return playing ? "Listening to music" : "Music paused"
        }
    }

    var body: some View {
        let frames = self.frames
        let duration = frameDuration
        Group {
            if let fixedFrame {
                Canvas { context, size in Self.draw(frames[fixedFrame % frames.count], persona: persona, in: &context, size: size) }
            } else if animated {
                TimelineView(.periodic(from: .now, by: duration)) { timeline in
                    let index = Int(timeline.date.timeIntervalSinceReferenceDate / duration) % frames.count
                    Canvas { context, size in Self.draw(frames[index], persona: persona, in: &context, size: size) }
                }
            } else {
                // Still image: the last frame is the most telling one for every animation.
                Canvas { context, size in Self.draw(frames[frames.count - 1], persona: persona, in: &context, size: size) }
            }
        }
        .frame(width: size * Self.aspect, height: size)
        // Mirror about the raven's own middle, not the middle of the wider canvas that also holds its prop.
        .scaleEffect(x: flipped ? -1 : 1, y: 1,
                     anchor: UnitPoint(x: CGFloat(PixelSprites.bodyWidth) / 2 / CGFloat(PixelSprites.width), y: 0.5))
        .accessibilityLabel(label)
    }
}

/// A character pacing back and forth across `range` points. With `tricks` on, it stops and does its
/// party trick while the pointer is on it.
struct Stroller: View {
    var persona: Persona
    var size: CGFloat
    var range: CGFloat
    /// Points per second.
    var speed: CGFloat = 16
    /// 0–1: where in its lap it starts, so a group doesn't move in step.
    var phase: Double = 0
    var animated = true
    var tricks = false
    /// Seconds between redraws. The strollers beside the notch are always on screen, so they tick slowly.
    var tick: Double = 0.125
    var onHover: (Bool) -> Void = { _ in }

    @State private var hovering = false
    @State private var pausedTotal: TimeInterval = 0
    @State private var pauseStart: Date?

    private var travel: CGFloat { max(0, range - size * CGFloat(PixelSprites.bodyWidth) / CGFloat(PixelSprites.size)) }

    /// Position along the lap and whether it is on the way back, at `time` seconds of walking.
    private func position(at time: TimeInterval) -> (x: CGFloat, returning: Bool) {
        guard travel > 0, speed > 0 else { return (0, false) }
        let lap = Double(travel) * 2
        let along = (time * Double(speed) + phase * lap).truncatingRemainder(dividingBy: lap)
        let x = along < Double(travel) ? along : lap - along
        let px = Double(size) / Double(PixelSprites.size)   // move in whole pixels, like a sprite
        return (CGFloat((x / px).rounded() * px), along >= Double(travel))
    }

    var body: some View {
        Group {
            if animated {
                TimelineView(.periodic(from: .now, by: tick)) { timeline in
                    let now = timeline.date
                    let paused = pausedTotal + (pauseStart.map { now.timeIntervalSince($0) } ?? 0)
                    let walked = now.timeIntervalSinceReferenceDate - paused
                    let spot = position(at: walked)
                    let performing = tricks && hovering
                    let beat = Int(now.timeIntervalSinceReferenceDate / 0.28)
                    // A little hop on every other beat while performing.
                    let hop: CGFloat = performing && beat % 2 == 0 ? -size * 0.12 : 0
                    PixelBot(mode: performing ? .trick : .walk, persona: persona, size: size,
                             flipped: spot.returning && !performing,
                             fixedFrame: performing ? beat : Int(walked / max(tick, 0.25)))
                        .onHover { inside in
                            guard tricks else { return }
                            hovering = inside
                            if inside { pauseStart = Date() }
                            else if let start = pauseStart { pausedTotal += Date().timeIntervalSince(start); pauseStart = nil }
                            onHover(inside)
                        }
                        .offset(x: spot.x, y: hop)
                }
            } else {
                PixelBot(mode: .walk, persona: persona, size: size, animated: false)
                    .offset(x: travel * CGFloat(phase))
            }
        }
        .frame(width: range, height: size, alignment: .leading)
    }
}

/// Shown when nothing is running: the whole flock strolling about. Point at one and it shows off.
struct CrewStage: View {
    var width: CGFloat
    var animated = true
    static let height: CGFloat = 88
    @State private var pointed: String?

    private var caption: String {
        if let id = pointed, let p = PixelSprites.personas.first(where: { $0.id == id }) {
            return "\(p.name) the \(p.role) — \(p.motto)"
        }
        return "Nothing running. The ravens are keeping watch."
    }

    var body: some View {
        let crew = PixelSprites.personas
        VStack(spacing: 6) {
            ZStack(alignment: .leading) {
                ForEach(Array(crew.enumerated()), id: \.element.id) { index, persona in
                    Stroller(persona: persona, size: 40, range: width,
                             speed: 13 + CGFloat((index * 7) % 11), phase: Double(index) / Double(crew.count) * 0.5 + (index % 2 == 0 ? 0 : 0.5),
                             animated: animated, tricks: true) { inside in
                        if inside { pointed = persona.id } else if pointed == persona.id { pointed = nil }
                    }
                }
            }
            .frame(width: width, height: 46, alignment: .bottomLeading)
            Text(caption)
                .font(.system(size: 11.5, weight: pointed == nil ? .regular : .medium))
                .foregroundStyle(.white.opacity(pointed == nil ? 0.5 : 0.85))
                .lineLimit(1)
        }
        .frame(width: width, height: Self.height)
    }
}

private struct RavenHeadphonesKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Music is playing: every raven drawn below puts headphones on.
    var ravenHeadphones: Bool {
        get { self[RavenHeadphonesKey.self] }
        set { self[RavenHeadphonesKey.self] = newValue }
    }
}
