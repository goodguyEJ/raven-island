import AppKit
import SwiftUI
import Combine
import RavenIslandCore

/// Borderless panel that never takes keyboard focus and may sit over the menu bar.
final class NotchPanel: NSPanel {
    // Key only when a text field is clicked (becomesKeyOnlyIfNeeded), so typing a note works
    // without the panel ever taking focus on its own.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Lets the first click on a button count even though the panel isn't the key window.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Reports hover even while another app is active (SwiftUI's onHover is unreliable in inactive panels).
final class HoverView: NSView {
    var onHover: ((Bool) -> Void)?
    private var area: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(a)
        area = a
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

@MainActor
final class NotchController {
    private let model: AppModel
    private let settings: Settings
    private let music: MusicSource
    private let calendar: CalendarSource
    private let state: NotchState
    private let panel: NotchPanel
    private var subscriptions = Set<AnyCancellable>()

    private var hovering = false
    private var shrinkPending = false
    private var lastAttention = 0
    private var sessionCount = 0
    private var cardHeight: CGFloat = 0
    private var frontRequestID: String?
    private var queuedCount = 0
    private var hasPending: Bool { cardHeight > 0 }
    private var collapseWork: DispatchWorkItem?
    private var shrinkWork: DispatchWorkItem?
    private var resizeWork: DispatchWorkItem?
    private var resizeTarget = CGRect.zero
    /// After the gear closes the panel under the pointer, hover stays off until the pointer leaves.
    private var suppressHover = false

    var onSelect: (Session) -> Void = { _ in }
    /// A rect asks for Settings to open below the panel, which a waiting decision keeps open.
    var onOpenSettings: (CGRect?) -> Void = { _ in }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private var spring: Animation? { reduceMotion ? nil : Motion.panel }
    private var settle: TimeInterval { reduceMotion ? 0 : Motion.panelSettle }

