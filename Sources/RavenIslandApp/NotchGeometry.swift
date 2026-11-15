import AppKit
import RavenIslandCore

/// Where the panel sits and how big it is, derived from the screen it lives on.
struct NotchGeometry: Equatable {
    var hasNotch: Bool
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    /// Gap between the top of the screen and the top of the panel (0 when hugging a notch).
    var topOffset: CGFloat
    var screenFrame: CGRect
    /// With no sessions, show a couple of characters strolling in the collapsed panel.
    var idleStroll = false
    /// With no sessions, the expanded panel shows the flock instead of a plain message.
    var crewStage = false
    /// With no sessions, what is playing and what is next on the calendar.
    var idleHome = IdleHome.none

    static let wing: CGFloat = 38
    static let expandedWidth: CGFloat = 600
    static let rowHeight: CGFloat = 54
    /// Rows per page of the session list; more sessions go on further pages.
    static let maxRows = 5
    static let pagerHeight: CGFloat = 28
    static let pillHeight: CGFloat = 26
    static let idleHomeHeight: CGFloat = 96

    static func forScreen(_ screen: NSScreen) -> NotchGeometry {
        let top = screen.safeAreaInsets.top
        if top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return NotchGeometry(hasNotch: true, notchWidth: screen.frame.width - left.width - right.width,
                                 notchHeight: top, topOffset: 0, screenFrame: screen.frame)
        }
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        return NotchGeometry(hasNotch: false, notchWidth: 0, notchHeight: 0,
                             topOffset: menuBar + 6, screenFrame: screen.frame)
    }

    /// The built-in notched display if there is one, otherwise the main screen.
    static func preferredScreen(mode: String = "auto") -> NSScreen? {
        // screens[0] is always the display that holds the menu bar.
        if mode == "primary" { return NSScreen.screens.first }
        return NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first
    }

    var headerHeight: CGFloat { hasNotch ? notchHeight : 30 }

    /// Radius of the outward curves where the panel meets the top of the screen. Only when the
    /// panel hangs from the notch; the floating pill on other displays has ordinary corners.
    /// None around a bare notch, where nothing shows beside it.
    func earRadius(expanded: Bool, sessionCount: Int) -> CGFloat {
        guard hasNotch, expanded || sessionCount > 0 || idleStroll || idleHome.hasCollapsedContent else { return 0 }
        return expanded ? 14 : 7
    }

    var headerSideWidth: CGFloat { (Self.expandedWidth - notchWidth) / 2 - 22 }

    func collapsedSize(sessionCount: Int) -> CGSize {
        if hasNotch {
            let body = notchWidth + (sessionCount > 0 || idleStroll || idleHome.hasCollapsedContent ? 2 * Self.wing : 0)
            return CGSize(width: body + 2 * earRadius(expanded: false, sessionCount: sessionCount), height: notchHeight)
        }
        return CGSize(width: sessionCount > 0 ? 178 : (idleStroll || idleHome.hasCollapsedContent ? 96 : 44), height: Self.pillHeight)
    }

    /// With a request card showing, the session list is kept short so the panel stays compact.
    static func visibleRows(sessionCount: Int, hasCard: Bool) -> Int {
        max(1, min(sessionCount, hasCard ? 3 : maxRows))
    }

    /// `focus`: a decision is waiting and only its session is shown, with a "Show all" line under it.
    /// `queued`: decisions waiting behind the one on screen; they get an "Up next" line.
    func expandedSize(sessionCount: Int, cardHeight: CGFloat = 0, focus: Bool = false, queued: Int = 0) -> CGSize {
        let width = max(Self.expandedWidth, notchWidth + 2 * Self.wing + 80) + 2 * earRadius(expanded: true, sessionCount: sessionCount)
        let list: CGFloat
        if focus {
            list = Self.rowHeight + (sessionCount > 1 ? Self.pagerHeight : 0)
        } else if sessionCount == 0 {
            list = idleHome.showsPanel && cardHeight == 0 ? Self.idleHomeHeight : (crewStage ? CrewStage.height : Self.rowHeight)
        } else {
            let rows = Self.visibleRows(sessionCount: sessionCount, hasCard: cardHeight > 0)
            // With a card up there is always a footer line, for "Show less".
            let footer = sessionCount > rows || (cardHeight > 0 && sessionCount > 1)
            list = CGFloat(rows) * Self.rowHeight + (footer ? Self.pagerHeight : 0)
        }
        let upNext = cardHeight > 0 && queued > 0 ? Self.pagerHeight : 0
        return CGSize(width: width, height: headerHeight + cardHeight + upNext + list + 10)
    }

    func frame(for size: CGSize) -> CGRect {
        CGRect(x: (screenFrame.midX - size.width / 2).rounded(),
               y: screenFrame.maxY - topOffset - size.height,
               width: size.width, height: size.height)
    }
}
