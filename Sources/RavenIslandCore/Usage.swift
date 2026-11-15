import Foundation

public struct UsageWindow: Codable, Equatable, Sendable {
    /// 0–100.
    public var usedPercent: Double
    public var resetsAt: Date?
    public init(usedPercent: Double, resetsAt: Date?) { self.usedPercent = usedPercent; self.resetsAt = resetsAt }
}

public enum UsageLevel: Sendable { case normal, warning, critical }

/// Subscription usage as reported to Claude Code's status line.
public struct UsageSnapshot: Codable, Equatable, Sendable {
    public var fiveHour: UsageWindow?
    public var sevenDay: UsageWindow?
    public var updatedAt: Date

    public init(fiveHour: UsageWindow?, sevenDay: UsageWindow?, updatedAt: Date) {
        self.fiveHour = fiveHour; self.sevenDay = sevenDay; self.updatedAt = updatedAt
    }

    /// Nil when the status line input carries no usage (API-key users, or before a session's first response).
    public init?(statusLine payload: JSONValue, now: Date = Date()) {
        guard let limits = payload["rate_limits"] else { return nil }
        func window(_ key: String) -> UsageWindow? {
            guard let w = limits[key], let used = w["used_percentage"]?.number else { return nil }
            guard used.isFinite else { return nil }
            // Reset times are only believed within a sane window (windows are at most a week long).
            let reset = w["resets_at"]?.number.flatMap { seconds -> Date? in
                guard seconds.isFinite else { return nil }
                let date = Date(timeIntervalSince1970: seconds)
                let delta = date.timeIntervalSince(now)
                return delta > -86_400 && delta < 31 * 86_400 ? date : nil
            }
            return UsageWindow(usedPercent: min(100, max(0, used)), resetsAt: reset)
        }
        let five = window("five_hour"), seven = window("seven_day")
        guard five != nil || seven != nil else { return nil }
        self.init(fiveHour: five, sevenDay: seven, updatedAt: now)
    }

    /// A newer report replaces only the windows it mentions.
    public func merging(_ newer: UsageSnapshot) -> UsageSnapshot {
        UsageSnapshot(fiveHour: newer.fiveHour ?? fiveHour, sevenDay: newer.sevenDay ?? sevenDay, updatedAt: newer.updatedAt)
    }

    /// A window whose reset time has passed has started over, so its old percentage is dropped.
    public func current(now: Date = Date()) -> UsageSnapshot {
        func live(_ w: UsageWindow?) -> UsageWindow? {
            guard let w, w.usedPercent.isFinite else { return nil }
            if let reset = w.resetsAt, reset <= now || reset.timeIntervalSince(now) > 31 * 86_400 { return nil }
            return w
        }
        return UsageSnapshot(fiveHour: live(fiveHour), sevenDay: live(sevenDay), updatedAt: updatedAt)
    }

    public var isEmpty: Bool { fiveHour == nil && sevenDay == nil }

    public static func level(_ percent: Double) -> UsageLevel {
        percent >= 90 ? .critical : (percent >= 75 ? .warning : .normal)
    }

    /// "12m", "2h 13m", "3d 4h".
    public static func countdown(to date: Date, now: Date = Date()) -> String {
        let interval = date.timeIntervalSince(now)
        let s = interval.isFinite ? Int(max(0, min(interval, 365 * 86_400))) : 0
        if s < 3600 { return "\(max(1, s / 60))m" }
        if s < 86_400 { return "\(s / 3600)h \((s % 3600) / 60)m" }
        return "\(s / 86_400)d \((s % 86_400) / 3600)h"
    }
}
