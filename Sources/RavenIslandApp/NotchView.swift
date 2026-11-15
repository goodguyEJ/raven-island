import SwiftUI
import RavenIslandCore

/// Rotating arc. Drawn by hand so it also renders in offscreen snapshots.
struct SpinnerArc: View {
    var color: Color
    var animated: Bool
    @State private var turning = false

    var body: some View {
        Circle()
            .trim(from: 0.08, to: 0.78)
            .stroke(color, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            .rotationEffect(.degrees(turning ? 360 : 0))
            .onAppear {
                guard animated else { return }
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { turning = true }
            }
    }
}

struct StatusGlyph: View {
    var state: SessionState
    var size: CGFloat = 14
    var animated = true
    @State private var pulsing = false

    var body: some View {
        Group {
            switch state {
            case .working:
                SpinnerArc(color: state.color, animated: animated).frame(width: size - 2, height: size - 2)
            case .idle:
                Circle().fill(state.color).frame(width: size * 0.5, height: size * 0.5)
            default:
                Image(systemName: symbol)
                    .resizable().scaledToFit()
                    .frame(width: size, height: size)
                    .foregroundStyle(state.color)
                    .opacity(state.needsAttention && pulsing ? 0.45 : 1)
                    .onAppear {
                        guard animated, state.needsAttention else { return }
                        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulsing = true }
                    }
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(state.label)
    }

    private var symbol: String {
        switch state {
        case .needsApproval: return "exclamationmark.circle.fill"
        case .waitingForInput: return "ellipsis.bubble.fill"
        case .done: return "checkmark.circle.fill"
        case .error: return "xmark.octagon.fill"
        case .working, .idle: return "circle.fill"
        }
    }
}

struct SessionRow: View {
    var session: Session
    var now: Date
    var animated: Bool
    var characters = true
    var onSelect: (Session) -> Void
    /// Nil hides the clear button: a session with a decision waiting can't be cleared from under it.
    var onDismiss: ((Session) -> Void)? = nil
    @State private var hovered = false
    @State private var checkHovered = false

    var body: some View {
        HStack(spacing: 11) {
            if characters {
                let persona = PixelSprites.persona(for: session.id)
                Group {
                    if session.state == .idle {
                        // Nothing to do yet: it paces.
                        Stroller(persona: persona, size: 28, range: 40, speed: 8, animated: animated, tick: 0.25)
                    } else {
                        PixelBot(state: session.state, work: session.workKind, persona: persona, size: 34, animated: animated)
                    }
                }
                .frame(width: 46, height: 34, alignment: .leading)
            } else {
                StatusGlyph(state: session.state, size: 15, animated: animated)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(TextSafety.visible(session.projectName)).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    if session.subagents > 0 {
                        Text("+\(session.subagents)")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(.white.opacity(0.14)))
                            .foregroundStyle(.white.opacity(0.75))
                            .accessibilityLabel("\(session.subagents) subagents")
                    }
                }
                Text(TextSafety.visible(subtitle))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(session.state == .working ? session.workKind.label : session.state.label)
                    .font(.system(size: 11.5, weight: .medium)).foregroundStyle(session.state.color)
                Text(elapsed(since: session.stateSince, now: now))
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.45))
            }
            // "Done with this one": clears the row until the session does something new.
            if let onDismiss {
                Button { onDismiss(session) } label: {
                    Image(systemName: checkHovered ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.system(size: 17))
                        .foregroundStyle(checkHovered ? Color.green : .white.opacity(session.state == .done ? 0.6 : 0.3))
                        .frame(width: 26, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { checkHovered = $0 }
                .help("Clear from the list. It comes back if the session does something new.")
                .accessibilityLabel("Clear \(session.projectName) from the list")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: NotchGeometry.rowHeight - 4)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.white.opacity(hovered ? 0.12 : (session.state.needsAttention ? 0.07 : 0))))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture { onSelect(session) }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        if session.state == .working || session.state == .needsApproval, let a = session.activity { return a }
        return session.title ?? session.activity ?? session.cwd ?? ""
    }
}

