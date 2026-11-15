# Idle Home (Music + Calendar) Implementation Plan

> **For agentic workers:** run this plan inline, task by task, in one session on branch
> `feat/idle-home`. Do not use `superpowers:executing-plans` or
> `superpowers:subagent-driven-development`. **Never commit or push**: each task ends at a
> checkpoint where you report the diff; the owner approves commits. Steps use checkbox
> (`- [ ]`) syntax for tracking.

**Goal:** With no Claude Code sessions running, the notch shows what is playing in Spotify
or Apple Music and the next calendar events, in place of the idle ravens.

**Architecture:** Pure value types and rules (`NowPlaying`, `Agenda`, `IdleHome`,
`ArtworkPolicy`) live in `RavenIslandCore` and are unit-tested. Two observable sources in
`RavenIslandApp` (`MusicSource`, `CalendarSource`) feed them; `NotchController` copies an
`IdleHome` summary into `NotchGeometry` so the window size and the SwiftUI views agree.
Nothing in the approval path (`AppModel` requests, socket, bridge, hot keys) changes.

**Tech Stack:** Swift 6 toolchain in Swift 5 language mode, SwiftPM, SwiftUI + AppKit,
EventKit, DistributedNotificationCenter, Apple Events via `/usr/bin/osascript`, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-15-idle-home-design.md` (section 5 is this plan;
section 6 is later phases and is out of scope). Read it before starting.

## Global Constraints

- macOS 14 minimum; no new package dependencies; no private APIs.
- `RavenIslandCore` imports Foundation only (no AppKit, no EventKit).
- No code or assets from boring.notch (GPL-3.0). Original work only.
- Idle home renders only when `sessions.isEmpty` and nothing is pending. No code path with
  sessions may change behaviour.
- Nothing in this feature calls `NotchController.expand()` or plays a sound.
- No permission prompt unless the user clicked a control or switched a setting on.
- Track and event titles: shown through `TextSafety.visible`, capped at 200 characters,
  never written to disk, `AppModel.log`, or `Diagnostics.report`.
- Scripts sent to players are fixed strings; nothing from a notification is placed in one.
- Network: only the Spotify artwork fetch, only when `spotifyArtwork` is on, HTTPS, host
  exactly `i.scdn.co`, at most 2,000,000 bytes, ephemeral session.
- Settings keys and defaults: `showMusic` true, `showCalendar` false, `spotifyArtwork` false.
- Idle home height 96pt. Collapsed look-ahead 60 minutes. At most 3 agenda rows.
- Wing width stays 38pt; up to 48pt is allowed if "10:30" does not fit. Beyond that, stop
  and ask the owner.
- Comments: none unless the why is non-obvious. No commented-out code.
- Commands: unit tests `./scripts/test.sh`; one suite `./scripts/test.sh --filter <Suite>`;
  build `swift build`; bundle `./scripts/build-app.sh`; end-to-end `python3 scripts/e2e.py`;
  snapshots `"build/Raven Island.app/Contents/MacOS/Raven Island" --snapshot build/snapshots`.

## Review Focus

1. A notification with a 10,000-character or control-character title: the panel shows a
   capped, visibly-marked string and does not grow. (Task 1)
2. Both players running, one paused and one playing, then the playing one quits: the
   paused one is shown, not a stale track. (Task 1, `NowPlayingBoard`)
3. A track with no duration or duration 0 (ads, some podcasts): no progress bar, no
   division by zero. (Task 1)
4. An event that started yesterday and is still running, and one that crosses midnight:
   the first shows as "now", the second is listed today. (Task 2)
5. A redirect or look-alike host on the artwork address (`i.scdn.co.example.com`, `http:`,
   a port, user info): refused. (Task 3)

Not unit-testable, covered by the hand checks in Task 9: a session starting or an approval
arriving while the idle home is open; Calendar access revoked while the app runs.

## File Map

| File | Responsibility |
|---|---|
| `Sources/RavenIslandCore/NowPlaying.swift` (new) | `MusicApp`, `NowPlaying`, payload parsing, `NowPlayingBoard` |
| `Sources/RavenIslandCore/Agenda.swift` (new) | `AgendaEvent`, `Agenda` selection, labels, next boundary |
| `Sources/RavenIslandCore/IdleHome.swift` (new) | `IdleHome` summary, `ArtworkPolicy` |
| `Sources/RavenIslandApp/MusicSource.swift` (new) | Notification listeners, controls, artwork |
| `Sources/RavenIslandApp/CalendarSource.swift` (new) | EventKit access and refresh |
| `Sources/RavenIslandApp/IdleHomeView.swift` (new) | Wing views and the open-panel idle home |
| `NotchGeometry.swift`, `NotchView.swift`, `NotchController.swift`, `main.swift` | Sizing and wiring |
| `Settings.swift`, `SettingsView.swift`, `Diagnostics.swift`, `Snapshot.swift` | Settings, report, snapshots |
| `scripts/build-app.sh`, `scripts/uninstall.sh`, `AppModel.uninstallIntegration` | Usage strings, grant reset |
| `README.md`, `docs/SPEC.md`, `docs/SECURITY-REVIEW.md`, `docs/PLAN.md`, `CHANGELOG.md` | Docs |

---

### Task 0: Spike the four unknowns (spec 5.7)

Throwaway; nothing from it is kept in `Sources/`. Needs the owner at the Mac for a minute.

- [ ] **Step 1:** In the session scratch directory, write a Swift script that subscribes to
  `com.spotify.client.PlaybackStateChanged` and `com.apple.Music.playerInfo` on
  `DistributedNotificationCenter.default()` and prints each `userInfo` key with its Swift type.
  Ask the owner to play, pause and skip in each player. Record key names, types and units.
- [ ] **Step 2:** With the owner's OK for the Automation prompt, run
  `osascript -e 'tell application id "com.apple.Music" to get raw data of artwork 1 of current track'`
  for a library track and a streamed track; record what comes back. Same for
  `tell application id "com.spotify.client" to get artwork url of current track`.
- [ ] **Step 3:** Render `Text("10:30")` at 11pt semibold monospaced-digit and measure its
  width against 38pt (a five-line `NSAttributedString.size()` check is enough).
- [ ] **Step 4:** Write the findings under spec section 5.7 as "Spike results (date)". If a
  key or unit differs from Task 1's table, change Task 1's table and tests to match before
  starting it. The Calendar prompt question is answered in Task 5.

**Checkpoint:** report findings; no code.

---

### Task 1: `NowPlaying` and `NowPlayingBoard` (Core)

**Files:**
- Create: `Sources/RavenIslandCore/NowPlaying.swift`
- Test: `Tests/RavenIslandCoreTests/NowPlayingTests.swift`

**Interfaces — Produces:**

```swift
public enum MusicApp: String, Sendable, CaseIterable {
    case spotify, appleMusic
    public var bundleID: String          // "com.spotify.client", "com.apple.Music"
    public var notificationName: String  // "com.spotify.client.PlaybackStateChanged", "com.apple.Music.playerInfo"
    public var displayName: String       // "Spotify", "Music"
}

