import SwiftUI
import IOHIDPrivate
import RavenIslandCore

final class TemperatureSource: ObservableObject {
    @Published private(set) var temperatures = Temperatures(readings: [])

    private let queue = DispatchQueue(label: "ravenisland.temperatures", qos: .utility, autoreleaseFrequency: .workItem)
    private var client: IOHIDEventSystemClient?
    private var timer: DispatchSourceTimer?

    /// On while the setting is on and the panel is open; nothing is sampled otherwise.
    var isActive = false {
        didSet {
            guard isActive != oldValue else { return }
            timer?.cancel()
            timer = nil
            guard isActive else { return }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: 3, leeway: .milliseconds(500))
            timer.setEventHandler { [weak self] in self?.refresh() }
            timer.resume()
            self.timer = timer
        }
    }

    private func refresh() {
        let temperatures = Temperatures(readings: read())
        DispatchQueue.main.async {
            // Raw readings differ on almost every read; republishing redraws the whole panel.
            if temperatures.shown != self.temperatures.shown { self.temperatures = temperatures }
        }
    }

    private func read() -> [SensorReading] {
        if client == nil, let created = IOHIDEventSystemClientCreate(kCFAllocatorDefault) {
            // Apple vendor usage page, temperature sensor usage.
            _ = IOHIDEventSystemClientSetMatching(created, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
            client = created
        }
        guard let client, let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else { return [] }
        let temperature: Int64 = 15   // kIOHIDEventTypeTemperature
        return services.compactMap { service in
            guard let name = IOHIDServiceClientCopyProperty(service, "Product" as CFString) as? String,
                  let event = IOHIDServiceClientCopyEvent(service, temperature, 0, 0) else { return nil }
            return SensorReading(name: name, celsius: IOHIDEventGetFloatValue(event, Int32(temperature << 16)))
        }
    }
}

extension TemperatureLevel {
    var color: Color {
        switch self {
        case .safe: return .green
        case .warning: return .yellow
        case .hot: return .red
        }
    }

    var spoken: String {
        switch self {
        case .safe: return ""
        case .warning: return ", warm"
        case .hot: return ", hot"
        }
    }
}

struct TemperatureFooter: View {
    var temperatures: [ShownTemperature]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(temperatures, id: \.label) { temperature in
                HStack(spacing: 3) {
                    Text(temperature.label).foregroundStyle(.white.opacity(0.55))
                    Text(temperature.value).fontWeight(.semibold).foregroundStyle(temperature.level.color)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(temperature.label) \(temperature.value)\(temperature.level.spoken)")
            }
        }
        .font(.system(size: 10.5).monospacedDigit())
        .lineLimit(1)
    }
}
