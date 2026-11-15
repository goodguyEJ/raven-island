import AVFoundation
import RavenIslandCore

/// Plays the sound for an event: a file from the chosen pack if it has one, otherwise the built-in tone.
@MainActor
final class SoundPlayer: NSObject, AVAudioPlayerDelegate {
    private let settings: Settings
    private var playing: [AVAudioPlayer] = []
    private var lastPlayed: [SoundEvent: Date] = [:]
    private var builtIn: [SoundEvent: Data] = [:]
    static let extensions = ["wav", "aiff", "aif", "mp3", "m4a", "caf"]

    init(settings: Settings) {
        self.settings = settings
    }

    /// Respects the user's sound settings. `force` is for the preview buttons in Settings.
    func play(_ event: SoundEvent, force: Bool = false) {
        if !force {
            guard settings.soundsEnabled, settings.isOn(event), !settings.isQuietNow else { return }
            // Several sessions changing at once shouldn't stack the same sound.
            if let last = lastPlayed[event], Date().timeIntervalSince(last) < 0.8 { return }
        }
        lastPlayed[event] = Date()
        guard let player = makePlayer(event) else { return }
        player.volume = Float(settings.volume)
        player.delegate = self
        playing.append(player)
        player.play()
    }

    private func makePlayer(_ event: SoundEvent) -> AVAudioPlayer? {
        if settings.soundPack != Settings.builtInPack {
            let folder = Settings.soundsFolder.appendingPathComponent(settings.soundPack, isDirectory: true)
            for ext in Self.extensions {
                let file = folder.appendingPathComponent("\(event.rawValue).\(ext)")
                if FileManager.default.fileExists(atPath: file.path), let p = try? AVAudioPlayer(contentsOf: file) { return p }
            }
        }
        let data = builtIn[event] ?? ToneSynth.wav(ToneSynth.render(event))
        builtIn[event] = data
        return try? AVAudioPlayer(data: data)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.playing.removeAll { $0 === player } }
    }
}