public struct NowPlaying: Equatable, Sendable {
    public var app: MusicApp
    public var title: String
    public var artist: String
    public var album: String
    public var isPlaying: Bool
    public var duration: TimeInterval?   // nil when missing or <= 0
    public var position: TimeInterval    // at `asOf`
    public var asOf: Date
    public var trackID: String?
    public static let maxTextLength = 200
    /// nil when the payload says stopped, or has no usable title.
    public init?(app: MusicApp, userInfo: [String: Any], now: Date)
    public func position(at date: Date) -> TimeInterval   // advances only while playing; clamped to 0...duration
    public func progress(at date: Date) -> Double?        // 0...1, nil without a duration
}

public struct NowPlayingBoard: Equatable, Sendable {
    public init()
    public mutating func update(_ app: MusicApp, _ value: NowPlaying?)   // nil = that player stopped
    public mutating func remove(_ app: MusicApp)                         // player quit
    /// A playing track beats a paused one; among equals the latest `asOf` wins.
    public var current: NowPlaying? { get }
}
```

Payload keys (adjust to the Task 0 findings):

| Field | Spotify | Apple Music |
|---|---|---|
| state | `"Player State"`: `"Playing"`, `"Paused"`, `"Stopped"` | same |
| title / artist / album | `"Name"`, `"Artist"`, `"Album"` | same |
| duration | `"Duration"`, milliseconds | `"Total Time"`, milliseconds |
| position | `"Playback Position"`, seconds | absent → 0 |
| track id | `"Track ID"` (String) | `"PersistentID"` (number → String) |

Numbers may arrive as `Int`, `Double` or `NSNumber`; accept all three.

- [ ] **Step 1: Write the failing tests** in `@Suite struct NowPlayingTests` with
  `let now = Date(timeIntervalSince1970: 1_800_000_000)`:

```swift
@Test func parsesSpotify() {
    let n = NowPlaying(app: .spotify, userInfo: ["Player State": "Playing", "Name": "Song", "Artist": "Band",
        "Album": "LP", "Duration": 215_000, "Playback Position": 12.5, "Track ID": "spotify:track:abc"], now: now)
    #expect(n == NowPlaying(app: .spotify, title: "Song", artist: "Band", album: "LP", isPlaying: true,
                            duration: 215, position: 12.5, asOf: now, trackID: "spotify:track:abc"))
}
@Test func parsesAppleMusicPaused() {
    let n = NowPlaying(app: .appleMusic, userInfo: ["Player State": "Paused", "Name": "Tune", "Artist": "Solo",
        "Total Time": NSNumber(value: 180_000), "PersistentID": NSNumber(value: 42)], now: now)
    #expect(n?.isPlaying == false); #expect(n?.duration == 180); #expect(n?.position == 0)
    #expect(n?.album == ""); #expect(n?.trackID == "42")
}
@Test func stoppedOrUntitledIsNil() {
    #expect(NowPlaying(app: .spotify, userInfo: ["Player State": "Stopped", "Name": "Song"], now: now) == nil)
    #expect(NowPlaying(app: .spotify, userInfo: ["Player State": "Playing"], now: now) == nil)
    #expect(NowPlaying(app: .spotify, userInfo: ["Player State": "Playing", "Name": "   "], now: now) == nil)
    #expect(NowPlaying(app: .spotify, userInfo: ["Player State": 7, "Name": ["x"]], now: now) == nil)
    #expect(NowPlaying(app: .spotify, userInfo: [:], now: now) == nil)
}
@Test func capsLongText() {
    let n = NowPlaying(app: .spotify, userInfo: ["Player State": "Playing", "Name": String(repeating: "a", count: 10_000),
        "Artist": String(repeating: "b", count: 10_000)], now: now)
    #expect(n?.title.count == 200); #expect(n?.artist.count == 200)
}
@Test func zeroDurationHasNoProgress() {
    let n = NowPlaying(app: .spotify, userInfo: ["Player State": "Playing", "Name": "Ad", "Duration": 0], now: now)
    #expect(n?.duration == nil); #expect(n?.progress(at: now + 30) == nil)
}
@Test func positionAdvancesOnlyWhilePlayingAndClamps() {
    var n = NowPlaying(app: .spotify, title: "S", artist: "", album: "", isPlaying: true, duration: 100, position: 90, asOf: now, trackID: nil)
    #expect(n.position(at: now + 5) == 95); #expect(n.position(at: now + 60) == 100)
    #expect(n.position(at: now - 500) == 0); #expect(n.progress(at: now + 5) == 0.95)
    n.isPlaying = false
    #expect(n.position(at: now + 60) == 90)
}
@Test func boardPrefersPlayingThenLatest() {
    func track(_ app: MusicApp, playing: Bool, at offset: TimeInterval) -> NowPlaying {
        NowPlaying(app: app, title: app.rawValue, artist: "", album: "", isPlaying: playing, duration: nil, position: 0, asOf: now + offset, trackID: nil)
    }
    var board = NowPlayingBoard()
    #expect(board.current == nil)
    board.update(.spotify, track(.spotify, playing: false, at: 10))
    board.update(.appleMusic, track(.appleMusic, playing: true, at: 0))
    #expect(board.current?.app == .appleMusic)          // playing beats a later pause
    board.update(.spotify, track(.spotify, playing: true, at: 20))
    #expect(board.current?.app == .spotify)             // both playing: latest wins
    board.remove(.spotify)
    #expect(board.current?.app == .appleMusic)
    board.update(.appleMusic, nil)
    #expect(board.current == nil)
}
```

  The memberwise `NowPlaying(app:title:…)` initializer used above must be `public`.
- [ ] **Step 2:** `./scripts/test.sh --filter NowPlayingTests` → fails to compile (`NowPlaying` undefined).
- [ ] **Step 3:** Implement the file to the interface above. Trim whitespace before the
  empty-title check; cap with `String.prefix(maxTextLength)`.
- [ ] **Step 4:** `./scripts/test.sh --filter NowPlayingTests` → all pass. `./scripts/test.sh` → all pass.

**Checkpoint:** report; no commit.

---

### Task 2: `Agenda` (Core)

**Files:**
- Create: `Sources/RavenIslandCore/Agenda.swift`
- Test: `Tests/RavenIslandCoreTests/AgendaTests.swift`

**Interfaces — Produces:**

```swift
public struct AgendaEvent: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String      // capped at NowPlaying.maxTextLength by the initializer
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var isDeclined: Bool
    public var isCancelled: Bool
    public init(id: String, title: String, start: Date, end: Date,
                isAllDay: Bool = false, isDeclined: Bool = false, isCancelled: Bool = false)
    public func isRunning(at now: Date) -> Bool   // start <= now < end
}

