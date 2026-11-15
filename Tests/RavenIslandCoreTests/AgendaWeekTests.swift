import Foundation
import Testing
@testable import RavenIslandCore

@Suite struct AgendaWeekTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    func date(_ month: Int, _ day: Int, _ hour: Double = 0, year: Int = 2026) -> Date {
        let midnight = calendar.date(from: DateComponents(year: year, month: month, day: day))!
        return midnight + hour * 3600
    }

    func ev(_ id: String, _ from: Date, _ to: Date, allDay: Bool = false, declined: Bool = false,
            cancelled: Bool = false) -> AgendaEvent {
        AgendaEvent(id: id, title: id, start: from, end: to, isAllDay: allDay, isDeclined: declined, isCancelled: cancelled)
    }

    @Test func sixDaysAroundToday() {
        let week = AgendaWeek(now: date(11, 15, 14), calendar: calendar)
        #expect(week.days == (13...18).map { date(11, $0) })
        #expect(week.today == date(11, 15))
        #expect(week.start == date(11, 13)); #expect(week.end == date(11, 19))
    }

    @Test func windowCrossesYear() {
        let week = AgendaWeek(now: date(12, 30, 10), calendar: calendar)
        #expect(week.days == [date(12, 28), date(12, 29), date(12, 30), date(12, 31),
                              date(1, 1, year: 2027), date(1, 2, year: 2027)])
    }

    @Test func overnightEventOnBothDays() {
        let now = date(11, 15, 14)
        let week = AgendaWeek(now: now, calendar: calendar)
        let e = ev("late", date(11, 16, 23), date(11, 17, 1))
        #expect(week.events(on: date(11, 16), from: [e], now: now, calendar: calendar).map(\.id) == ["late"])
        #expect(week.events(on: date(11, 17), from: [e], now: now, calendar: calendar).map(\.id) == ["late"])
    }

    @Test func todayDropsEndedOtherDaysKeepThem() {
        let now = date(11, 15, 14)
        let week = AgendaWeek(now: now, calendar: calendar)
        let events = [ev("ended", date(11, 15, 9), date(11, 15, 10)), ev("yesterday", date(11, 14, 9), date(11, 14, 10))]
        #expect(week.events(on: date(11, 15), from: events, now: now, calendar: calendar).isEmpty)
        #expect(week.events(on: date(11, 14), from: events, now: now, calendar: calendar).map(\.id) == ["yesterday"])
    }

    @Test func filtersAndSorts() {
        let now = date(11, 15, 8)
        let week = AgendaWeek(now: now, calendar: calendar)
        let events = [ev("b", date(11, 15, 13), date(11, 15, 14)), ev("a", date(11, 15, 9), date(11, 15, 10)),
                      ev("allday", date(11, 15), date(11, 16), allDay: true),
                      ev("declined", date(11, 15, 11), date(11, 15, 12), declined: true),
                      ev("cancelled", date(11, 15, 11), date(11, 15, 12), cancelled: true)]
        #expect(week.events(on: date(11, 15), from: events, now: now, calendar: calendar).map(\.id) == ["a", "b"])
    }

    @Test func endIsNextMidnightAcrossDST() {
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = TimeZone(identifier: "America/New_York")!
        // Clocks fall back on Sunday 1 Nov 2026, the last day of this strip.
        let now = ny.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 12))!
        let week = AgendaWeek(now: now, calendar: ny)
        #expect(week.end == ny.date(from: DateComponents(year: 2026, month: 11, day: 2))!)
    }

    @Test func hasEvents() {
        let now = date(11, 15, 14)
        let week = AgendaWeek(now: now, calendar: calendar)
        #expect(!week.hasEvents([], now: now, calendar: calendar))
        #expect(week.hasEvents([ev("x", date(11, 18, 9), date(11, 18, 10))], now: now, calendar: calendar))
        #expect(!week.hasEvents([ev("y", date(11, 19, 9), date(11, 19, 10))], now: now, calendar: calendar))
    }
}