    init(model: AppModel, settings: Settings, music: MusicSource, calendar: CalendarSource) {
        self.model = model
        self.settings = settings
        self.music = music
        self.calendar = calendar
        let screen = NotchGeometry.preferredScreen(mode: settings.displayMode)
        var geometry = screen.map(NotchGeometry.forScreen)
            ?? NotchGeometry(hasNotch: false, notchWidth: 0, notchHeight: 0, topOffset: 30,
                             screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        geometry.crewStage = settings.showCharacters
        geometry.idleStroll = settings.showCharacters && settings.strollWhenIdle
        geometry.idleHome = IdleHome(nowPlaying: music.nowPlaying, showMusic: settings.showMusic, agenda: calendar.events,
                                     collapsedLabel: calendar.collapsedLabel,
                                     agendaOn: settings.showCalendar && calendar.access == .granted,
                                     weekHasEvents: AgendaWeek(now: Date(), calendar: .current)
                                        .hasEvents(calendar.week, now: Date(), calendar: .current))
        state = NotchState(geometry: geometry)

        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isFloatingPanel = true
        // Set after isFloatingPanel, which resets the level. Must be above the menu bar to cover the notch area.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let root = NotchRootView(model: model, state: state, settings: settings, music: music, calendar: calendar,
                                 onSelect: { [weak self] s in
            self?.onSelect(s)
        }, onOpenSettings: { [weak self] in self?.openSettingsFromPanel() }, onOpenCalendar: {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
        })
        let hosting = FirstMouseHostingView(rootView: root)
        hosting.autoresizingMask = [.width, .height]
        let container = HoverView(frame: .zero)
        hosting.frame = container.bounds
        container.addSubview(hosting)
        container.onHover = { [weak self] inside in self?.hoverChanged(inside) }
        panel.contentView = container

        model.$sessions.receive(on: RunLoop.main).sink { [weak self] in self?.sessionsChanged($0) }
            .store(in: &subscriptions)
        model.$pending.receive(on: RunLoop.main).sink { [weak self] in self?.pendingChanged($0) }
            .store(in: &subscriptions)
        // The panel shows prompts, commands, and file contents; by default it is invisible to screen capture.
        settings.$hideFromScreenSharing.receive(on: RunLoop.main).sink { [weak self] hide in
            self?.panel.sharingType = hide ? .none : .readOnly
        }.store(in: &subscriptions)
        // Turning characters or strolling on or off changes the panel's shape.
        settings.$showCharacters.combineLatest(settings.$strollWhenIdle).dropFirst()
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.screensChanged() }
            .store(in: &subscriptions)
        settings.$displayMode.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.screensChanged() }
            .store(in: &subscriptions)
        // "Show all" and "Show less" change the panel's height.
        state.$showAll.dropFirst().removeDuplicates().receive(on: RunLoop.main)
            .sink { [weak self] showAll in
                guard let self else { return }
                self.resizeWindow()
            }
            .store(in: &subscriptions)
        // Delivered on the next pass of the run loop, after the published values have changed.
        music.objectWillChange.merge(with: calendar.objectWillChange, settings.objectWillChange)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.idleHomeChanged() }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.screensChanged() }
            .store(in: &subscriptions)

        applyFrame()
        panel.orderFrontRegardless()
    }

    private func screensChanged() {
        guard let screen = NotchGeometry.preferredScreen(mode: settings.displayMode) else { return }
        var geometry = NotchGeometry.forScreen(screen)
        geometry.crewStage = settings.showCharacters
        geometry.idleStroll = settings.showCharacters && settings.strollWhenIdle
        geometry.idleHome = idleHome()
        state.geometry = geometry
        applyFrame()
    }

    private func idleHome() -> IdleHome {
        IdleHome(nowPlaying: music.nowPlaying, showMusic: settings.showMusic, agenda: calendar.events,
                 collapsedLabel: calendar.collapsedLabel, agendaOn: settings.showCalendar && calendar.access == .granted,
                 weekHasEvents: AgendaWeek(now: Date(), calendar: .current).hasEvents(calendar.week, now: Date(), calendar: .current))
    }

    /// Never opens the panel: a track change or an upcoming event only reshapes what is already there.
    private func idleHomeChanged() {
        let idle = idleHome()
        guard idle != state.geometry.idleHome else { return }
        state.geometry.idleHome = idle
        // With sessions or a decision showing, the idle home is not on screen; leave the frame alone.
        guard sessionCount == 0, !hasPending else { return }
        resizeWindow()
    }

    /// Growing: make room at once. Shrinking while open: let the shape finish animating, or its
    /// bottom is cut off. A further shrink before then restarts the wait.
    private func resizeWindow() {
        let target = state.geometry.frame(for: currentSize())
        guard state.expanded, target.height < panel.frame.height else {
            resizeWork?.cancel()
            resizeWork = nil
            applyFrame()
            return
        }
        if resizeWork != nil, target == resizeTarget { return }
        resizeWork?.cancel()
        resizeTarget = target
        let work = DispatchWorkItem { [weak self] in
            self?.resizeWork = nil
            self?.applyFrame()
        }
        resizeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settle, execute: work)
    }

    private func currentSize() -> CGSize {
        let g = state.geometry
        return (state.expanded || shrinkPending) ? g.expandedSize(sessionCount: sessionCount, cardHeight: cardHeight, focus: hasPending && !state.showAll, queued: queuedCount)
                                                 : g.collapsedSize(sessionCount: sessionCount)
    }

    private func sessionsChanged(_ sessions: [Session]) {
        sessionCount = sessions.count
        let attention = sessions.filter { $0.state.needsAttention }.count
        resizeWindow()
        if attention > lastAttention, settings.autoExpand {
            // Something new needs the user: open up, then tuck away again unless they're looking at it.
            expand()
            if !hovering { scheduleCollapse(after: 6) }
        }
        lastAttention = attention
    }

    /// A waiting request pins the panel open; once the queue empties it tucks away again.
    private func pendingChanged(_ pending: [PendingRequest]) {
        // Each new decision starts focused on its own session.
        if pending.first?.id != frontRequestID {
            frontRequestID = pending.first?.id
            state.showAll = false
        }
        cardHeight = pending.first.map(RequestCard.height(for:)) ?? 0
        queuedCount = max(0, pending.count - 1)
        if hasPending {
            expand()
            resizeWindow()
        } else {
            resizeWindow()
            if !hovering { scheduleCollapse(after: 0.8) }
        }
    }

    /// The window is exactly the size of the shape, so everything outside it stays clickable.
    /// While a collapse animation is running the window keeps the expanded size.
    private func applyFrame() {
        let frame = state.geometry.frame(for: currentSize())
        if frame != panel.frame { panel.setFrame(frame, display: true) }
    }

    private func openSettingsFromPanel() {
        if hasPending {
            onOpenSettings(panel.frame)
            return
        }
        hovering = false
        suppressHover = true
        collapse()
        onOpenSettings(nil)
    }

    private func hoverChanged(_ inside: Bool) {
        if suppressHover {
            if !inside { suppressHover = false }
            return
        }
        hovering = inside
        if inside {
            collapseWork?.cancel()
            expand()
        } else {
            scheduleCollapse(after: 0.35)
        }
    }

    private func expand() {
        collapseWork?.cancel()
        shrinkWork?.cancel()
        shrinkPending = false
        guard !state.expanded else { return }
        // Grow the window first so the animation has room, then animate the shape inside it.
        panel.setFrame(state.geometry.frame(for: state.geometry.expandedSize(sessionCount: sessionCount, cardHeight: cardHeight, focus: hasPending && !state.showAll, queued: queuedCount)), display: true)
        withAnimation(spring) { state.expanded = true }
    }

    private func scheduleCollapse(after delay: TimeInterval) {
        collapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.collapse() }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func collapse() {
        guard state.expanded, !hovering, !hasPending else { return }
        shrinkPending = true
        withAnimation(spring) { state.expanded = false }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.state.expanded else { return }
            self.shrinkPending = false
            self.applyFrame()
            // The window shrank out from under the pointer, so no exit may ever arrive.
            if self.suppressHover, !self.panel.frame.contains(NSEvent.mouseLocation) { self.suppressHover = false }
        }
        shrinkWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settle, execute: work)
    }
}