public enum Agenda {
    public static let maxRows = 3
    public static let collapsedLookAhead: TimeInterval = 3600
    /// Timed, not declined, not cancelled, end > now, start before tomorrow's midnight; by start; at most maxRows.
    public static func remainingToday(_ events: [AgendaEvent], now: Date, calendar: Calendar) -> [AgendaEvent]
    /// "now" while the first remaining event is running; its start time once within collapsedLookAhead; else nil.
    public static func collapsedLabel(_ events: [AgendaEvent], now: Date, calendar: Calendar, locale: Locale) -> String?
    /// Short time in the locale's 12/24-hour style, without seconds.
    public static func timeLabel(_ date: Date, calendar: Calendar, locale: Locale) -> String
    /// The next moment the output of the two functions above can change: the earliest, after now, of
    /// (start - collapsedLookAhead), start, and end over all qualifying events, and tomorrow's midnight.
    public static func nextBoundary(_ events: [AgendaEvent], now: Date, calendar: Calendar) -> Date
}
```

- [ ] **Step 1: Write the failing tests** in `@Suite struct AgendaTests`. Fixture: a
  Gregorian `Calendar` with `timeZone = TimeZone(identifier: "UTC")!`,
  `locale = Locale(identifier: "en_GB")`, `midnight = Date(timeIntervalSince1970: 1_800_000_000 - 1_800_000_000 % 86_400)`,
  `func at(_ h: Double) -> Date { midnight + h * 3600 }`,
  `func ev(_ id: String, _ from: Double, _ to: Double, …flags) -> AgendaEvent`. Tests and assertions:

  - `selectsRemainingTimedEvents`: events `a` 8–9, `b` 10–11, `c` 13–14, `d` 15–16, `e` 17–18,
    all-day `f`, declined `g` 12–13, cancelled `h` 12–13; `now = at(9.5)` →
    ids `["b", "c", "d"]`.
  - `runningEventIsIncludedAndEndedIsNot`: `a` 9–10, `now = at(9.5)` → `["a"]`; `now = at(10)` → `[]`.
  - `startedYesterdayStillRunning`: event −2…1 (hours from midnight), `now = at(0.5)` → included,
    `collapsedLabel == "now"`.
  - `crossesMidnightListedToday`: event 23–25, `now = at(20)` → included; an event 24.5–26 → not included.
  - `collapsedLabelWindow`: `b` 10:30–11; `now = at(9)` → `nil`; `now = at(9.5)` → `"10:30"`;
    `now = at(10.75)` → `"now"`; `now = at(11)` → `nil`.
  - `timeLabelFollowsLocale`: `at(15.5)` with `en_GB` → `"15:30"`; with `en_US` the label
    contains `"3:30"` and `"PM"`.
  - `nextBoundary`: `b` 10:30–11; from `at(8)` → `at(9.5)`; from `at(9.5)` → `at(10.5)`;
    from `at(10.5)` → `at(11)`; from `at(11)` → `at(24)`. With no events from `at(8)` → `at(24)`.
  - `capsTitle`: a 10,000-character title → `title.count == 200`.
- [ ] **Step 2:** `./scripts/test.sh --filter AgendaTests` → fails to compile.
- [ ] **Step 3:** Implement. `timeLabel` uses `Date.FormatStyle(date: .omitted, time: .shortened)`
  with the given locale and the calendar's time zone.
- [ ] **Step 4:** `./scripts/test.sh` → all pass.

**Checkpoint:** report; no commit.

---

### Task 3: `IdleHome` and `ArtworkPolicy` (Core)

**Files:**
- Create: `Sources/RavenIslandCore/IdleHome.swift`
- Test: `Tests/RavenIslandCoreTests/IdleHomeTests.swift`

**Interfaces — Produces:**

```swift
public struct IdleHome: Equatable, Sendable {
    public var hasTrack: Bool           // a track is known, playing or paused
    public var isPlaying: Bool
    public var agendaOn: Bool           // calendar switched on and access granted
    public var agendaRows: Int
    public var collapsedLabel: String?
    public static let none: IdleHome    // all false / 0 / nil
    public init(nowPlaying: NowPlaying?, showMusic: Bool, agenda: [AgendaEvent], collapsedLabel: String?, agendaOn: Bool)
    public var showsPanel: Bool { get }          // hasTrack || agendaRows > 0
    public var showsAgendaHalf: Bool { get }     // showsPanel && agendaOn
    public var hasCollapsedContent: Bool { get } // hasTrack || collapsedLabel != nil
}

