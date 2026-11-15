import SwiftUI
import CrowsNestCore

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
    var onDismiss: (Session) -> Void = { _ in }
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

/// The panel itself: a black shape that is either notch-sized (collapsed) or a session list (expanded).
struct NotchContentView: View {
    var sessions: [Session]
    var expanded: Bool
    var geometry: NotchGeometry
    var animated = true
    /// The request currently shown as a card, and how many more are queued behind it.
    var request: PendingRequest? = nil
    var moreRequests = 0
    var usage: UsageSnapshot? = nil
    var characters = true
    var onSelect: (Session) -> Void = { _ in }
    var onDismiss: (Session) -> Void = { _ in }
    var onClearFinished: () -> Void = {}
    var onDecision: (PendingRequest, Decision) -> Void = { _, _ in }
    var onReviewed: (PendingRequest) -> Void = { _ in }
    var onEditing: (PendingRequest, Bool) -> Void = { _, _ in }

    private var footerHeight: CGFloat { usage == nil ? 0 : UsageStrip.height }
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
        expanded ? geometry.expandedSize(sessionCount: sessions.count, cardHeight: cardHeight, footerHeight: footerHeight)
                 : geometry.collapsedSize(sessionCount: sessions.count)
    }

    private var shape: UnevenRoundedRectangle {
        let bottom: CGFloat = expanded ? 22 : (geometry.hasNotch ? 10 : NotchGeometry.pillHeight / 2)
        let top: CGFloat = geometry.hasNotch ? 0 : bottom
        return UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom,
                                      bottomTrailingRadius: bottom, topTrailingRadius: top, style: .continuous)
    }

    private var attention: Int { sessions.filter { $0.state.needsAttention }.count }
    private var finished: Int { sessions.filter { $0.state == .done }.count }
    private var headline: SessionState { sessions.first?.state ?? .idle }   // list is sorted most-urgent first

    var body: some View {
        ZStack(alignment: .top) {
            shape.fill(.black)
            if expanded { expandedBody.transition(.opacity) } else { collapsedBody.transition(.opacity) }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .contentShape(shape)
        .animation(animated ? .spring(response: 0.36, dampingFraction: 0.82) : nil, value: sessions.count)
        .animation(animated ? .spring(response: 0.36, dampingFraction: 0.82) : nil, value: request?.id)
    }

    @ViewBuilder private var collapsedBody: some View {
        if sessions.isEmpty, geometry.idleStroll {
            // Nothing running: two of the crew stroll beside the notch (a different pair each hour).
            let crew = PixelSprites.personas
            let hour = Calendar.current.component(.hour, from: Date())
            let side = min(geometry.hasNotch ? geometry.notchHeight - 6 : NotchGeometry.pillHeight - 4, 26)
            if geometry.hasNotch {
                HStack(spacing: 0) {
                    Stroller(persona: crew[hour % crew.count], size: side, range: NotchGeometry.wing - 6, speed: 4, animated: animated, tick: 0.5)
                        .frame(width: NotchGeometry.wing)
                    Color.clear.frame(width: geometry.notchWidth)
                    Stroller(persona: crew[(hour + 3) % crew.count], size: side, range: NotchGeometry.wing - 6, speed: 3, phase: 0.5, animated: animated, tick: 0.5)
                        .frame(width: NotchGeometry.wing)
                }
                .frame(height: geometry.notchHeight)
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

    private var expandedBody: some View {
        VStack(spacing: 0) {
            HStack {
                Text(sessions.isEmpty ? "Crow's Nest" : "\(sessions.count) session\(sessions.count == 1 ? "" : "s")")
                    .foregroundStyle(.white.opacity(0.7))
                if finished > 0 {
                    Button(action: onClearFinished) {
                        Text("Clear \(finished) done")
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(.white.opacity(0.14)))
                            .foregroundStyle(.white.opacity(0.85))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                }
                Spacer()
                if attention > 0 {
                    Text("\(attention) need\(attention == 1 ? "s" : "") you").foregroundStyle(SessionState.needsApproval.color)
                }
            }
            .font(.system(size: 11.5, weight: .medium))
            .padding(.horizontal, 18)
            .frame(height: geometry.headerHeight)

            if let request {
                RequestCard(request: request, more: moreRequests, live: animated,
                            onDecision: { onDecision(request, $0) }, onReviewed: { onReviewed(request) },
                            onEditing: { onEditing(request, $0) })
                    .id(request.id)   // fresh text fields and selections for each request
            }

            if sessions.isEmpty, geometry.crewStage {
                CrewStage(width: size.width - 36, animated: animated)
            } else if sessions.isEmpty {
                Text("No active sessions")
                    .font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity).frame(height: NotchGeometry.rowHeight)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    VStack(spacing: 4) {
                        ForEach(pageSessions) { s in
                            SessionRow(session: s, now: timeline.date, animated: animated, characters: characters, onSelect: onSelect, onDismiss: onDismiss)
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(height: CGFloat(visibleRows) * NotchGeometry.rowHeight)
                if sessions.count > visibleRows { pager }
            }
            if let usage {
                TimelineView(.periodic(from: .now, by: 30)) { timeline in
                    UsageStrip(usage: usage, now: timeline.date)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

final class NotchState: ObservableObject {
    @Published var expanded = false
    @Published var geometry: NotchGeometry
    init(geometry: NotchGeometry) { self.geometry = geometry }
}

/// Live wrapper: pins the shape to the top centre of the (possibly larger) window.
struct NotchRootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var state: NotchState
    @ObservedObject var settings: Settings
    var reduceMotion: Bool
    var onSelect: (Session) -> Void

    var body: some View {
        NotchContentView(sessions: model.sessions, expanded: state.expanded, geometry: state.geometry,
                         animated: !reduceMotion, request: model.pending.first,
                         moreRequests: max(0, model.pending.count - 1),
                         usage: settings.showUsage ? model.usage : nil, characters: settings.showCharacters,
                         onSelect: onSelect,
                         onDismiss: { model.dismiss($0.id) }, onClearFinished: { model.dismissFinished() },
                         onDecision: { request, decision in
                             model.resolve(request.id, decision)
                             // "Terminal" means the user wants to answer there, so take them to it.
                             if decision == .terminal, let s = model.session(id: request.sessionID) { _ = model.jump(s) }
                         },
                         onReviewed: { model.markReviewed($0.id) },
                         onEditing: { model.setEditing($0.id, $1) })
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