/// The panel's outline. Hanging from the notch, its top corners curve outward into the top edge of
/// the screen, so the panel reads as part of the notch; floating, it is an ordinary rounded shape.
struct NotchPanelShape: Shape {
    var ear: CGFloat
    var bottom: CGFloat
    var top: CGFloat

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(ear, AnimatablePair(bottom, top)) }
        set { ear = newValue.first; bottom = newValue.second.first; top = newValue.second.second }
    }

    func path(in rect: CGRect) -> Path {
        guard ear > 0 else {
            return UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom,
                                          bottomTrailingRadius: bottom, topTrailingRadius: top, style: .continuous)
                .path(in: rect)
        }
        let w = rect.width, h = rect.height
        let b = min(bottom, (w - 2 * ear) / 2, h - ear)
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addQuadCurve(to: CGPoint(x: ear, y: ear), control: CGPoint(x: ear, y: 0))
        p.addLine(to: CGPoint(x: ear, y: h - b))
        p.addQuadCurve(to: CGPoint(x: ear + b, y: h), control: CGPoint(x: ear, y: h))
        p.addLine(to: CGPoint(x: w - ear - b, y: h))
        p.addQuadCurve(to: CGPoint(x: w - ear, y: h - b), control: CGPoint(x: w - ear, y: h))
        p.addLine(to: CGPoint(x: w - ear, y: ear))
        p.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w - ear, y: 0))
        p.closeSubpath()
        return p.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

struct HeaderUsage: View {
    var usage: UsageSnapshot
    var now: Date

    private func color(_ percent: Double) -> Color {
        switch UsageSnapshot.level(percent) {
        case .normal: return Color(red: 0.36, green: 0.80, blue: 0.48)
        case .warning: return .orange
        case .critical: return Color(red: 1.0, green: 0.35, blue: 0.32)
        }
    }