public enum ArtworkPolicy {
    public static let maxBytes = 2_000_000
    public static let host = "i.scdn.co"
    public static func allows(_ url: URL) -> Bool   // https, host == host exactly, no port, no user, no password
}
```

`init` rules: `showMusic == false` → `hasTrack` and `isPlaying` false. `agendaOn == false` →
`agendaRows` 0 and `collapsedLabel` nil regardless of the arguments.

- [ ] **Step 1: Write the failing tests** in `@Suite struct IdleHomeTests`:
  - `noneShowsNothing`: `IdleHome.none.showsPanel`, `.showsAgendaHalf`, `.hasCollapsedContent` all false.
  - `trackOnly`: a paused track, `agendaOn: false` → `showsPanel`, `hasCollapsedContent` true;
    `showsAgendaHalf` false; `isPlaying` false.
  - `musicSwitchedOffHidesTrack`: a playing track with `showMusic: false`, no agenda → equals `.none`.
  - `agendaGrantedButEmptyIsNotContent`: no track, `agendaOn: true`, no events → `showsPanel` false.
  - `agendaGrantedEmptyWithTrackShowsHalf`: track, `agendaOn: true`, no events → `showsAgendaHalf` true, `agendaRows == 0`.
  - `agendaOffIgnoresEvents`: one event and label `"10:30"` with `agendaOn: false` → `agendaRows == 0`, `collapsedLabel == nil`.
  - `artworkPolicy`: allows `https://i.scdn.co/image/ab67616d0000b273abc`; refuses
    `http://i.scdn.co/image/x`, `https://i.scdn.co.example.com/x`, `https://example.com/i.scdn.co`,
    `https://i.scdn.co:8443/x`, `https://user:pw@i.scdn.co/x`, `https://I.SCDN.CO.evil/x`, `file:///tmp/x`.
