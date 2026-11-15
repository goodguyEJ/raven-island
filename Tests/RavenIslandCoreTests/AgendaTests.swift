import Foundation
import Testing
@testable import RavenIslandCore

@Suite struct AgendaTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "en_GB")
        return c
    }()
    let locale = Locale(identifier: "en_GB")
    let midnight = Date(timeIntervalSince1970: TimeInterval(1_800_000_000 - 1_800_000_000 % 86_400 as Int))

    func at(_ h: Double) -> Date { midnight + h * 3600 }

    func ev(_ id: String, _ from: Double, _ to: Double, allDay: Bool = false, declined: Bool = false,
            cancelled: Bool = false) -> AgendaEvent {
        AgendaEvent(id: id, title: id, start: at(from), end: at(to), isAllDay: allDay, isDeclined: declined, isCancelled: cancelled)
    }

    func ids(_ events: [AgendaEvent], now: Date) -> [String] {
        Agenda.remainingToday(events, now: now, calendar: calendar).map(\.id)
    }

    @Test func selectsRemainingTimedEvents() {
        let events = [ev("e", 17, 18), ev("a", 8, 9), ev("c", 13, 14), ev("b", 10, 11), ev("d", 15, 16),
                      ev("f", 0, 24, allDay: true), ev("g", 12, 13, declined: true), ev("h", 12, 13, cancelled: true)]
        #expect(ids(events, now: at(9.5)) == ["b", "c", "d"])
    }

    @Test func runningEventIsIncludedAndEndedIsNot() {
        #expect(ids([ev("a", 9, 10)], now: at(9.5)) == ["a"])
        #expect(ids([ev("a", 9, 10)], now: at(10)) == [])
    }

    @Test func startedYesterdayStillRunning() {
        let events = [ev("y", -2, 1)]
        #expect(ids(events, now: at(0.5)) == ["y"])
        #expect(Agenda.collapsedLabel(events, now: at(0.5), calendar: calendar, locale: locale) == "now")
    }

    @Test func crossesMidnightListedToday() {
        #expect(ids([ev("late", 23, 25)], now: at(20)) == ["late"])
        #expect(ids([ev("tomorrow", 24.5, 26)], now: at(20)) == [])
    }

    @Test func collapsedLabelWindow() {
        let events = [ev("b", 10.5, 11)]
        func label(_ h: Double) -> String? { Agenda.collapsedLabel(events, now: at(h), calendar: calendar, locale: locale) }
        #expect(label(9) == nil)
        #expect(label(9.5) == "10:30")
        #expect(label(10.75) == "now")
        #expect(label(11) == nil)
        let us = Agenda.collapsedLabel([ev("p", 15.5, 16)], now: at(15), calendar: calendar, locale: Locale(identifier: "en_US"))
        #expect(us == "3:30")
    }

    @Test func timeLabelFollowsLocale() {
        #expect(Agenda.timeLabel(at(15.5), calendar: calendar, locale: Locale(identifier: "en_GB")) == "15:30")
        let us = Agenda.timeLabel(at(15.5), calendar: calendar, locale: Locale(identifier: "en_US"))
        #expect(us.contains("3:30")); #expect(us.contains("PM"))
    }

    @Test func nextBoundary() {
        let events = [ev("b", 10.5, 11)]
        #expect(Agenda.nextBoundary(events, now: at(8), calendar: calendar) == at(9.5))
        #expect(Agenda.nextBoundary(events, now: at(9.5), calendar: calendar) == at(10.5))
        #expect(Agenda.nextBoundary(events, now: at(10.5), calendar: calendar) == at(11))
        #expect(Agenda.nextBoundary(events, now: at(11), calendar: calendar) == at(24))
        #expect(Agenda.nextBoundary([], now: at(8), calendar: calendar) == at(24))
    }

    @Test func capsTitle() {
        let e = AgendaEvent(id: "x", title: String(repeating: "t", count: 10_000), start: at(9), end: at(10))
        #expect(e.title.count == 200)
    }
}
