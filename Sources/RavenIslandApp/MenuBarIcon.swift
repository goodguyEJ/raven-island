import AppKit

/// The menu bar icon: a small island with two palms over a wave. A template image, so macOS
/// colours it for light and dark menu bars.
enum MenuBarIcon {
    static func image() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.set()

            let wave = NSBezierPath()
            wave.move(to: NSPoint(x: 1, y: 2.2))
            wave.curve(to: NSPoint(x: 6.5, y: 2.2), controlPoint1: NSPoint(x: 2.8, y: 3.4), controlPoint2: NSPoint(x: 4.7, y: 1))
            wave.curve(to: NSPoint(x: 12, y: 2.2), controlPoint1: NSPoint(x: 8.3, y: 3.4), controlPoint2: NSPoint(x: 10.2, y: 1))
            wave.curve(to: NSPoint(x: 17, y: 2.2), controlPoint1: NSPoint(x: 13.8, y: 3.4), controlPoint2: NSPoint(x: 15.4, y: 1))
            wave.lineWidth = 1.2
            wave.lineCapStyle = .round
            wave.stroke()

            let island = NSBezierPath()
            island.move(to: NSPoint(x: 2.5, y: 4))
            island.curve(to: NSPoint(x: 15.5, y: 4), controlPoint1: NSPoint(x: 5, y: 7.2), controlPoint2: NSPoint(x: 13, y: 7.2))
            island.close()
            island.fill()

            palm(base: NSPoint(x: 8, y: 5.5), top: NSPoint(x: 10.5, y: 14.5), bend: NSPoint(x: 8.2, y: 11), frond: 4.2)
            palm(base: NSPoint(x: 11.5, y: 5.2), top: NSPoint(x: 13.2, y: 10.5), bend: NSPoint(x: 11.8, y: 8.5), frond: 3)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Raven Island"
        return image
    }

    private static func palm(base: NSPoint, top: NSPoint, bend: NSPoint, frond: CGFloat) {
        let trunk = NSBezierPath()
        trunk.move(to: base)
        trunk.curve(to: top, controlPoint1: bend, controlPoint2: bend)
        trunk.lineWidth = 1.3
        trunk.lineCapStyle = .round
        trunk.stroke()
        for angle: CGFloat in [160, 120, 75, 35, -5] {
            let rad = angle * .pi / 180
            let tip = NSPoint(x: top.x + frond * cos(rad), y: top.y + frond * sin(rad) - frond * 0.35)
            let mid = NSPoint(x: top.x + frond * 0.6 * cos(rad), y: top.y + frond * 0.6 * sin(rad) + 0.6)
            let leaf = NSBezierPath()
            leaf.move(to: top)
            leaf.curve(to: tip, controlPoint1: mid, controlPoint2: mid)
            leaf.lineWidth = 1.1
            leaf.lineCapStyle = .round
            leaf.stroke()
        }
    }
}