- [ ] **Step 2:** `./scripts/test.sh --filter IdleHomeTests` → fails to compile.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `./scripts/test.sh` → all pass.

**Checkpoint:** report; no commit.

---

### Task 4: `MusicSource` (App)

**Files:**
- Create: `Sources/RavenIslandApp/MusicSource.swift`
- Modify: `Sources/RavenIslandApp/Settings.swift`, `Sources/RavenIslandApp/Jumper.swift`

**Interfaces — Consumes:** `MusicApp`, `NowPlaying`, `NowPlayingBoard`, `ArtworkPolicy` (Tasks 1, 3).

**Produces:**

```swift
enum MusicCommand { case playPause, next, previous }

@MainActor final class MusicSource: ObservableObject {
    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var artwork: NSImage?
    /// False after a control was refused by macOS; the view dims the controls.
    @Published private(set) var controlsAllowed = true
    init(settings: Settings)
    func start()
    func send(_ command: MusicCommand)   // to nowPlaying's app; no-op without a track
    func activatePlayer()                // bring nowPlaying's app forward; never launches one
}
```

`Settings` gains `@Published var showMusic: Bool` (key `showMusic`, default `true`) and
`@Published var spotifyArtwork: Bool` (key `spotifyArtwork`, default `false`), following the
existing property pattern.

- [ ] **Step 1:** In `Jumper.swift`, change `run(_:_:timeout:)` from `private` to internal so
  `MusicSource` reuses it. No other change there.
- [ ] **Step 2:** Add the two settings to `Settings.swift` (property, `register(defaults:)`, `init`).
- [ ] **Step 3:** Implement `MusicSource`:
  - `start()`: for each `MusicApp`, observe `notificationName` on
    `DistributedNotificationCenter.default()`; on receipt, on the main actor, build
    `NowPlaying(app:userInfo:now:)` from `notification.userInfo as? [String: Any] ?? [:]` and
    `board.update`. Observe `NSWorkspace.didTerminateApplicationNotification` and call
    `board.remove` for a matching `bundleID`. After every change set
    `nowPlaying = settings.showMusic ? board.current : nil`; also recompute when
    `settings.$showMusic` changes.
  - Initial state: for each player already running
    (`NSRunningApplication.runningApplications(withBundleIdentifier:)`), only if
    `AEDeterminePermissionToAutomateTarget` (ask = false) returns `noErr`, query state with one
    fixed script and feed the result through the same `NowPlaying` initializer by building the
    same dictionary shape. Skip silently otherwise.
  - Fixed scripts, addressed by bundle identifier, sent with `Jumper.run("/usr/bin/osascript", ["-e", …])`
    off the main thread: `tell application id "<bundleID>" to playpause`, `… to next track`,
    `… to previous track`. A nil result sets `controlsAllowed = false`; a success sets it true.
  - Artwork: when `nowPlaying?.trackID` changes, clear `artwork`, then:
    Apple Music → read `raw data of artwork 1 of current track` (in-process `NSAppleScript`
    off the main thread, per the Task 0 finding), only when Automation is already granted;
    Spotify → only when `settings.spotifyArtwork`, get `artwork url of current track`, require
    `ArtworkPolicy.allows`, fetch with `URLSession(configuration: .ephemeral)`, reject a response
    whose final URL fails `ArtworkPolicy.allows` or whose body exceeds `ArtworkPolicy.maxBytes`.
    Discard the result if the track changed while loading.
- [ ] **Step 4:** `swift build` → succeeds. `./scripts/test.sh` → all pass.

**Checkpoint:** report; no commit.

---

### Task 5: `CalendarSource` (App)

**Files:**
- Create: `Sources/RavenIslandApp/CalendarSource.swift`
- Modify: `Sources/RavenIslandApp/Settings.swift`, `scripts/build-app.sh`

**Interfaces — Consumes:** `AgendaEvent`, `Agenda` (Task 2).

**Produces:**

```swift
enum CalendarAccess { case notAsked, granted, denied }

@MainActor final class CalendarSource: ObservableObject {
    @Published private(set) var events: [AgendaEvent] = []     // Agenda.remainingToday
    @Published private(set) var collapsedLabel: String?        // Agenda.collapsedLabel
    @Published private(set) var access: CalendarAccess
    init(settings: Settings)
    func start()
    func requestAccess()   // called only from the Settings toggle
}
```

`Settings` gains `@Published var showCalendar: Bool` (key `showCalendar`, default `false`).

- [ ] **Step 1:** Add `showCalendar` to `Settings.swift`.
- [ ] **Step 2:** In `scripts/build-app.sh` Info.plist, add
  `<key>NSCalendarsFullAccessUsageDescription</key><string>Raven Island shows today's remaining events beside the notch when no agent is running. It only reads them.</string>`
  and change the `NSAppleEventsUsageDescription` string to
  `Raven Island asks your terminal app to bring the right tab to the front, and Spotify or Music to play, pause, and skip.`
