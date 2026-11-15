import Foundation

/// One calendar event, reduced to what the idle home needs.
public struct AgendaEvent: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var isDeclined: Bool
    public var isCancelled: Bool
    /// The calendar's colour as 0xRRGGBB; nil uses the default accent.
    public var color: UInt32?

    public init(id: String, title: String, start: Date, end: Date,
                isAllDay: Bool = false, isDeclined: Bool = false, isCancelled: Bool = false, color: UInt32? = nil) {
        self.id = id
        self.title = String(title.prefix(NowPlaying.maxTextLength))
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.isDeclined = isDeclined
        self.isCancelled = isCancelled
        self.color = color
    }

    public func isRunning(at now: Date) -> Bool { start <= now && now < end }
}

/// Which of today's events to show, and how to label them.
public enum Agenda {
    public static let maxRows = 3
    public static let collapsedLookAhead: TimeInterval = 3600

    static func midnightAfter(_ now: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
    }

    static func qualifying(_ events: [AgendaEvent], now: Date, calendar: Calendar) -> [AgendaEvent] {
        let midnight = midnightAfter(now, calendar: calendar)
        return events.filter { !$0.isAllDay && !$0.isDeclined && !$0.isCancelled && $0.start < midnight }
    }

    /// Timed, not declined, not cancelled, end > now, start before tomorrow's midnight; by start; at most `limit`.
    public static func remainingToday(_ events: [AgendaEvent], now: Date, calendar: Calendar,
                                      limit: Int? = maxRows) -> [AgendaEvent] {
        let sorted = qualifying(events, now: now, calendar: calendar).filter { $0.end > now }.sorted { $0.start < $1.start }
        return limit.map { Array(sorted.prefix($0)) } ?? sorted
    }

    /// "now" while the first remaining event is running; its start time once within collapsedLookAhead; else nil.
    /// Without AM/PM, which is unambiguous within the hour and keeps the label inside the notch wing.
    public static func collapsedLabel(_ events: [AgendaEvent], now: Date, calendar: Calendar, locale: Locale) -> String? {
        guard let next = remainingToday(events, now: now, calendar: calendar).first else { return nil }
        if next.isRunning(at: now) { return "now" }
        guard next.start.timeIntervalSince(now) <= collapsedLookAhead else { return nil }
        var periods = calendar
        periods.locale = locale
        var label = timeLabel(next.start, calendar: calendar, locale: locale)
        for symbol in [periods.amSymbol, periods.pmSymbol] { label = label.replacingOccurrences(of: symbol, with: "") }
        return label.trimmingCharacters(in: .whitespaces)
    }

    /// Short time in the locale's 12/24-hour style, without seconds.
    public static func timeLabel(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar,
                                        timeZone: calendar.timeZone))
    }

    /// The next moment the output of the functions above can change.
    public static func nextBoundary(_ events: [AgendaEvent], now: Date, calendar: Calendar) -> Date {
        let moments = qualifying(events, now: now, calendar: calendar)
            .flatMap { [$0.start - collapsedLookAhead, $0.start, $0.end] }
            .filter { $0 > now }
        return (moments + [midnightAfter(now, calendar: calendar)]).min()!
    }
}

/// The week strip: six days around today, and which events fall on each.
public struct AgendaWeek: Equatable, Sendable {
    public static let daysBefore = 2
    public static let daysAfter = 3
    public var days: [Date]
    public var today: Date
    /// Start of the day after the last one: by the calendar, not 24 hours, so a clock change is covered.
    public var end: Date

    public var start: Date { days[0] }

    public init(now: Date, calendar: Calendar) {
        today = calendar.startOfDay(for: now)
        let base = today
        days = (-Self.daysBefore...Self.daysAfter).map { calendar.date(byAdding: .day, value: $0, to: base) ?? base }
        end = calendar.date(byAdding: .day, value: Self.daysAfter + 1, to: base) ?? base + Double(Self.daysAfter + 1) * 86_400
    }

    /// Timed, not declined, not cancelled, overlapping that day; for today only events not yet ended; by start.
    public func events(on day: Date, from events: [AgendaEvent], now: Date, calendar: Calendar) -> [AgendaEvent] {
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart + 86_400
        let isToday = dayStart == today
        return events.filter { e in
            !e.isAllDay && !e.isDeclined && !e.isCancelled && e.start < dayEnd
                && (e.end > dayStart || (e.start == e.end && e.start >= dayStart))
                && (!isToday || e.end > now)
        }
        .sorted { $0.start < $1.start }
    }

    public func hasEvents(_ events: [AgendaEvent], now: Date, calendar: Calendar) -> Bool {
        days.contains { !self.events(on: $0, from: events, now: now, calendar: calendar).isEmpty }
    }
}
