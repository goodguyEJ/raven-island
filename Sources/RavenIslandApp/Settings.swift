import Foundation
import Combine
import ServiceManagement
import RavenIslandCore

/// User preferences, stored in UserDefaults.
@MainActor
final class Settings: ObservableObject {
    static let builtInPack = "Built-in"
    private let defaults: UserDefaults

    @Published var autoExpand: Bool { didSet { defaults.set(autoExpand, forKey: "autoExpand") } }
    @Published var answersFromPanel: Bool { didSet { defaults.set(answersFromPanel, forKey: "answersFromPanel") } }
    @Published var showCharacters: Bool { didSet { defaults.set(showCharacters, forKey: "showCharacters") } }
    /// With nothing running, a character strolls beside the notch.
    @Published var strollWhenIdle: Bool { didSet { defaults.set(strollWhenIdle, forKey: "strollWhenIdle") } }
    /// Beside the notch, take turns showing the time, the date and the battery.
    @Published var rotateNotchDetails: Bool { didSet { defaults.set(rotateNotchDetails, forKey: "rotateNotchDetails") } }
    /// "auto": the built-in notched display when there is one. "primary": the display with the menu bar.
    @Published var displayMode: String { didSet { defaults.set(displayMode, forKey: "displayMode") } }
    /// Keeps the panel out of screen shares, recordings, and screenshots.
    @Published var hideFromScreenSharing: Bool { didSet { defaults.set(hideFromScreenSharing, forKey: "hideFromScreenSharing") } }
    /// Minutes a finished session stays in the list; 0 keeps it until cleared by hand.
    @Published var autoClearMinutes: Int { didSet { defaults.set(autoClearMinutes, forKey: "autoClearMinutes") } }
    @Published var clearOnJump: Bool { didSet { defaults.set(clearOnJump, forKey: "clearOnJump") } }
    /// The setup window was dismissed with "Not now"; don't open it again on launch.
    @Published var setupDeferred: Bool { didSet { defaults.set(setupDeferred, forKey: "setupDeferred") } }
    @Published var shortcutsEnabled: Bool { didSet { defaults.set(shortcutsEnabled, forKey: "shortcutsEnabled") } }
    @Published var showMusic: Bool { didSet { defaults.set(showMusic, forKey: "showMusic") } }
    /// Off by default: loading Spotify album art is the app's only network request.
    @Published var spotifyArtwork: Bool { didSet { defaults.set(spotifyArtwork, forKey: "spotifyArtwork") } }
    /// Off by default: turning it on is what asks for Calendar access.
    @Published var showCalendar: Bool { didSet { defaults.set(showCalendar, forKey: "showCalendar") } }

    @Published var showTemperatures: Bool { didSet { defaults.set(showTemperatures, forKey: "showTemperatures") } }

    @Published var soundsEnabled: Bool { didSet { defaults.set(soundsEnabled, forKey: "soundsEnabled") } }
    @Published var volume: Double { didSet { defaults.set(volume, forKey: "volume") } }
    @Published var mutedEvents: Set<String> { didSet { defaults.set(Array(mutedEvents), forKey: "mutedEvents") } }
    @Published var soundPack: String { didSet { defaults.set(soundPack, forKey: "soundPack") } }
    @Published var quietHoursEnabled: Bool { didSet { defaults.set(quietHoursEnabled, forKey: "quietHoursEnabled") } }
    @Published var quietStart: Int { didSet { defaults.set(quietStart, forKey: "quietStart") } }
    @Published var quietEnd: Int { didSet { defaults.set(quietEnd, forKey: "quietEnd") } }

    @Published private(set) var launchAtLogin = false
    @Published private(set) var launchAtLoginError: String?