- [ ] **Step 3:** Implement `CalendarSource`:
  - `access` from `EKEventStore.authorizationStatus(for: .event)`: `.fullAccess` → `.granted`,
    `.notDetermined` → `.notAsked`, everything else (including `.writeOnly`) → `.denied`.
  - `requestAccess()`: `requestFullAccessToEvents`, then update `access` and refresh.
  - Refresh (only when `settings.showCalendar` and `.granted`; otherwise publish empty and nil):
    fetch events from now's start of day to the following midnight, map each `EKEvent` to
    `AgendaEvent` (`isDeclined`: the current user's participant status is `.declined`;
    `isCancelled`: `status == .canceled`), publish `Agenda.remainingToday` and
    `Agenda.collapsedLabel` with `Calendar.current` / `Locale.current`.
  - Triggers: `.EKEventStoreChanged`, `NSWorkspace.didWakeNotification`,
    `settings.$showCalendar`, and one timer re-armed after each refresh for
    `Agenda.nextBoundary`. No repeating timer.
- [ ] **Step 4:** `swift build` → succeeds. `./scripts/test.sh` → all pass.
- [ ] **Step 5:** Record under spec 5.7 whether the Calendar prompt appears for the built
  bundle and whether the grant survives `./scripts/dev.sh` (checked by hand in Task 9).

**Checkpoint:** report; no commit.

---

### Task 6: Geometry, views, wiring

**Files:**
- Create: `Sources/RavenIslandApp/IdleHomeView.swift`
- Modify: `NotchGeometry.swift`, `NotchView.swift`, `NotchController.swift`, `main.swift`,
  `Snapshot.swift` (all under `Sources/RavenIslandApp/`)

**Interfaces — Consumes:** `IdleHome` (Task 3), `MusicSource`, `MusicCommand` (Task 4),
`CalendarSource` (Task 5).

**Produces:**

```swift
// NotchGeometry
var idleHome = IdleHome.none
static let idleHomeHeight: CGFloat = 96

// IdleHomeView.swift
struct IdleMusicWing: View { var artwork: NSImage?; var playing: Bool; var size: CGFloat; var animated: Bool }
struct IdleAgendaWing: View { var label: String }
struct IdleHomePanel: View {
    var idleHome: IdleHome
    var nowPlaying: NowPlaying?
    var artwork: NSImage?
    var controlsAllowed: Bool
    var agenda: [AgendaEvent]
    var width: CGFloat
    var animated: Bool
    var onMusic: (MusicCommand) -> Void
    var onOpenPlayer: () -> Void
    var onOpenCalendar: () -> Void
}

// NotchContentView: new stored properties, all defaulted so existing call sites compile
var nowPlaying: NowPlaying? = nil
var artwork: NSImage? = nil
var controlsAllowed = true
var agenda: [AgendaEvent] = []
var onMusic: (MusicCommand) -> Void = { _ in }
var onOpenPlayer: () -> Void = {}
var onOpenCalendar: () -> Void = {}
```

Every `idleHome` use below applies only when `sessionCount == 0`.

- [ ] **Step 0: Baseline.** Before touching any view: `./scripts/build-app.sh`, then
  `"build/Raven Island.app/Contents/MacOS/Raven Island" --snapshot build/snapshots-before`.
- [ ] **Step 1: Snapshot cases first.** In `Snapshot.write`, add an `IdleHome` and fixtures
  (a `NowPlaying` titled "Night Drive" by "The Sample Band", three `AgendaEvent`s "Standup",
  "Planning", "Review", a generated solid-colour `NSImage` as artwork) and these cases, each
  rendered for the notch geometry, plus the first also for the pill: `11-idle-both-expanded`,
  `11b-idle-both-collapsed`, `12-idle-music-only-expanded`, `13-idle-calendar-only-expanded`,
  `13b-idle-calendar-only-collapsed`, `14-idle-track-paused-nothing-else-today`,
  `15-idle-controls-denied`, `16-idle-stroll-off-music-collapsed` (geometry with
  `idleStroll: false`). Extend the `cases` tuple or add a second loop; keep existing names
  and output unchanged.
- [ ] **Step 2:** `swift build` → fails (new `NotchContentView` parameters and
  `NotchGeometry.idleHome` do not exist).
- [ ] **Step 3: `NotchGeometry`.**
  - `earRadius` and `collapsedSize`: where they test `idleStroll`, test
    `idleStroll || idleHome.hasCollapsedContent`. Pill width with idle content: 96.
  - `expandedSize`, `sessionCount == 0`: `idleHome.showsPanel ? Self.idleHomeHeight : (crewStage ? CrewStage.height : Self.rowHeight)`.
