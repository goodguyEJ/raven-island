import Foundation
import Testing
@testable import RavenIslandCore

@Suite struct NowPlayingTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func parsesSpotify() {
        let n = NowPlaying(app: .spotify, userInfo: ["Player State": "Playing", "Name": "Song", "Artist": "Band",
            "Album": "LP", "Duration": 215_000, "Playback Position": 12.5, "Track ID": "spotify:track:abc"], now: now)
        #expect(n == NowPlaying(app: .spotify, title: "Song", artist: "Band", album: "LP", isPlaying: true,
                                duration: 215, position: 12.5, asOf: now, trackID: "spotify:track:abc"))
    }

    @Test func parsesAppleMusicPaused() {
        let n = NowPlaying(app: .appleMusic, userInfo: ["Player State": "Paused", "Name": "Tune", "Artist": "Solo",
            "Total Time": NSNumber(value: 180_000), "PersistentID": NSNumber(value: 42)], now: now)
        #expect(n?.isPlaying == false); #expect(n?.duration == 180); #expect(n?.position == 0)
        #expect(n?.album == ""); #expect(n?.trackID == "42")
    }

    @Test func stoppedOrUntitledIsNil() {
        #expect(NowPlaying(app: .spotify, userInfo: ["Player State": "Stopped", "Name": "Song"], now: now) == nil)
        #expect(NowPlaying(app: .spotify, userInfo: ["Player State": "Playing"], now: now) == nil)
        #expect(NowPlaying(app: .spotify, userInfo: ["Player State": "Playing", "Name": "   "], now: now) == nil)
        #expect(NowPlaying(app: .spotify, userInfo: ["Player State": 7, "Name": ["x"]], now: now) == nil)
        #expect(NowPlaying(app: .spotify, userInfo: [:], now: now) == nil)
    }

    @Test func capsLongText() {
        let n = NowPlaying(app: .spotify, userInfo: ["Player State": "Playing", "Name": String(repeating: "a", count: 10_000),
            "Artist": String(repeating: "b", count: 10_000)], now: now)
        #expect(n?.title.count == 200); #expect(n?.artist.count == 200)
    }

    @Test func controlCharactersAreVisiblyMarked() {
        let n = NowPlaying(app: .spotify, userInfo: ["Player State": "Playing", "Name": "Evil\u{202E}txt.exe\u{0007}"], now: now)
        let shown = TextSafety.visible(n!.title)
        #expect(!shown.contains("\u{202E}")); #expect(!shown.contains("\u{0007}"))
    }

    @Test func positionCarriesOverWhenPayloadHasNone() {
        var board = NowPlayingBoard()
        board.update(.appleMusic, NowPlaying(app: .appleMusic, title: "T", artist: "", album: "", isPlaying: true,
                                             duration: 300, position: 100, asOf: now, trackID: "42"))
        let paused = NowPlaying(app: .appleMusic, title: "T", artist: "", album: "", isPlaying: false,
                                duration: 300, position: 0, asOf: now + 20, trackID: "42")
        board.update(.appleMusic, paused, positionReported: false)
        #expect(board.current?.position == 120)
        let next = NowPlaying(app: .appleMusic, title: "U", artist: "", album: "", isPlaying: true,
                              duration: 200, position: 0, asOf: now + 30, trackID: "43")
        board.update(.appleMusic, next, positionReported: false)
        #expect(board.current?.position == 0)
    }

    @Test func zeroDurationHasNoProgress() {
        let n = NowPlaying(app: .spotify, userInfo: ["Player State": "Playing", "Name": "Ad", "Duration": 0], now: now)
        #expect(n?.duration == nil); #expect(n?.progress(at: now + 30) == nil)
    }

    @Test func positionAdvancesOnlyWhilePlayingAndClamps() {
        var n = NowPlaying(app: .spotify, title: "S", artist: "", album: "", isPlaying: true, duration: 100, position: 90, asOf: now, trackID: nil)
        #expect(n.position(at: now + 5) == 95); #expect(n.position(at: now + 60) == 100)
        #expect(n.position(at: now - 500) == 0); #expect(n.progress(at: now + 5) == 0.95)
        n.isPlaying = false
        #expect(n.position(at: now + 60) == 90)
    }

    @Test func boardPrefersPlayingThenLatest() {
        func track(_ app: MusicApp, playing: Bool, at offset: TimeInterval) -> NowPlaying {
            NowPlaying(app: app, title: app.rawValue, artist: "", album: "", isPlaying: playing, duration: nil, position: 0, asOf: now + offset, trackID: nil)
        }
        var board = NowPlayingBoard()
        #expect(board.current == nil)
        board.update(.spotify, track(.spotify, playing: false, at: 10))
        board.update(.appleMusic, track(.appleMusic, playing: true, at: 0))
        #expect(board.current?.app == .appleMusic)
        board.update(.spotify, track(.spotify, playing: true, at: 20))
        #expect(board.current?.app == .spotify)
        board.remove(.spotify)
        #expect(board.current?.app == .appleMusic)
        board.update(.appleMusic, nil)
        #expect(board.current == nil)
    }
}
