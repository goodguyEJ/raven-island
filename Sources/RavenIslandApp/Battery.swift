import SwiftUI
import IOKit.ps

/// The built-in battery; nil on a Mac without one.
struct BatteryStatus: Equatable {
    var percent: Int
    var onPower: Bool

    static func read() -> BatteryStatus? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            return BatteryStatus(percent: min(100, current * 100 / max),
                                 onPower: d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
        }
        return nil
    }

    /// Beside the notch: just the level, red to 20%, yellow to 50%, green above.
    var levelColor: Color { percent <= 20 ? .red : (percent <= 50 ? .yellow : .green) }

    /// Plugged in counts as charging even when charging is paused (Optimised Battery Charging holds at 80%).
    var color: Color {
        if onPower { return .green }
        return percent <= 20 ? .red : .white.opacity(0.75)
    }
}

struct HeaderBattery: View {
    /// Off while "Clear N done" shares the header, which would otherwise reach under the notch.
    var showsPercent = true

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            if let battery = BatteryStatus.read() {
                HStack(spacing: 3) {
                    BatteryGlyph(battery: battery)
                    if showsPercent {
                        Text("\(battery.percent)%").font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                            .foregroundStyle(battery.color)
                    }
                }
                .fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Battery \(battery.percent) percent\(battery.onPower ? ", plugged in" : "")")
            }
        }
    }
}

/// Drawn like the menu bar's: the body fills to the actual level, with a bolt over it while plugged in.
struct BatteryGlyph: View {
    var battery: BatteryStatus

    var body: some View {
        HStack(spacing: 1) {
            ZStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(.white.opacity(0.45), lineWidth: 1)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(battery.color)
                    .frame(width: max(1.5, 17 * CGFloat(battery.percent) / 100))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(2)
                if battery.onPower {
                    Image(systemName: "bolt.fill").font(.system(size: 7.5, weight: .black)).foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 0.5)
                }
            }
            .frame(width: 21, height: 10)
            RoundedRectangle(cornerRadius: 1).fill(.white.opacity(0.45)).frame(width: 1.5, height: 4)
        }
    }
}

/// The time, in the right wing beside the notch. No AM/PM: the wing is too narrow for it.
struct NotchClock: View {
    private static let format: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = (DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: .current) ?? "H:mm")
            .replacingOccurrences(of: "[aBb]", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        return f
    }()

    /// Hour of day and colour: night blue, rose at dawn, gold in the morning, amber through the
    /// afternoon, violet at dusk, back to night blue. Hours between two stops blend.
    private static let sky: [(hour: Double, rgb: (Double, Double, Double))] = [
        (0, (0.55, 0.64, 1.0)), (5, (0.55, 0.64, 1.0)), (6.5, (1.0, 0.6, 0.66)), (9, (1.0, 0.84, 0.35)),
        (13, (1.0, 0.68, 0.3)), (17.5, (1.0, 0.68, 0.3)), (19, (0.85, 0.6, 0.95)), (20.5, (0.55, 0.64, 1.0)),
        (24, (0.55, 0.64, 1.0)),
    ]

    static func color(at date: Date) -> Color {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
        let upper = sky.firstIndex { $0.hour > hour } ?? sky.count - 1
        let (a, b) = (sky[max(0, upper - 1)], sky[upper])
        let t = b.hour > a.hour ? (hour - a.hour) / (b.hour - a.hour) : 0
        return Color(red: a.rgb.0 + (b.rgb.0 - a.rgb.0) * t, green: a.rgb.1 + (b.rgb.1 - a.rgb.1) * t,
                     blue: a.rgb.2 + (b.rgb.2 - a.rgb.2) * t)
    }

    private static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd"
        return f
    }()

    /// Every 15 seconds, the date and then the battery show for 3 seconds each before the time returns.
    var rotates = false

    private static func detail(at date: Date) -> Int {
        let second = Int(date.timeIntervalSinceReferenceDate) % 15
        return second >= 12 ? 2 : (second >= 9 ? 1 : 0)
    }

    var body: some View {
        let minute = Calendar.current.dateInterval(of: .minute, for: .now)?.start ?? .now
        TimelineView(.periodic(from: minute, by: rotates ? 1 : 60)) { context in
            let turn = rotates ? Self.detail(at: context.date) : 0
            let battery = turn == 2 ? BatteryStatus.read() : nil
            let index = turn == 2 && battery == nil ? 0 : turn
            ZStack {
                Group {
                    switch index {
                    case 1: Text(Self.monthDay.string(from: context.date))
                    case 2: battery.map { b in Text("\(b.percent)%").foregroundStyle(b.levelColor) }
                    default: Text(Self.format.string(from: context.date))
                    }
                }
                .id(index)
                .transition(.opacity)
            }
            .animation(Motion.fade, value: index)
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .foregroundStyle(Self.color(at: context.date))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }
}