- [ ] **Step 4: `IdleHomeView.swift`.**
  - `IdleMusicWing`: artwork (or `music.note` glyph) in a rounded square of `size`, then three
    2pt bars that animate while `playing && animated` and rest at fixed heights otherwise.
  - `IdleAgendaWing`: the label, 11pt semibold monospaced-digit, `.white.opacity(0.85)`,
    `lineLimit(1)`, `minimumScaleFactor(0.8)`.
  - `IdleHomePanel`: height `NotchGeometry.idleHomeHeight`. Music half: artwork 56pt, title
    (13pt semibold) and artist (11.5pt, 0.58 opacity) through `TextSafety.visible`, one line
    each; previous / play-pause / next as `HeaderIconButton`-style buttons (`backward.fill`,
    `play.fill` or `pause.fill`, `forward.fill`), dimmed and `.help("Allow Raven Island to
    control this app in System Settings → Privacy & Security → Automation")` when
    `!controlsAllowed`; a 3pt progress capsule inside `TimelineView(.periodic(from: .now, by: 1))`
    using `progress(at:)`, hidden when nil. Artwork and title tap → `onOpenPlayer`.
    Agenda half (only when `idleHome.showsAgendaHalf`): "Today" caption, then rows of
    `Agenda.timeLabel` (or "now" for a running event, in `SessionState.working.color`) and
    title; zero rows → "Nothing else today" at 0.5 opacity. Row tap → `onOpenCalendar`.
    A 1pt divider at 0.12 opacity between halves. A single half takes the full width.
    Accessibility: each control has a label; each agenda row combines its children.
- [ ] **Step 5: `NotchView`.**
  - `collapsedBody`, first branch condition becomes
    `sessions.isEmpty, geometry.idleStroll || geometry.idleHome.hasCollapsedContent`. Left
    slot: `IdleMusicWing` when `geometry.idleHome.hasTrack`, else the existing `Stroller` when
    `geometry.idleStroll`, else `Color.clear`. Right slot: `IdleAgendaWing` when
    `geometry.idleHome.collapsedLabel != nil`, else the existing second `Stroller` when
    `geometry.idleStroll`, else `Color.clear`. Pill: the same two items in an `HStack`.
  - `expandedBody`, empty branch: `geometry.idleHome.showsPanel` → `IdleHomePanel(…)`, before
    the existing `CrewStage` / "No active sessions" branches.
  - `NotchRootView`: take `@ObservedObject var music: MusicSource` and
    `@ObservedObject var calendar: CalendarSource` and pass their values and actions through.
- [ ] **Step 6: `NotchController`.** `init(model:settings:music:calendar:)`. A private
  `idleHome()` builds `IdleHome(nowPlaying: music.nowPlaying, showMusic: settings.showMusic,
  agenda: calendar.events, collapsedLabel: calendar.collapsedLabel,
  agendaOn: settings.showCalendar && calendar.access == .granted)`. Set it wherever
  `crewStage` / `idleStroll` are set (init and `screensChanged`). Subscribe to
  `music.$nowPlaying`, `calendar.$events`, `calendar.$collapsedLabel`, `calendar.$access`,
  `settings.$showMusic`, `settings.$showCalendar`; on change, if the new `IdleHome` differs,
  assign `state.geometry.idleHome` and `applyFrame()`. Growing: frame first. Shrinking while
  expanded: delay `applyFrame()` by 0.45s (0 with Reduce Motion), as the `showAll` sink does.
  Do not call `expand()`.
  `onOpenPlayer` → `music.activatePlayer()`; `onOpenCalendar` →
  `NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))`.
- [ ] **Step 7: `main.swift`.** Create `MusicSource(settings:)` and `CalendarSource(settings:)`
  as `AppDelegate` properties, call `start()` on each after `model.start()` (skip both under
  `--test-mode`), and pass them to `NotchController`.
- [ ] **Step 8:** `swift build` → succeeds. `./scripts/test.sh` → all pass.
  `./scripts/build-app.sh`, then the snapshot command → every new PNG is written, and the
  existing `1-`…`10-` PNGs match the baseline in `build/snapshots-before` (see Step 0).
  Usage countdowns are time-based, so compare the collapsed and non-usage cases with `cmp`
  and the rest by eye.
- [ ] **Step 9:** Read each new PNG. Check: nothing clipped at 96pt, wings symmetric, "10:30"
  readable in the wing (else widen `wing` up to 48 and re-run), stroll-off case has one
  empty wing and no raven.

**Checkpoint:** report with the new PNG paths; no commit.

---

### Task 7: Settings UI, diagnostics, uninstall

**Files:**
- Modify: `Sources/RavenIslandApp/SettingsView.swift`, `Sources/RavenIslandApp/Diagnostics.swift`,
  `Sources/RavenIslandApp/AppModel.swift` (`uninstallIntegration`), `scripts/uninstall.sh`,
  `Sources/RavenIslandApp/main.swift` (pass sources to the settings window and diagnostics)

- [ ] **Step 1: `SettingsView` General tab**, new section after "Panel":

