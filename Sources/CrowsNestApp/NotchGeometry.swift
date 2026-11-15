import AppKit

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
    /// With no sessions, the expanded panel shows the crew instead of a plain message.
    var crewStage = false

    static let wing: CGFloat = 38
    static let expandedWidth: CGFloat = 520
    static let rowHeight: CGFloat = 54
    /// Rows per page of the session list; more sessions go on further pages.
    static let maxRows = 5
    static let pagerHeight: CGFloat = 28
    static let pillHeight: CGFloat = 26

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

    func collapsedSize(sessionCount: Int) -> CGSize {
        if hasNotch {
            return CGSize(width: notchWidth + (sessionCount > 0 || idleStroll ? 2 * Self.wing : 0), height: notchHeight)
        }
        return CGSize(width: sessionCount > 0 ? 178 : (idleStroll ? 96 : 44), height: Self.pillHeight)
    }

    /// With a request card showing, the session list is kept short so the panel stays compact.
    static func visibleRows(sessionCount: Int, hasCard: Bool) -> Int {
        max(1, min(sessionCount, hasCard ? 3 : maxRows))
    }

    func expandedSize(sessionCount: Int, cardHeight: CGFloat = 0, footerHeight: CGFloat = 0) -> CGSize {
        let rows = Self.visibleRows(sessionCount: sessionCount, hasCard: cardHeight > 0)
        let width = max(Self.expandedWidth, notchWidth + 2 * Self.wing + 80)
        let pager = sessionCount > rows ? Self.pagerHeight : 0
        let list = sessionCount == 0 && crewStage ? CrewStage.height : CGFloat(rows) * Self.rowHeight + pager
        return CGSize(width: width, height: headerHeight + cardHeight + list + footerHeight + 10)
    }

    func frame(for size: CGSize) -> CGRect {
        CGRect(x: (screenFrame.midX - size.width / 2).rounded(),
               y: screenFrame.maxY - topOffset - size.height,
               width: size.width, height: size.height)
    }
}
