import SwiftUI

/// The motion presets from DESIGN.md, section 7.
enum Motion {
    static let quick = 0.12
    static let standard = 0.2
    /// How long the window waits for the panel spring before it shrinks.
    static let panelSettle = 0.45

    static let panel = Animation.spring(response: 0.36, dampingFraction: 0.82)
    static let press = Animation.spring(response: 0.25, dampingFraction: 0.9)
    static let hover = Animation.easeOut(duration: quick)
    static let fade = Animation.easeInOut(duration: standard)

    static let spin = Animation.linear(duration: 0.9).repeatForever(autoreverses: false)
    static let pulse = Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)
}

struct PressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            // 0.5 when disabled is what the plain style these buttons used to have draws.
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.5)
            .animation(Motion.press, value: configuration.isPressed)
    }
}
