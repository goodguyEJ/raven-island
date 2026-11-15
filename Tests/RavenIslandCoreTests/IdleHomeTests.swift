import Foundation
import Testing
@testable import RavenIslandCore

@Suite struct IdleHomeTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func track(playing: Bool) -> NowPlaying {
        NowPlaying(app: .spotify, title: "S", artist: "", album: "", isPlaying: playing, duration: nil, position: 0, asOf: now, trackID: nil)
    }

    @Test func noneShowsNothing() {
        #expect(!IdleHome.none.showsPanel)
        #expect(!IdleHome.none.showsAgendaHalf)
        #expect(!IdleHome.none.hasCollapsedContent)
    }

    @Test func trackOnly() {
        let h = IdleHome(nowPlaying: track(playing: false), showMusic: true, agenda: [], collapsedLabel: nil, agendaOn: false)
        #expect(h.showsPanel); #expect(h.hasCollapsedContent)
        #expect(!h.showsAgendaHalf); #expect(!h.isPlaying)
    }

    @Test func musicSwitchedOffHidesTrack() {
        let h = IdleHome(nowPlaying: track(playing: true), showMusic: false, agenda: [], collapsedLabel: nil, agendaOn: false)
        #expect(h == .none)
    }

    @Test func agendaGrantedButEmptyIsNotContent() {
        let h = IdleHome(nowPlaying: nil, showMusic: true, agenda: [], collapsedLabel: nil, agendaOn: true)
        #expect(!h.showsPanel)
    }

    @Test func agendaGrantedEmptyWithTrackShowsHalf() {
        let h = IdleHome(nowPlaying: track(playing: true), showMusic: true, agenda: [], collapsedLabel: nil, agendaOn: true)
        #expect(h.showsAgendaHalf); #expect(h.agendaRows == 0)
    }

    @Test func agendaOffIgnoresEvents() {
        let e = AgendaEvent(id: "a", title: "A", start: now, end: now + 600)
        let h = IdleHome(nowPlaying: nil, showMusic: true, agenda: [e], collapsedLabel: "10:30", agendaOn: false)
        #expect(h.agendaRows == 0); #expect(h.collapsedLabel == nil)
    }

    @Test func artworkPolicy() {
        #expect(ArtworkPolicy.allows(URL(string: "https://i.scdn.co/image/ab67616d0000b273abc")!))
        for refused in ["http://i.scdn.co/image/x", "https://i.scdn.co.example.com/x", "https://example.com/i.scdn.co",
                        "https://i.scdn.co:8443/x", "https://user:pw@i.scdn.co/x", "https://I.SCDN.CO.evil/x", "file:///tmp/x"] {
            #expect(!ArtworkPolicy.allows(URL(string: refused)!), "\(refused)")
        }
    }
}
