import Foundation
import Testing
@testable import RavenIslandCore

@Suite struct AgendaTimelineTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    let midnight = Date(timeIntervalSince1970: TimeInterval(1_800_000_000 - 1_800_000_000 % 86_400 as Int))

    func at(_ h: Double) -> Date { midnight + h * 3600 }

    func ev(_ id: String, _ from: Double, _ to: Double, allDay: Bool = false, declined: Bool = false,
            cancelled: Bool = false) -> AgendaEvent {
        AgendaEvent(id: id, title: id, start: at(from), end: at(to), isAllDay: allDay, isDeclined: declined, isCancelled: cancelled)
    }

    func timeline(_ events: [AgendaEvent], now: Double = 14) -> AgendaTimeline {
        AgendaTimeline(events: events, now: at(now), calendar: calendar, minimumHeight: 0.1)
    }

    @Test func windowStartsAtHalfHour() {
        let t = timeline([], now: 14.33)
        #expect(t.start == at(14)); #expect(t.end == at(17))
        #expect(t.hourMarks == [at(14), at(15), at(16), at(17)])
        #expect(abs(t.nowOffset - 0.11) < 0.001)
        #expect(timeline([], now: 14.5).start == at(14.5))
    }

    @Test func blockPositions() {
        let t = timeline([ev("a", 15, 16)])
        #expect(t.blocks.count == 1)
        let b = t.blocks[0]
        #expect(abs(b.top - 1.0 / 3) < 1e-9); #expect(abs(b.height - 1.0 / 3) < 1e-9)
        #expect(b.column == 0); #expect(b.columns == 1)
    }

    @Test func spanningEventFillsWindow() {
        let t = timeline([ev("a", 13, 18)])
        #expect(t.blocks.first?.top == 0); #expect(t.blocks.first?.height == 1); #expect(t.later == nil)
    }

    @Test func zeroLengthEventGetsMinimumHeight() {
        #expect(timeline([ev("a", 15, 15)]).blocks.first?.height == 0.1)
        let edge = timeline([ev("b", 16.95, 17)]).blocks.first!
        #expect(edge.top + edge.height <= 1 + 1e-9)
        #expect(abs(edge.height - 0.1) < 1e-9)
    }

    @Test func twoOverlapsShareColumns() {
        let t = timeline([ev("a", 15, 16), ev("b", 15.5, 16.5)])
        #expect(t.blocks.map(\.column) == [0, 1]); #expect(t.blocks.map(\.columns) == [2, 2])
    }

    @Test func thirdOverlapDropped() {
        let t = timeline([ev("c", 15.25, 16), ev("a", 15, 16), ev("b", 15, 16)])
        #expect(Set(t.blocks.map(\.event.id)) == ["a", "b"])
    }

    @Test func shortBackToBackEventsDoNotOverlapWhenDrawn() {
        let t = timeline([ev("a", 15, 15.25), ev("b", 15.25, 16)])
        #expect(t.blocks.map(\.column) == [0, 1]); #expect(t.blocks.map(\.columns) == [2, 2])
    }

    @Test func threeShortBackToBackAllShown() {
        let events = [ev("a", 15, 15.25), ev("b", 15.25, 15.5), ev("c", 15.5, 15.75)]
        let t = AgendaTimeline(events: events, now: at(14), calendar: calendar, minimumHeight: 12.0 / 64)
        #expect(t.blocks.map(\.event.id) == ["a", "b", "c"])
    }

    @Test func laterLine() {
        #expect(timeline([ev("14", 14, 15), ev("18", 18, 19)], now: 14.5).later?.id == "18")
        #expect(timeline([ev("14", 14, 15), ev("16", 16, 16.5), ev("18", 18, 19)], now: 14.5).later == nil)
    }

    @Test func windowAcrossMidnight() {
        let t = timeline([ev("tomorrow", 24.5, 25)], now: 23.4)
        #expect(t.start == at(23)); #expect(t.hourMarks.last == at(26))
        #expect(t.blocks.isEmpty); #expect(t.later == nil)
    }

    @Test func declinedCancelledAllDayIgnored() {
        let t = timeline([ev("d", 15, 16, declined: true), ev("c", 15, 16, cancelled: true), ev("f", 0, 24, allDay: true)])
        #expect(t.blocks.isEmpty)
    }
}
