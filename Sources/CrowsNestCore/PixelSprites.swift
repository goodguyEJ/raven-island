import Foundation

/// Shared facts about the pixel art. The agents and their props are drawn in `Personas.swift`.
public enum PixelSprites {
    /// Rows in every frame.
    public static let size = 16
    /// Columns in every frame: the agent on the left, its prop on the right.
    public static let width = 20

    /// Seconds per frame.
    public static func frameDuration(for state: SessionState) -> Double {
        switch state {
        case .working: return 0.22
        case .needsApproval: return 0.3
        case .waitingForInput, .done: return 0.45
        case .error: return 0.35
        case .idle: return 0.25
        }
    }

    /// Stable slot for a session, so each one keeps its own agent.
    public static func tintIndex(for sessionID: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return Int(sessionID.utf8.reduce(UInt32(7)) { ($0 &* 31) &+ UInt32($1) } % UInt32(count))
    }
}
