import AppKit
import EventKit
import Combine
import RavenIslandCore

enum CalendarAccess { case notAsked, granted, denied }

/// Today's remaining events, read-only. Nothing here asks for access except `requestAccess()`,
/// which only the Settings toggle calls.
@MainActor
final class CalendarSource: ObservableObject {
    @Published private(set) var events: [AgendaEvent] = []
    @Published private(set) var collapsedLabel: String?
    @Published private(set) var access: CalendarAccess

    private let settings: Settings
    private let store = EKEventStore()
    private var timer: Timer?
    private var subscriptions = Set<AnyCancellable>()

    init(settings: Settings) {
        self.settings = settings
        access = Self.currentAccess()
    }

    private static func currentAccess() -> CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .granted
        case .notDetermined: return .notAsked
        default: return .denied
        }
    }

    func start() {
        NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: store)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
        // @Published sends before the property changes, so pass the new value through.
        settings.$showCalendar.dropFirst().sink { [weak self] on in self?.refresh(showCalendar: on) }
            .store(in: &subscriptions)
        refresh()
    }

    func requestAccess() {
        Task {
            _ = try? await store.requestFullAccessToEvents()
            refresh()
        }
    }

    private func refresh(showCalendar: Bool? = nil) {
        timer?.invalidate()
        timer = nil
        let current = Self.currentAccess()
        if current != access { access = current }
        guard showCalendar ?? settings.showCalendar, current == .granted else {
            publish([], nil)
            return
        }
        let now = Date()
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now.addingTimeInterval(86_400)
        let all = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil)).map { e in
            AgendaEvent(id: "\(e.eventIdentifier ?? "")|\(e.startDate.timeIntervalSince1970)", title: e.title ?? "",
                        start: e.startDate, end: e.endDate, isAllDay: e.isAllDay,
                        isDeclined: e.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false,
                        isCancelled: e.status == .canceled, color: Self.rgb(e.calendar?.cgColor))
        }
        publish(Agenda.remainingToday(all, now: now, calendar: calendar, limit: nil),
                Agenda.collapsedLabel(all, now: now, calendar: calendar, locale: .current))
        let boundary = Agenda.nextBoundary(all, now: now, calendar: calendar)
        timer = Timer.scheduledTimer(withTimeInterval: max(1, boundary.timeIntervalSinceNow + 0.5), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private static func rgb(_ color: CGColor?) -> UInt32? {
        guard let c = color.flatMap(NSColor.init(cgColor:))?.usingColorSpace(.sRGB) else { return nil }
        func byte(_ v: CGFloat) -> UInt32 { UInt32((min(max(v, 0), 1) * 255).rounded()) }
        return byte(c.redComponent) << 16 | byte(c.greenComponent) << 8 | byte(c.blueComponent)
    }

    private func publish(_ events: [AgendaEvent], _ label: String?) {
        if events != self.events { self.events = events }
        if label != collapsedLabel { collapsedLabel = label }
    }
}
