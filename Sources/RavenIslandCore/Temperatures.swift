import Foundation

public struct SensorReading: Equatable, Sendable {
    public var name: String
    public var celsius: Double

    public init(name: String, celsius: Double) {
        self.name = name
        self.celsius = celsius
    }
}

public enum TemperatureLevel: Equatable, Sendable {
    case safe, warning, hot
}

public struct ShownTemperature: Equatable, Sendable {
    public var label: String
    public var value: String
    public var level: TemperatureLevel

    public init(label: String, value: String, level: TemperatureLevel) {
        self.label = label
        self.value = value
        self.level = level
    }
}

/// The three internal temperatures, in °C: the hottest reading of each kind. A sensor this Mac
/// does not have stays nil.
public struct Temperatures: Equatable, Sendable {
    public var cpu: Double?
    public var ssd: Double?
    public var battery: Double?

    /// Sensor names differ between chip generations (these were seen on an M2); extend here.
    /// "tdie" leaves out the PMU's "tcal" (a calibration constant) and "tdev" sensors.
    /// `warning` and `hot` are the degrees from which the reading stops being safe.
    private static let sensors: [(path: WritableKeyPath<Temperatures, Double?>, label: String, decimals: Int,
                                  warning: Double, hot: Double, matches: (String) -> Bool)] = [
        (\.cpu, "CPU", 0, 70, 90, { $0.contains("tdie") }),
        (\.ssd, "SSD", 0, 50, 65, { $0.hasPrefix("NAND") }),
        (\.battery, "Battery", 1, 35, 45, { $0 == "gas gauge battery" }),
    ]

    public init(readings: [SensorReading]) {
        for reading in readings where reading.celsius > 0 && reading.celsius < 150 {
            guard let path = Self.sensors.first(where: { $0.matches(reading.name) })?.path else { continue }
            self[keyPath: path] = max(self[keyPath: path] ?? 0, reading.celsius)
        }
    }

    public var shown: [ShownTemperature] {
        Self.sensors.compactMap { sensor in
            guard let reading = self[keyPath: sensor.path] else { return nil }
            // Judged on the number as shown, so the colour and the digits cannot disagree.
            let scale = pow(10, Double(sensor.decimals))
            let degrees = (reading * scale).rounded() / scale
            return ShownTemperature(label: sensor.label, value: String(format: "%.\(sensor.decimals)f°", degrees),
                                    level: degrees >= sensor.hot ? .hot : (degrees >= sensor.warning ? .warning : .safe))
        }
    }
}
