import Foundation
import Testing
@testable import RavenIslandCore

@Suite struct TonesTests {
    @Test func everySoundIsAudibleShortAndUnclipped() {
        for event in SoundEvent.allCases {
            let samples = ToneSynth.render(event)
            let seconds = Double(samples.count) / 44_100
            let peak = samples.map(abs).max() ?? 0
            #expect(seconds > 0.15 && seconds < 0.6, "\(event) lasts \(seconds)s")
            #expect(peak > 0.2 && peak <= 1.0, "\(event) peak \(peak)")
            #expect(abs(samples.last ?? 1) < 0.01, "\(event) ends with a click")
        }
        // The four sounds are distinguishable by length or content.
        #expect(Set(SoundEvent.allCases.map { ToneSynth.render($0).count }).count == 4)
    }

    @Test func wavHeader() {
        let samples: [Float] = [0, 0.5, -0.5, 2, -2]
        let wav = ToneSynth.wav(samples)
        #expect(wav.count == 44 + samples.count * 2)
        #expect(String(data: wav.prefix(4), encoding: .ascii) == "RIFF")
        #expect(String(data: wav[8..<12], encoding: .ascii) == "WAVE")
        let last = wav.suffix(2).withUnsafeBytes { Int16(littleEndian: $0.loadUnaligned(as: Int16.self)) }
        #expect(last == -32_767)   // out-of-range input is clamped, not wrapped
    }

    @Test func transitionsThatMakeSound() {
        #expect(SoundEvent.forTransition(from: .working, to: .needsApproval) == .approval)
        #expect(SoundEvent.forTransition(from: .working, to: .waitingForInput) == .question)
        #expect(SoundEvent.forTransition(from: .working, to: .done) == .done)
        #expect(SoundEvent.forTransition(from: nil, to: .error) == .error)
        #expect(SoundEvent.forTransition(from: .needsApproval, to: .needsApproval) == nil)   // no repeat
        #expect(SoundEvent.forTransition(from: .done, to: .working) == nil)
        #expect(SoundEvent.forTransition(from: nil, to: .idle) == nil)
    }

    @Test func quietHours() {
        #expect(QuietHours.isQuiet(hour: 23, start: 22, end: 7))
        #expect(QuietHours.isQuiet(hour: 3, start: 22, end: 7))
        #expect(!QuietHours.isQuiet(hour: 7, start: 22, end: 7))
        #expect(!QuietHours.isQuiet(hour: 12, start: 22, end: 7))
        #expect(QuietHours.isQuiet(hour: 13, start: 12, end: 14))
        #expect(!QuietHours.isQuiet(hour: 14, start: 12, end: 14))
        #expect(!QuietHours.isQuiet(hour: 5, start: 9, end: 9))
    }
}
