import Foundation

/// Turns an artwork's average colour into one that reads on the black panel.
public enum ArtworkTint {
    static let minBrightness = 0.75
    static let minSaturation = 0.45
    /// Below these the average has no real hue (or is too dark to tell), so it stays grey rather than
    /// turning a random colour.
    static let greyThreshold = 0.12
    static let darkThreshold = 0.15

    public static func readable(red: Double, green: Double, blue: Double) -> (red: Double, green: Double, blue: Double) {
        let maxC = max(red, green, blue), minC = min(red, green, blue)
        let delta = maxC - minC
        var saturation = maxC > 0 ? delta / maxC : 0
        let brightness = max(maxC, minBrightness)
        guard saturation >= greyThreshold, maxC >= darkThreshold else { return (brightness, brightness, brightness) }
        saturation = max(saturation, minSaturation)

        var hue: Double
        if maxC == red { hue = (green - blue) / delta }
        else if maxC == green { hue = 2 + (blue - red) / delta }
        else { hue = 4 + (red - green) / delta }
        hue = (hue / 6).truncatingRemainder(dividingBy: 1)
        if hue < 0 { hue += 1 }
        return fromHSB(hue, saturation, brightness)
    }

    private static func fromHSB(_ h: Double, _ s: Double, _ v: Double) -> (red: Double, green: Double, blue: Double) {
        let sector = h * 6
        let i = Int(sector) % 6
        let f = sector - Double(Int(sector))
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch i {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }
}
