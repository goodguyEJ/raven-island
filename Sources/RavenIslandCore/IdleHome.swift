import Foundation

/// What the idle home has to show. Geometry and views both read this, so the window size and
/// the content cannot disagree.
public struct IdleHome: Equatable, Sendable {
    /// A track is known, playing or paused.
    public var hasTrack: Bool
    public var isPlaying: Bool
    /// The calendar is switched on and access is granted.
    public var agendaOn: Bool
    public var agendaRows: Int
    public var collapsedLabel: String?
    /// Any of the week strip's six days has an event, so the calendar side is worth opening for.
    public var weekHasEvents: Bool

    public static let none = IdleHome(hasTrack: false, isPlaying: false, agendaOn: false, agendaRows: 0, collapsedLabel: nil,
                                      weekHasEvents: false)

    private init(hasTrack: Bool, isPlaying: Bool, agendaOn: Bool, agendaRows: Int, collapsedLabel: String?, weekHasEvents: Bool) {
        self.hasTrack = hasTrack
        self.isPlaying = isPlaying
        self.agendaOn = agendaOn
        self.agendaRows = agendaRows
        self.collapsedLabel = collapsedLabel
        self.weekHasEvents = weekHasEvents
    }

    public init(nowPlaying: NowPlaying?, showMusic: Bool, agenda: [AgendaEvent], collapsedLabel: String?, agendaOn: Bool,
                weekHasEvents: Bool = false) {
        let track = showMusic ? nowPlaying : nil
        self.init(hasTrack: track != nil, isPlaying: track?.isPlaying ?? false, agendaOn: agendaOn,
                  agendaRows: agendaOn ? agenda.count : 0, collapsedLabel: agendaOn ? collapsedLabel : nil,
                  weekHasEvents: agendaOn && weekHasEvents)
    }

    /// Permission and empty states never count as content.
    public var showsPanel: Bool { hasTrack || agendaRows > 0 || weekHasEvents }
    public var showsAgendaHalf: Bool { showsPanel && agendaOn }
    public var hasCollapsedContent: Bool { hasTrack || collapsedLabel != nil }
}

/// The one network request the app makes: Spotify album art, and only from Spotify's image host.
public enum ArtworkPolicy {
    public static let maxBytes = 2_000_000
    public static let host = "i.scdn.co"

    public static func allows(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == host && url.port == nil && url.user == nil && url.password == nil
    }
}
