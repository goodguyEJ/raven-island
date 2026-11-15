import Foundation

/// The music players the idle home listens to.
public enum MusicApp: String, Sendable, CaseIterable {
    case spotify, appleMusic

    public var bundleID: String {
        switch self {
        case .spotify: return "com.spotify.client"
        case .appleMusic: return "com.apple.Music"
        }
    }

    /// The distributed notification the player posts on every play, pause, and track change.
    public var notificationName: String {
        switch self {
        case .spotify: return "com.spotify.client.PlaybackStateChanged"
        case .appleMusic: return "com.apple.Music.playerInfo"
        }
    }

    public var displayName: String {
        switch self {
        case .spotify: return "Spotify"
        case .appleMusic: return "Music"
        }
    }

    public var durationKey: String { self == .spotify ? "Duration" : "Total Time" }
    public var trackIDKey: String { self == .spotify ? "Track ID" : "PersistentID" }
}

/// What one player is playing. Built from a notification payload that any local process can post,
/// so every field is treated as untrusted.
public struct NowPlaying: Equatable, Sendable {
    public var app: MusicApp
    public var title: String
    public var artist: String
    public var album: String
    public var isPlaying: Bool
    /// Seconds; nil when missing or not positive (ads, some podcasts).
    public var duration: TimeInterval?
    /// Seconds into the track at `asOf`.
    public var position: TimeInterval
    public var asOf: Date
    public var trackID: String?

    public static let maxTextLength = 200

    public init(app: MusicApp, title: String, artist: String, album: String, isPlaying: Bool,
                duration: TimeInterval?, position: TimeInterval, asOf: Date, trackID: String?) {
        self.app = app
        self.title = title
        self.artist = artist
        self.album = album
        self.isPlaying = isPlaying
        self.duration = duration
        self.position = position
        self.asOf = asOf
        self.trackID = trackID
    }

    /// Nil when the payload says stopped, or has no usable title.
    public init?(app: MusicApp, userInfo: [String: Any], now: Date) {
        guard let state = userInfo["Player State"] as? String, state == "Playing" || state == "Paused",
              let title = Self.text(userInfo["Name"]), !title.isEmpty else { return nil }
        let milliseconds = Self.number(userInfo[app.durationKey]) ?? 0
        let id: String?
        if let s = userInfo[app.trackIDKey] as? String { id = String(s.prefix(Self.maxTextLength)) }
        else if let n = userInfo[app.trackIDKey] as? NSNumber { id = n.stringValue }
        else { id = nil }
        self.init(app: app, title: title, artist: Self.text(userInfo["Artist"]) ?? "",
                  album: Self.text(userInfo["Album"]) ?? "", isPlaying: state == "Playing",
                  duration: milliseconds > 0 ? milliseconds / 1000 : nil,
                  position: max(0, Self.number(userInfo["Playback Position"]) ?? 0), asOf: now, trackID: id)
    }

    private static func text(_ value: Any?) -> String? {
        guard let s = value as? String else { return nil }
        return String(s.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxTextLength))
    }

    private static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber else { return nil }
        let d = n.doubleValue
        return d.isFinite ? d : nil
    }

    /// Advances only while playing; clamped to the track.
    public func position(at date: Date) -> TimeInterval {
        let p = isPlaying ? position + date.timeIntervalSince(asOf) : position
        return min(max(0, p), duration ?? .infinity)
    }

    /// 0...1, or nil without a duration.
    public func progress(at date: Date) -> Double? {
        guard let duration, duration > 0 else { return nil }
        return position(at: date) / duration
    }
}

/// The latest state of each player, and which one the idle home shows.
public struct NowPlayingBoard: Equatable, Sendable {
    private var players: [MusicApp: NowPlaying] = [:]

    public init() {}

    /// Nil means that player stopped. `positionReported: false` (Music's payload has no position) keeps
    /// the position running from the previous update of the same track, so a pause does not reset it.
    public mutating func update(_ app: MusicApp, _ value: NowPlaying?, positionReported: Bool = true) {
        var value = value
        if !positionReported, let new = value, let old = players[app], old.trackID != nil, old.trackID == new.trackID {
            value?.position = old.position(at: new.asOf)
        }
        players[app] = value
    }

    /// The player quit.
    public mutating func remove(_ app: MusicApp) { players[app] = nil }

    /// A playing track beats a paused one; among equals the latest `asOf` wins.
    public var current: NowPlaying? {
        players.values.max { a, b in
            a.isPlaying != b.isPlaying ? !a.isPlaying : a.asOf < b.asOf
        }
    }
}
