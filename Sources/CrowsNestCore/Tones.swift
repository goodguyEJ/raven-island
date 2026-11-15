import Foundation

public enum SoundEvent: String, CaseIterable, Sendable {
    case approval, question, done, error

    public var label: String {
        switch self {
        case .approval: return "Needs approval"
        case .question: return "Question"
        case .done: return "Finished"
        case .error: return "Error"
        }
    }

    /// The sound for a session entering `state`, if that change deserves one.
    public static func forTransition(from old: SessionState?, to new: SessionState) -> SoundEvent? {
        guard old != new else { return nil }
        switch new {
        case .needsApproval: return .approval
        case .waitingForInput: return .question
        case .done: return .done
        case .error: return .error
        case .idle, .working: return nil
        }
    }
}

/// Small chip-style synthesizer for the built-in sounds: plain waveforms with a plucked envelope.
public enum ToneSynth {
    public enum Wave: Sendable { case square, triangle }

    public struct Note: Sendable {
        public var frequency: Double
        public var duration: Double
        public var wave: Wave
    }

    public static func notes(for event: SoundEvent) -> [Note] {
        switch event {
        case .approval:   // two quick rising notes: "look here"
            return [Note(frequency: 659.25, duration: 0.09, wave: .square), Note(frequency: 987.77, duration: 0.16, wave: .square)]
        case .question:   // up, then a held turn
            return [Note(frequency: 587.33, duration: 0.08, wave: .triangle), Note(frequency: 783.99, duration: 0.08, wave: .triangle),
                    Note(frequency: 698.46, duration: 0.18, wave: .triangle)]
        case .done:       // major arpeggio
            return [523.25, 659.25, 783.99, 1046.5].enumerated().map {
                Note(frequency: $0.element, duration: $0.offset == 3 ? 0.22 : 0.07, wave: .triangle)
            }
        case .error:      // two low falling notes
            return [Note(frequency: 220, duration: 0.12, wave: .square), Note(frequency: 164.81, duration: 0.24, wave: .square)]
        }
    }

    public static func render(_ event: SoundEvent, sampleRate: Double = 44_100) -> [Float] {
        var out: [Float] = []
        for note in notes(for: event) {
            let count = Int(note.duration * sampleRate)
            let attack = max(1, Int(0.004 * sampleRate))
            for i in 0..<count {
                let phase = (Double(i) * note.frequency / sampleRate).truncatingRemainder(dividingBy: 1)
                let raw: Double
                switch note.wave {
                case .square: raw = phase < 0.5 ? 0.55 : -0.55          // quieter: squares sound louder
                case .triangle: raw = 4 * abs(phase - 0.5) - 1
                }
                let rise = min(1, Double(i) / Double(attack))
                let decay = exp(-3.2 * Double(i) / Double(count))
                let release = min(1, Double(count - i) / Double(attack))   // no click at the note's end
                out.append(Float(raw * rise * decay * release * 0.8))
            }
        }
        return out
    }

    /// 16-bit mono PCM WAV.
    public static func wav(_ samples: [Float], sampleRate: Int = 44_100) -> Data {
        func le<T: FixedWidthInteger>(_ v: T) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        let dataSize = UInt32(samples.count * 2)
        var d = Data("RIFF".utf8)
        d += le(UInt32(36) + dataSize); d += Data("WAVEfmt ".utf8)
        d += le(UInt32(16)); d += le(UInt16(1)); d += le(UInt16(1))
        d += le(UInt32(sampleRate)); d += le(UInt32(sampleRate * 2)); d += le(UInt16(2)); d += le(UInt16(16))
        d += Data("data".utf8); d += le(dataSize)
        for s in samples { d += le(Int16(max(-1, min(1, s)) * 32_767)) }
        return d
    }
}

public enum QuietHours {
    /// True when `hour` (0–23) falls in [start, end). A range that wraps midnight (22 → 7) is supported;
    /// start == end means quiet hours are effectively off.
    public static func isQuiet(hour: Int, start: Int, end: Int) -> Bool {
        if start == end { return false }
        return start < end ? (hour >= start && hour < end) : (hour >= start || hour < end)
    }
}
