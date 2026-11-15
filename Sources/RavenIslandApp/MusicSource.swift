import AppKit
import SwiftUI
import Combine
import RavenIslandCore

enum MusicCommand {
    case playPause, next, previous

    var verb: String {
        switch self {
        case .playPause: return "playpause"
        case .next: return "next track"
        case .previous: return "previous track"
        }
    }
}

/// What Spotify or Music is playing, read from the notifications both post on every change.
/// Reading needs no permission; controls and artwork use Apple Events and only ever go to a
/// player that is already running, because `tell application id` would launch it.
@MainActor
final class MusicSource: ObservableObject {
    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var artwork: NSImage?
    /// The artwork's colour, made readable on black; nil without artwork.
    @Published private(set) var tint: Color?
    /// False after a control was refused by macOS; the view dims the controls.
    @Published private(set) var controlsAllowed = true

    private let settings: Settings
    private var board = NowPlayingBoard()
    private var subscriptions = Set<AnyCancellable>()
    private var artworkKey: String?
    private let playerObserver = PlayerNotificationObserver()
    private nonisolated static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    init(settings: Settings) {
        self.settings = settings
    }

    func start() {
        playerObserver.onChange = { [weak self] app, info in
            self?.board.update(app, NowPlaying(app: app, userInfo: info, now: Date()),
                               positionReported: info["Playback Position"] != nil)
            self?.publish()
        }
        playerObserver.start()
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                guard let app = MusicApp.allCases.first(where: { $0.bundleID == id }) else { return }
                self?.board.remove(app)
                self?.publish()
            }
            .store(in: &subscriptions)
        // @Published sends before the property changes, so pass the new value through.
        settings.$showMusic.dropFirst().sink { [weak self] on in self?.publish(showMusic: on) }
            .store(in: &subscriptions)
        settings.$spotifyArtwork.dropFirst().sink { [weak self] on in
            self?.artworkKey = nil
            self?.publish(spotifyArtwork: on)
        }
        .store(in: &subscriptions)
        loadInitialState()
    }

    func send(_ command: MusicCommand) {
        guard let app = nowPlaying?.app, Self.isRunning(app) else { return }
        let script = "tell application id \"\(app.bundleID)\" to \(command.verb)"
        DispatchQueue.global(qos: .userInitiated).async {
            // Long enough for the user to answer the Automation prompt the first click brings up.
            let ok = Jumper.run("/usr/bin/osascript", ["-e", script], timeout: 60) != nil
            DispatchQueue.main.async { [weak self] in self?.controlsAllowed = ok }
        }
    }

    func activatePlayer() {
        guard let app = nowPlaying?.app else { return }
        NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).first?.activate()
    }

    private func publish(showMusic: Bool? = nil, spotifyArtwork: Bool? = nil) {
        let value = (showMusic ?? settings.showMusic) ? board.current : nil
        if value != nowPlaying { nowPlaying = value }
        updateArtwork(spotifyArtwork: spotifyArtwork ?? settings.spotifyArtwork)
    }

    // MARK: Apple Events

    private static func isRunning(_ app: MusicApp) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty
    }

    /// Never asks: a prompt may only follow the user's own click.
    private nonisolated static func automationGranted(_ app: MusicApp) -> Bool {
        guard let target = NSAppleEventDescriptor(bundleIdentifier: app.bundleID).aeDesc else { return false }
        return AEDeterminePermissionToAutomateTarget(target, typeWildCard, typeWildCard, false) == noErr
    }

    private nonisolated static let separator = "\u{1F}"

    private static func stateScript(_ app: MusicApp) -> String {
        let duration = app == .spotify ? "duration of t" : "round ((duration of t) * 1000)"
        let id = app == .spotify ? "id of t" : "persistent ID of t"
        return """
        tell application id "\(app.bundleID)"
            if player state is stopped then return ""
            set t to current track
            set s to ASCII character 31
            return (player state as text) & s & (name of t) & s & (artist of t) & s & (album of t) & s & (\(duration)) & s & (player position) & s & (\(id))
        end tell
        """
    }

    /// Players already running at launch have not posted anything yet; ask them once, if allowed.
    private func loadInitialState() {
        for app in MusicApp.allCases where Self.isRunning(app) {
            let script = Self.stateScript(app)
            DispatchQueue.global(qos: .utility).async {
                guard Self.automationGranted(app),
                      let out = Jumper.run("/usr/bin/osascript", ["-e", script], timeout: 10) else { return }
                let parts = out.trimmingCharacters(in: .newlines).components(separatedBy: Self.separator)
                guard parts.count == 7 else { return }
                let info: [String: Any] = [
                    "Player State": parts[0].capitalized, "Name": parts[1], "Artist": parts[2], "Album": parts[3],
                    app.durationKey: NSNumber(value: Double(parts[4]) ?? 0),
                    "Playback Position": NSNumber(value: Double(parts[5]) ?? 0), app.trackIDKey: parts[6],
                ]
                let value = NowPlaying(app: app, userInfo: info, now: Date())
                DispatchQueue.main.async { [weak self] in
                    guard let self, value != nil else { return }
                    self.board.update(app, value)
                    self.publish()
                }
            }
        }
    }

    // MARK: Artwork

    private func updateArtwork(spotifyArtwork: Bool) {
        let key = nowPlaying.map { "\($0.app.rawValue)|\($0.trackID ?? $0.title)" }
        guard key != artworkKey else { return }
        artworkKey = key
        artwork = nil
        tint = nil
        guard let app = nowPlaying?.app, let key, Self.isRunning(app) else { return }
        if app == .spotify, !spotifyArtwork { return }
        Task.detached(priority: .utility) {
            guard Self.automationGranted(app) else { return }
            let data = app == .appleMusic ? Self.musicArtwork() : await Self.spotifyArtwork()
            await MainActor.run { [weak self] in
                guard let self, self.artworkKey == key, let data else { return }
                let image = NSImage(data: data)
                self.artwork = image
                self.tint = image.flatMap(Self.tint(of:))
            }
        }
    }

    static func tint(of image: NSImage) -> Color? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: 4, height: 4))
        NSGraphicsContext.restoreGraphicsState()
        var sum = (r: 0.0, g: 0.0, b: 0.0)
        for x in 0..<4 { for y in 0..<4 {
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
            sum.r += Double(c.redComponent); sum.g += Double(c.greenComponent); sum.b += Double(c.blueComponent)
        } }
        let c = ArtworkTint.readable(red: sum.r / 16, green: sum.g / 16, blue: sum.b / 16)
        return Color(red: c.red, green: c.green, blue: c.blue)
    }

    /// Raw image data comes back from osascript as «data PNGf89504E…»: a four-letter type, then hex.
    private nonisolated static func musicArtwork() -> Data? {
        let script = "tell application id \"com.apple.Music\" to get raw data of artwork 1 of current track"
        guard let out = Jumper.run("/usr/bin/osascript", ["-e", script], timeout: 10),
              let open = out.range(of: "«data "), let close = out.range(of: "»", range: open.upperBound..<out.endIndex) else { return nil }
        let hex = out[open.upperBound..<close.lowerBound].dropFirst(4)
        guard hex.count <= 2 * ArtworkPolicy.maxBytes, hex.count % 2 == 0 else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }

    private nonisolated static func spotifyArtwork() async -> Data? {
        let script = "tell application id \"com.spotify.client\" to get artwork url of current track"
        guard let out = Jumper.run("/usr/bin/osascript", ["-e", script], timeout: 10),
              let url = URL(string: out.trimmingCharacters(in: .whitespacesAndNewlines)), ArtworkPolicy.allows(url) else { return nil }
        do {
            let (bytes, response) = try await session.bytes(for: URLRequest(url: url), delegate: SameHostOnly())
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, let final = http.url,
                  ArtworkPolicy.allows(final), http.expectedContentLength <= ArtworkPolicy.maxBytes else { return nil }
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > ArtworkPolicy.maxBytes { return nil }
            }
            return data
        } catch {
            return nil
        }
    }
}

/// NSApplication suspends distributed notifications while the app is inactive, which for a
/// menu bar app is nearly always; the block-based API cannot opt out, so this uses selectors.
@MainActor
private final class PlayerNotificationObserver: NSObject {
    var onChange: (MusicApp, [String: Any]) -> Void = { _, _ in }

    func start() {
        for app in MusicApp.allCases {
            DistributedNotificationCenter.default().addObserver(self, selector: #selector(received(_:)),
                                                                name: Notification.Name(app.notificationName), object: nil,
                                                                suspensionBehavior: .deliverImmediately)
        }
    }

    @objc private func received(_ note: Notification) {
        guard let app = MusicApp.allCases.first(where: { $0.notificationName == note.name.rawValue }) else { return }
        onChange(app, note.userInfo as? [String: Any] ?? [:])
    }
}

/// Refuses any redirect that would leave Spotify's image host.
private final class SameHostOnly: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        request.url.map(ArtworkPolicy.allows) == true ? request : nil
    }
}
