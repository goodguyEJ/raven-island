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

/// The compact Today timeline: a fixed window of a few hours and where each event sits in it.
public struct AgendaTimeline: Equatable, Sendable {
    public struct Block: Equatable, Sendable {
        public var event: AgendaEvent
        /// 0...1 of the window, from its start.
        public var top: Double
        public var height: Double
        public var column: Int
        public var columns: Int
    }

    public static let span: TimeInterval = 3 * 3600
    public var start: Date
    public var end: Date
    public var hourMarks: [Date]
    public var nowOffset: Double
    public var blocks: [Block]
    /// The next event after the window, shown only when nothing new starts inside it.
    public var later: AgendaEvent?

    /// Starts at the latest full or half hour at or before `now`, so "now" stays near the top.
    public init(events: [AgendaEvent], now: Date, calendar: Calendar, minimumHeight: Double) {
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        start = calendar.date(bySettingHour: parts.hour ?? 0, minute: (parts.minute ?? 0) < 30 ? 0 : 30, second: 0, of: now) ?? now
        end = start + Self.span
        let firstHour = calendar.dateComponents([.minute], from: start).minute == 0 ? start : start + 1800
        hourMarks = stride(from: 0.0, through: end.timeIntervalSince(firstHour), by: 3600).map { firstHour + $0 }
        nowOffset = now.timeIntervalSince(start) / Self.span

        let (windowStart, windowEnd) = (start, end)
        let remaining = Agenda.remainingToday(events, now: now, calendar: calendar, limit: nil)
        let visible = remaining.filter { $0.start < windowEnd && ($0.end > windowStart || $0.start >= windowStart) }
        // Columns follow the drawn extent, which a short event's minimum height can push past its real end.
        func drawnEnd(_ e: AgendaEvent) -> Date { max(e.end, e.start + minimumHeight * Self.span) }
        var columnEnds: [Date?] = [nil, nil]
        var placed: [(event: AgendaEvent, column: Int)] = []
        var realEnds: [Date?] = [nil, nil]
        for event in visible {
            // Without room for the drawn size, an event that does not really overlap still gets a column:
            // a slightly overlapping block beats a meeting that silently disappears.
            guard let column = columnEnds.firstIndex(where: { $0.map { $0 <= event.start } ?? true })
                    ?? realEnds.firstIndex(where: { $0.map { $0 <= event.start } ?? true }) else { continue }
            columnEnds[column] = drawnEnd(event)
            realEnds[column] = event.end
            placed.append((event, column))
        }
        func overlaps(_ a: AgendaEvent, _ b: AgendaEvent) -> Bool { a.start < drawnEnd(b) && b.start < drawnEnd(a) }
        blocks = placed.map { item in
            let top = max(0, item.event.start.timeIntervalSince(windowStart) / Self.span)
            let bottom = min(1, item.event.end.timeIntervalSince(windowStart) / Self.span)
            let height = min(1, max(bottom - top, minimumHeight))
            let shared = placed.contains { $0.column != item.column && overlaps($0.event, item.event) }
            return Block(event: item.event, top: min(top, 1 - height), height: height, column: item.column, columns: shared ? 2 : 1)
        }
        let startsInside = remaining.contains { $0.start > now && $0.start < windowEnd }
        later = startsInside ? nil : remaining.first { $0.start >= windowEnd }
    }
}