    /// Earlier builds used other identifiers (a placeholder, then the Crow's Nest name). Carry those
    /// preferences over once.
    static func migrateFromOldIdentifier(into defaults: UserDefaults = .standard) {
        // Only the real app: test and snapshot runs would otherwise take the user's preferences.
        guard defaults === UserDefaults.standard, Bundle.main.bundleIdentifier == "io.github.goodguyej.ravenisland",
              defaults.object(forKey: "migratedFromEarlierNames") == nil else { return }
        defaults.set(true, forKey: "migratedFromEarlierNames")
        for old in ["io.github.goodguyej.crowsnest", "local.crowsnest.app"] where Bundle.main.bundleIdentifier != old {
            guard let previous = defaults.persistentDomain(forName: old) else { continue }
            for (key, value) in previous where defaults.object(forKey: key) == nil { defaults.set(value, forKey: key) }
            defaults.removePersistentDomain(forName: old)
        }
    }

    init(defaults: UserDefaults = .standard) {
        Self.migrateFromOldIdentifier(into: defaults)
        self.defaults = defaults
        defaults.register(defaults: [
            "autoExpand": true, "answersFromPanel": true, "shortcutsEnabled": true,
            "showCharacters": true, "strollWhenIdle": true, "rotateNotchDetails": false, "displayMode": "auto", "hideFromScreenSharing": true,
            "autoClearMinutes": 5, "clearOnJump": true,
            "soundsEnabled": false, "volume": 0.5, "soundPack": Self.builtInPack,
            "quietHoursEnabled": false, "quietStart": 22, "quietEnd": 7,
            "showMusic": true, "spotifyArtwork": false, "showCalendar": false,
            "showTemperatures": false,
        ])
        showTemperatures = defaults.bool(forKey: "showTemperatures")
        showMusic = defaults.bool(forKey: "showMusic")
        spotifyArtwork = defaults.bool(forKey: "spotifyArtwork")
        showCalendar = defaults.bool(forKey: "showCalendar")
        autoExpand = defaults.bool(forKey: "autoExpand")
        answersFromPanel = defaults.bool(forKey: "answersFromPanel")
        shortcutsEnabled = defaults.bool(forKey: "shortcutsEnabled")
        setupDeferred = defaults.bool(forKey: "setupDeferred")
        showCharacters = defaults.bool(forKey: "showCharacters")
        strollWhenIdle = defaults.bool(forKey: "strollWhenIdle")
        rotateNotchDetails = defaults.bool(forKey: "rotateNotchDetails")
        displayMode = defaults.string(forKey: "displayMode") ?? "auto"
        hideFromScreenSharing = defaults.bool(forKey: "hideFromScreenSharing")
        autoClearMinutes = defaults.integer(forKey: "autoClearMinutes")
        clearOnJump = defaults.bool(forKey: "clearOnJump")
        soundsEnabled = defaults.bool(forKey: "soundsEnabled")
        volume = defaults.double(forKey: "volume")
        mutedEvents = Set(defaults.stringArray(forKey: "mutedEvents") ?? [])
        soundPack = defaults.string(forKey: "soundPack") ?? Self.builtInPack
        quietHoursEnabled = defaults.bool(forKey: "quietHoursEnabled")
        quietStart = defaults.integer(forKey: "quietStart")
        quietEnd = defaults.integer(forKey: "quietEnd")
        refreshLaunchAtLogin()
    }

    func isOn(_ event: SoundEvent) -> Bool { !mutedEvents.contains(event.rawValue) }
    func set(_ event: SoundEvent, on: Bool) {
        if on { mutedEvents.remove(event.rawValue) } else { mutedEvents.insert(event.rawValue) }
    }

    var isQuietNow: Bool {
        quietHoursEnabled && QuietHours.isQuiet(hour: Calendar.current.component(.hour, from: Date()),
                                                start: quietStart, end: quietEnd)
    }

    // MARK: Sound packs: folders under ~/.ravenisland/sounds, each holding approval/question/done/error audio files

    static var soundsFolder: URL { AppPaths.root.appendingPathComponent("sounds", isDirectory: true) }

    var availablePacks: [String] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: Self.soundsFolder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        let names = folders.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent).sorted()
        return [Self.builtInPack] + names
    }

    // MARK: Launch at login

    func refreshLaunchAtLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        refreshLaunchAtLogin()
    }
}
