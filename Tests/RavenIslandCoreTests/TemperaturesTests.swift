import Testing
@testable import RavenIslandCore

@Suite struct TemperaturesTests {
    func temps(_ readings: [(String, Double)]) -> Temperatures {
        Temperatures(readings: readings.map { SensorReading(name: $0.0, celsius: $0.1) })
    }

    func level(_ name: String, _ celsius: Double) -> TemperatureLevel? {
        temps([(name, celsius)]).shown.first?.level
    }

    @Test func cpuIsTheHottestDieSensor() {
        #expect(temps([("PMU tdie1", 40), ("PMU tdie2", 46), ("PMU2 tdie1", 43)]).cpu == 46)
    }

    @Test func calibrationAndDeviceSensorsAreNotCPU() {
        #expect(temps([("PMU tcal", 51.8), ("PMU tdev1", 60), ("PMU tdie1", 40)]).cpu == 40)
    }

    @Test func ssdIsTheHottestSensorWhoseNameStartsWithNAND() {
        let t = temps([("NAND CH0 temp", 35), ("NAND CH1 temp", 37), ("not NAND", 80)])
        #expect(t.ssd == 37)
    }

    @Test func batteryIsTheHottestGasGaugeReading() {
        let t = temps([("gas gauge battery", 31), ("gas gauge battery", 32.4), ("gas gauge battery", 30)])
        #expect(t.battery == 32.4)
    }

    @Test func readingsOutsideZeroTo150AreDiscarded() {
        let t = temps([("PMU tdie1", 0), ("PMU tdie2", -5), ("PMU tdie3", 150), ("PMU tdie4", 44),
                       ("NAND CH0 temp", 200), ("gas gauge battery", .nan)])
        #expect(t.cpu == 44)
        #expect(t.ssd == nil)
        #expect(t.battery == nil)
    }

    @Test func unknownSensorsAreIgnored() {
        #expect(temps([("PMU tcal", 51.8), ("some new sensor", 40)]).shown.isEmpty)
        #expect(temps([]).shown.isEmpty)
    }

    @Test func shownAsCPUThenSSDInWholeDegreesThenBatteryToOneDecimal() {
        let t = temps([("gas gauge battery", 29.8), ("NAND CH0 temp", 34), ("PMU tdie1", 50.4), ("PMU tdie2", 42.9)])
        #expect(t.shown == [
            ShownTemperature(label: "CPU", value: "50°", level: .safe),
            ShownTemperature(label: "SSD", value: "34°", level: .safe),
            ShownTemperature(label: "Battery", value: "29.8°", level: .safe),
        ])
    }

    @Test func aSensorThatIsMissingIsLeftOut() {
        #expect(temps([("PMU tdie1", 45.3), ("gas gauge battery", 32)]).shown.map(\.label) == ["CPU", "Battery"])
    }

    @Test func cpuIsSafeBelow70WarningTo89AndHotFrom90() {
        #expect(level("PMU tdie1", 69) == .safe)
        #expect(level("PMU tdie1", 70) == .warning)
        #expect(level("PMU tdie1", 89) == .warning)
        #expect(level("PMU tdie1", 90) == .hot)
    }

    @Test func ssdIsSafeBelow50WarningTo64AndHotFrom65() {
        #expect(level("NAND CH0 temp", 49) == .safe)
        #expect(level("NAND CH0 temp", 50) == .warning)
        #expect(level("NAND CH0 temp", 64) == .warning)
        #expect(level("NAND CH0 temp", 65) == .hot)
    }

    @Test func batteryIsSafeBelow35WarningTo44AndHotFrom45() {
        #expect(level("gas gauge battery", 34) == .safe)
        #expect(level("gas gauge battery", 35) == .warning)
        #expect(level("gas gauge battery", 44) == .warning)
        #expect(level("gas gauge battery", 45) == .hot)
    }

    @Test func theLevelFollowsTheNumberOnScreen() {
        #expect(temps([("PMU tdie1", 69.6)]).shown == [ShownTemperature(label: "CPU", value: "70°", level: .warning)])
        #expect(temps([("PMU tdie1", 69.4)]).shown == [ShownTemperature(label: "CPU", value: "69°", level: .safe)])
        #expect(temps([("gas gauge battery", 34.96)]).shown == [ShownTemperature(label: "Battery", value: "35.0°", level: .warning)])
        #expect(temps([("gas gauge battery", 34.94)]).shown == [ShownTemperature(label: "Battery", value: "34.9°", level: .safe)])
    }
}