    private func window(_ label: String, _ w: UsageWindow) -> some View {
        HStack(spacing: 3) {
            Text(label).foregroundStyle(.white.opacity(0.55))
            Text("\(Int(w.usedPercent.rounded()))%").foregroundStyle(color(w.usedPercent))
            if let reset = w.resetsAt {
                Text(UsageSnapshot.countdown(to: reset, now: now).replacingOccurrences(of: " ", with: ""))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label == "5h" ? "Five hour" : "Weekly") limit \(Int(w.usedPercent.rounded())) percent used")
    }

    var body: some View {
        HStack(spacing: 6) {
            if let five = usage.fiveHour { window("5h", five) }
            if usage.fiveHour != nil, usage.sevenDay != nil {
                Rectangle().fill(.white.opacity(0.25)).frame(width: 1, height: 10)
            }
            if let week = usage.sevenDay { window("7d", week) }
        }
        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
}

/// Decisions waiting behind the one on screen. They come up on their own, in order, as each is answered.
struct UpNextStrip: View {
    var queued: [PendingRequest]

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.turn.down.right").font(.system(size: 10, weight: .bold))
                .foregroundStyle(SessionState.needsApproval.color)
            Text("Up next").font(.system(size: 11, weight: .semibold)).foregroundStyle(SessionState.needsApproval.color)
            if let next = queued.first {
                Text("\(TextSafety.visible(next.projectName)) · \(TextSafety.visible(next.title))")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1).truncationMode(.tail)
            }
            if queued.count > 1 {
                Text("+\(queued.count - 1) more").font(.system(size: 11)).foregroundStyle(.white.opacity(0.45)).fixedSize()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(height: NotchGeometry.pagerHeight)
        .accessibilityElement(children: .combine)
    }
}

struct HeaderIconButton: View {
    var symbol: String
    var label: String
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 24, height: 22)
                .foregroundStyle(.white.opacity(hovered ? 1 : 0.75))
                .background(Circle().fill(.white.opacity(hovered ? 0.16 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// The panel itself: a black shape that is either notch-sized (collapsed) or a session list (expanded).
struct NotchContentView: View {
    var sessions: [Session]
    var expanded: Bool
    var geometry: NotchGeometry
    var animated = true
    /// The request currently shown as a card, and how many more are queued behind it.
    var request: PendingRequest? = nil
    /// Decisions waiting behind `request`, in the order they'll be shown.
    var queued: [PendingRequest] = []
    /// Sessions with a decision waiting; their rows can't be cleared.
    var waitingSessionIDs: Set<String> = []
    var usage: UsageSnapshot? = nil
    var characters = true
    var showAll = false
    var soundsOn = false
    var onSelect: (Session) -> Void = { _ in }
    var onDismiss: (Session) -> Void = { _ in }
    var onClearFinished: () -> Void = {}
    var onDecision: (PendingRequest, Decision) -> Void = { _, _ in }
    var onReviewed: (PendingRequest) -> Void = { _ in }
    var onEditing: (PendingRequest, Bool) -> Void = { _, _ in }
    var onShowAll: (Bool) -> Void = { _ in }
    var onToggleSound: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var nowPlaying: NowPlaying? = nil
    var artwork: NSImage? = nil
    var controlsAllowed = true
    var agenda: [AgendaEvent] = []
    var onMusic: (MusicCommand) -> Void = { _ in }
    var onOpenPlayer: () -> Void = {}
    var onOpenCalendar: () -> Void = {}

    private var focus: Bool { request != nil && !showAll }
    private var focusSession: Session? { request.flatMap { r in sessions.first { $0.id == r.sessionID } } }
    private var ear: CGFloat { geometry.earRadius(expanded: expanded, sessionCount: sessions.count) }
    private var cardHeight: CGFloat { request.map(RequestCard.height(for:)) ?? 0 }
    private var visibleRows: Int { NotchGeometry.visibleRows(sessionCount: sessions.count, hasCard: request != nil) }
    @State private var page = 0
    private var pageCount: Int { max(1, Int((Double(sessions.count) / Double(visibleRows)).rounded(.up))) }
    private var currentPage: Int { min(page, pageCount - 1) }
    private var pageSessions: [Session] {
        Array(sessions.dropFirst(currentPage * visibleRows).prefix(visibleRows))
    }
    /// Sessions on other pages that need you, so the pager can call them out.
    private var attentionElsewhere: Int {
        sessions.enumerated().filter { $0.element.state.needsAttention && $0.offset / visibleRows != currentPage }.count
    }

    private var size: CGSize {
        expanded ? geometry.expandedSize(sessionCount: sessions.count, cardHeight: cardHeight, focus: focus, queued: queued.count)
                 : geometry.collapsedSize(sessionCount: sessions.count)
    }

    private var shape: NotchPanelShape {
        let bottom: CGFloat = expanded ? 22 : (geometry.hasNotch ? 10 : NotchGeometry.pillHeight / 2)
        return NotchPanelShape(ear: ear, bottom: bottom, top: geometry.hasNotch ? 0 : bottom)
    }

    private var attention: Int { sessions.filter { $0.state.needsAttention }.count }
    private var finished: Int { sessions.filter { $0.state == .done }.count }
    private var headline: SessionState { sessions.first?.state ?? .idle }   // list is sorted most-urgent first

    var body: some View {
        ZStack(alignment: .top) {
            shape.fill(.black)
            Group {
                if expanded { expandedBody.transition(.opacity) } else { collapsedBody.transition(.opacity) }
            }
            .padding(.horizontal, ear)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .contentShape(shape)
        .animation(animated ? .spring(response: 0.36, dampingFraction: 0.82) : nil, value: sessions.count)
        .animation(animated ? .spring(response: 0.36, dampingFraction: 0.82) : nil, value: request?.id)
        .animation(animated ? .spring(response: 0.36, dampingFraction: 0.82) : nil, value: showAll)
    }

    @ViewBuilder private var collapsedBody: some View {
        if sessions.isEmpty, geometry.idleStroll || geometry.idleHome.hasCollapsedContent {
            // Nothing running: two of the flock stroll beside the notch (a different pair each hour),
            // unless a wing has something playing or coming up to show instead.
            let crew = PixelSprites.personas
            let hour = Calendar.current.component(.hour, from: Date())
            let side = min(geometry.hasNotch ? geometry.notchHeight - 6 : NotchGeometry.pillHeight - 4, 26)
            let idle = geometry.idleHome
            if geometry.hasNotch {
                HStack(spacing: 0) {
                    Group {
                        if idle.hasTrack {
                            musicWing(idle, side: side, persona: crew[hour % crew.count])
                        } else if geometry.idleStroll {
                            Stroller(persona: crew[hour % crew.count], size: side, range: NotchGeometry.wing - 6, speed: 4, animated: animated, tick: 0.5)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: NotchGeometry.wing)
                    Color.clear.frame(width: geometry.notchWidth)
                    Group {
                        if let label = idle.collapsedLabel {
                            IdleAgendaWing(label: label)
                        } else if geometry.idleStroll {
                            Stroller(persona: crew[(hour + 3) % crew.count], size: side, range: NotchGeometry.wing - 6, speed: 3, phase: 0.5, animated: animated, tick: 0.5)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: NotchGeometry.wing)
                }
                .frame(height: geometry.notchHeight)
            } else if idle.hasCollapsedContent {
                HStack(spacing: 10) {
                    if idle.hasTrack { musicWing(idle, side: side, persona: crew[hour % crew.count]) }
                    if let label = idle.collapsedLabel { IdleAgendaWing(label: label) }
                }
                .frame(height: NotchGeometry.pillHeight)
            } else {
                Stroller(persona: crew[hour % crew.count], size: side, range: 80, speed: 6, animated: animated, tick: 0.5)
                    .frame(height: NotchGeometry.pillHeight)
            }
        } else if sessions.isEmpty {
            if !geometry.hasNotch {
                Image(systemName: "bird.fill").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    .frame(height: NotchGeometry.pillHeight)
            }
        } else if geometry.hasNotch {
            HStack(spacing: 0) {
                headlineMark(size: geometry.notchHeight - 6).frame(width: NotchGeometry.wing)
                Color.clear.frame(width: geometry.notchWidth)
                countLabel.frame(width: NotchGeometry.wing)
            }
            .frame(height: geometry.notchHeight)
        } else {
            HStack(spacing: 7) {
                headlineMark(size: 18)
                Text(headline.label).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                if sessions.count > 1 { countLabel }
            }
            .padding(.horizontal, 10)
            .frame(height: NotchGeometry.pillHeight)
        }
    }

    @ViewBuilder private func musicWing(_ idle: IdleHome, side: CGFloat, persona: Persona) -> some View {
        if characters {
            PixelBot(mode: .listening(playing: idle.isPlaying), persona: persona, size: side, animated: animated,
                     fixedFrame: animated ? nil : 0)
        } else {
            IdleMusicWing(artwork: artwork, playing: idle.isPlaying, size: 18, animated: animated)
        }
    }

    /// Page controls under the list: "‹ 1 of 3 ›", how many more are running, and whether any of them
    /// need you. The list is sorted most urgent first, so page 1 always holds what needs attention.
    private var pager: some View {
        let hidden = sessions.count - pageSessions.count
        return HStack(spacing: 10) {
            pageButton("chevron.left", enabled: currentPage > 0) { page = currentPage - 1 }
            Text("\(currentPage + 1) of \(pageCount)")
                .font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(.white.opacity(0.75))
            pageButton("chevron.right", enabled: currentPage < pageCount - 1) { page = currentPage + 1 }
            Text("+\(hidden) more running")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            if attentionElsewhere > 0 {
                Text("· \(attentionElsewhere) need\(attentionElsewhere == 1 ? "s" : "") you")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(SessionState.needsApproval.color)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .frame(height: NotchGeometry.pagerHeight)
    }

    private func pageButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold))
                .frame(width: 22, height: 20)
                .background(Capsule().fill(.white.opacity(enabled ? 0.14 : 0.05)))
                .foregroundStyle(.white.opacity(enabled ? 0.9 : 0.3))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(symbol == "chevron.left" ? "Previous page" : "Next page")
    }

    /// The most urgent session, as its bot (or a plain status icon if characters are off).
    @ViewBuilder private func headlineMark(size: CGFloat) -> some View {
        if characters, let first = sessions.first {
            PixelBot(state: first.state, work: first.workKind, persona: PixelSprites.persona(for: first.id),
                     size: min(size, 26), animated: animated)
        } else {
            StatusGlyph(state: headline, size: min(size, 14), animated: animated)
        }
    }

    private var countLabel: some View {
        Text("\(attention > 0 ? attention : sessions.count)")
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .foregroundStyle(attention > 0 ? SessionState.needsApproval.color : .white.opacity(0.8))
            .accessibilityLabel(attention > 0 ? "\(attention) sessions need you" : "\(sessions.count) sessions")
    }

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                if let usage {
                    TimelineView(.periodic(from: .now, by: 30)) { timeline in HeaderUsage(usage: usage, now: timeline.date) }
                } else {
                    Text(sessions.isEmpty ? "Raven Island" : "\(sessions.count) session\(sessions.count == 1 ? "" : "s")")
                        .font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(width: geometry.headerSideWidth, alignment: .leading)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                if !sessions.isEmpty, request == nil, let nowPlaying {
                    HeaderMiniPlayer(nowPlaying: nowPlaying, compact: finished > 0, allowed: controlsAllowed, animated: animated,
                                     onPlayPause: { onMusic(.playPause) }, onOpenPlayer: onOpenPlayer)
                }
                if finished > 0 {
                    Button(action: onClearFinished) {
                        Text("Clear \(finished) done")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(.white.opacity(0.14)))
                            .foregroundStyle(.white.opacity(0.85))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                }
                HeaderIconButton(symbol: soundsOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
                                 label: soundsOn ? "Mute sounds" : "Turn sounds on", action: onToggleSound)
                HeaderIconButton(symbol: "gearshape.fill", label: "Settings", action: onOpenSettings)
            }
            .frame(width: geometry.headerSideWidth, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .frame(height: geometry.headerHeight)
    }

    private func rows(_ list: [Session]) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            VStack(spacing: 4) {
                ForEach(list) { s in
                    SessionRow(session: s, now: timeline.date, animated: animated, characters: characters,
                               onSelect: onSelect, onDismiss: waitingSessionIDs.contains(s.id) ? nil : onDismiss)
                }
            }
            .padding(.horizontal, 8)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func footerLink(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity).frame(height: NotchGeometry.pagerHeight).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var expandedBody: some View {
        VStack(spacing: 0) {
            header

            if focus, let request {
                rows(focusSession.map { [$0] } ?? []).frame(height: NotchGeometry.rowHeight)
                RequestCard(request: request, more: queued.count, live: animated,
                            onDecision: { onDecision(request, $0) }, onReviewed: { onReviewed(request) },
                            onEditing: { onEditing(request, $0) })
                    .id(request.id)   // fresh text fields and selections for each request
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                if !queued.isEmpty { UpNextStrip(queued: queued) }
                if sessions.count > 1 {
                    footerLink("Show all \(sessions.count) sessions") { onShowAll(true) }
                }
            } else {
                if let request {
                    RequestCard(request: request, more: queued.count, live: animated,
                                onDecision: { onDecision(request, $0) }, onReviewed: { onReviewed(request) },
                                onEditing: { onEditing(request, $0) })
                        .id(request.id)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                    if !queued.isEmpty { UpNextStrip(queued: queued) }
                }
                if sessions.isEmpty, request == nil, geometry.idleHome.showsPanel {
                    IdleHomePanel(idleHome: geometry.idleHome, nowPlaying: nowPlaying, artwork: artwork,
                                  controlsAllowed: controlsAllowed, agenda: agenda, width: size.width - 2 * ear - 36,
                                  animated: animated, onMusic: onMusic, onOpenPlayer: onOpenPlayer, onOpenCalendar: onOpenCalendar)
                } else if sessions.isEmpty, geometry.crewStage {
                    CrewStage(width: size.width - 2 * ear - 36, animated: animated)
                } else if sessions.isEmpty {
                    Text("No active sessions")
                        .font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity).frame(height: NotchGeometry.rowHeight)
                } else {
                    rows(pageSessions).frame(height: CGFloat(visibleRows) * NotchGeometry.rowHeight)
                    if sessions.count > visibleRows {
                        HStack(spacing: 0) {
                            pager
                            if request != nil { footerLink("Show less") { onShowAll(false) }.fixedSize().padding(.trailing, 18) }
                        }
                    } else if request != nil, sessions.count > 1 {
                        footerLink("Show less") { onShowAll(false) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

final class NotchState: ObservableObject {
    @Published var expanded = false
    /// While a decision is waiting, the panel shows only that session unless this is on.
    @Published var showAll = false
    @Published var geometry: NotchGeometry
    init(geometry: NotchGeometry) { self.geometry = geometry }
}

/// Live wrapper: pins the shape to the top centre of the (possibly larger) window.
struct NotchRootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var state: NotchState
    @ObservedObject var settings: Settings
    @ObservedObject var music: MusicSource
    @ObservedObject var calendar: CalendarSource
    var reduceMotion: Bool
    var onSelect: (Session) -> Void
    var onOpenSettings: () -> Void = {}
    var onOpenCalendar: () -> Void = {}

    var body: some View {
        NotchContentView(sessions: model.sessions, expanded: state.expanded, geometry: state.geometry,
                         animated: !reduceMotion, request: model.pending.first,
                         queued: Array(model.pending.dropFirst()),
                         waitingSessionIDs: Set(model.pending.map(\.sessionID)),
                         usage: settings.showUsage ? model.usage : nil, characters: settings.showCharacters,
                         showAll: state.showAll, soundsOn: settings.soundsEnabled,
                         onSelect: onSelect,
                         onDismiss: { model.dismiss($0.id) }, onClearFinished: { model.dismissFinished() },
                         onDecision: { request, decision in
                             model.resolve(request.id, decision)
                             // "Terminal" means the user wants to answer there, so take them to it.
                             if decision == .terminal, let s = model.session(id: request.sessionID) { _ = model.jump(s) }
                         },
                         onReviewed: { model.markReviewed($0.id) },
                         onEditing: { model.setEditing($0.id, $1) },
                         onShowAll: { state.showAll = $0 },
                         onToggleSound: { settings.soundsEnabled.toggle() },
                         onOpenSettings: onOpenSettings,
                         nowPlaying: music.nowPlaying, artwork: music.artwork, controlsAllowed: music.controlsAllowed,
                         agenda: calendar.events,
                         onMusic: { music.send($0) }, onOpenPlayer: { music.activatePlayer() },
                         onOpenCalendar: onOpenCalendar)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