```
Section("When nothing is running") {
    Toggle("Show what's playing in Spotify or Music", isOn: $settings.showMusic)
    Toggle("Load Spotify album art from the internet", isOn: $settings.spotifyArtwork)
        .disabled(!settings.showMusic)
    Text("Off by default. This is the only time Raven Island uses the network.")   // caption, secondary
    Toggle("Show today's events", isOn: <binding>)
    <caption when calendar.access == .denied:>
    "Calendar access is off. Allow it in System Settings → Privacy & Security → Calendars."  + Button("Open System Settings")
}
```

  The calendar binding's setter: set `settings.showCalendar`; when turned on and
  `calendar.access == .notAsked`, call `calendar.requestAccess()`. The button opens
  `x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars`.
- [ ] **Step 2: `Diagnostics.report`**, one line in "Settings:":
  `idle: music=<showMusic> spotifyArtwork=<spotifyArtwork> calendar=<showCalendar> calendarAccess=<notAsked|granted|denied> trackKnown=<bool> eventsToday=<count>`.
  No titles, artists, or event names. `Diagnostics.report` gains `music:` and `calendar:` parameters.
- [ ] **Step 3: Uninstall.** In `scripts/uninstall.sh` and after a successful
  `AppModel.uninstallIntegration()`, run `tccutil reset Calendar io.github.goodguyej.ravenisland`
  and `tccutil reset AppleEvents io.github.goodguyej.ravenisland`, ignoring failures. Read
  `scripts/uninstall.sh` first and place the lines beside the existing preference removal.
- [ ] **Step 4:** `swift build` → succeeds; `./scripts/test.sh` → all pass;
  `python3 scripts/e2e.py` → all checks pass (same count as on `raven-island`).
- [ ] **Step 5:** `"build/Raven Island.app/Contents/MacOS/Raven Island" --settings` after a
  rebuild; confirm the section renders and toggles persist across a relaunch.

**Checkpoint:** report; no commit.

---

### Task 8: Documentation

**Files:** `README.md`, `docs/SPEC.md`, `docs/SECURITY-REVIEW.md`, `docs/PLAN.md`, `CHANGELOG.md`

- [ ] **Step 1: README.** Features: a short "When nothing is running" paragraph with the
  `11-idle-both-expanded` screenshot copied to `docs/screens/`. "What this changes on your
  Mac": Calendar and Automation grants and that uninstall resets them. Replace both "No
  network connections" lines with: "No network connections, with one exception you switch on
  yourself: loading Spotify album art." Requirements: Spotify and Apple Music only.
- [ ] **Step 2: SPEC.** Add `### F15. Idle home` under section 6 summarising spec section 5
  and linking to the design doc; update section 8's "all processing is local" bullets with
  the artwork exception and "titles are never written to disk or the log".
- [ ] **Step 3: SECURITY-REVIEW.** New entry: untrusted inputs added (distributed
  notification payloads from any local process; an image from `i.scdn.co`), the controls
  (length cap, `TextSafety.visible`, fixed scripts, `ArtworkPolicy`, ephemeral session, size
  cap), and what is unverified.
- [ ] **Step 4: PLAN.** Add "Phase 11 — Idle home (music, calendar)" as built, and phases
  12–18 as one table copied from design section 6.
- [ ] **Step 5: CHANGELOG.** One "Added" entry under a new unreleased heading.

**Checkpoint:** report; no commit.

---

### Task 9: Final verification

- [ ] **Step 1:** Run each separately and record exit status: `./scripts/test.sh`,
  `python3 scripts/e2e.py`, `./scripts/build-app.sh`, the snapshot command.
- [ ] **Step 2: Comment hygiene** over this branch's diff (`git diff raven-island`): remove
  comments that restate code; keep only non-obvious whys.
- [ ] **Step 3: Hand checks on the built app** (`./scripts/dev.sh`), with the owner; record
  pass/fail for each:
  1. Spotify: play, pause, skip → wing and panel follow; first control click shows the macOS
     prompt; after Allow the controls work.
  2. Apple Music: the same, plus artwork appears.
  3. Deny Automation for one player → track still shows after a track change; controls dimmed.
  4. Spotify artwork setting off → note glyph and no network request (check with
     `nettop -p $(pgrep -x "Raven Island")` while skipping tracks); on → artwork appears.
  5. Calendar: toggle on → prompt; Allow → events listed; an event inside 60 minutes shows
     its time in the wing; deny path shows the Settings caption.
  6. Start a Claude Code session while the idle home is open → the session list replaces it.
  7. Trigger an approval with no other sessions and music playing → the card appears as today.
  8. Quit the player → the flock returns.
  9. Reduce Motion on → bars and progress do not animate.
  10. A display without a notch → pill shows the two items; panel opens correctly.
  11. `./scripts/dev.sh` again → note whether macOS re-asks for Calendar or Automation.
  12. Export a diagnostic report → contains the `idle:` line and no titles.
- [ ] **Step 4: Review.** Fresh read-only review of the whole branch diff against the design
  doc's sections 2 and 5 and this plan's Global Constraints and Review Focus, given the real
  command output from Step 1. Fix blockers, rerun the affected checks, review again.
- [ ] **Step 5:** Stop. Report files changed, command results, hand-check results, review
  outcome and limitations. Wait for the owner before any commit.
