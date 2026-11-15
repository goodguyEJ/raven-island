# Idle Home Round 3 Implementation Plan

> **For agentic workers:** run this plan inline, task by task, in one session on branch
> `feat/idle-home` (PR goodguyEJ/raven-island#1). Do not use `superpowers:executing-plans` or
> `superpowers:subagent-driven-development`. **No commits or pushes without the owner's
> approval**, except CI fixes under Auto-fix. Each task ends at a checkpoint with real output.

**Goal:** A player badge and artwork-tinted colours on the music half, a spinning record when
there is no artwork, and a clickable six-day week strip in place of the round 2 timeline.

**Architecture:** Day window, per-day selection and the colour adjustment are pure functions
in `RavenIslandCore`, unit-tested. The app target reads the week from EventKit, averages the
artwork into a colour, asks macOS for the player's icon, and draws the views.

**Tech Stack:** Swift 6 toolchain in Swift 5 mode (CI runs Swift 6.1), SwiftPM, SwiftUI + AppKit,
EventKit, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-15-idle-home-design.md`, section 9 (on top of 5 and 8).

## Global Constraints

- All earlier Global Constraints hold (round 1 and round 2 plans).
- Idle home height 96pt; wing 38pt; no new network; no prompt without a click.
- No bundled third-party logos: the badge is the installed app's icon from `NSWorkspace`.
- Six days: two before today, today, three after. At most two event rows, then "+N more".
- Record label colours: Spotify `#1DB954`, Music `#FA2D48`. About one turn per 2 seconds.
- Empty-day copy: "No events today" (today) or "No events" (other days), then "Enjoy your free time!".
- Calendar side counts as content when any of the six days has an event.
- Mixed `CGFloat` / `Double` arithmetic is written with explicit conversions (CI's Swift 6.1
  rejected an ambiguous division in round 2).

## Review Focus

1. A window across the year end (now 30 Dec): days run 28 Dec to 2 Jan in order. (Task 1, `windowCrossesYear`)
2. A black or near-black artwork: the tint is still readable on black. (Task 2, `darkAverageIsLifted`)
3. A day with five events: two rows and "+3 more", nothing past 96pt. (Task 5 snapshot `21b-week-more`)
4. The panel reopened after midnight with another day selected before: today is selected. (Task 5, hand check)
5. A player whose app macOS cannot find an icon for: no badge, no crash. (Task 4, `badge` returns nil path; hand check not possible, code review)

---

### Task 1: `AgendaWeek` (Core)

**Files:** Modify `Sources/RavenIslandCore/Agenda.swift`; Test `Tests/RavenIslandCoreTests/AgendaWeekTests.swift`.
Remove `AgendaTimeline` and `Tests/RavenIslandCoreTests/AgendaTimelineTests.swift` (replaced).

**Produces:**

```swift
public struct AgendaWeek: Equatable, Sendable {
    public static let daysBefore = 2
    public static let daysAfter = 3
    public var days: [Date]          // start of each day, 6 entries, in order
    public var today: Date           // start of today
    public var start: Date { get }   // days.first
    public var end: Date { get }     // start of the day after days.last
    public init(now: Date, calendar: Calendar)
    /// Timed, not declined, not cancelled, overlapping that day; for today only end > now; by start.
    public func events(on day: Date, from events: [AgendaEvent], now: Date, calendar: Calendar) -> [AgendaEvent]
    public func hasEvents(_ events: [AgendaEvent], now: Date, calendar: Calendar) -> Bool
}
```

- [ ] **Step 1: Failing tests** in `@Suite struct AgendaWeekTests` (UTC Gregorian fixture as in `AgendaTests`):
  - `sixDaysAroundToday`: now 2026-11-15 14:00 → `days` are 13…18 Nov at 00:00, `today` 15 Nov.
  - `windowCrossesYear`: now 2026-12-30 10:00 → days 28, 29, 30, 31 Dec, 1, 2 Jan.
  - `overnightEventOnBothDays`: event 16 Nov 23:00–17 Nov 01:00 is in `events(on: 16 Nov)` and `events(on: 17 Nov)`.
  - `todayDropsEndedOtherDaysKeepThem`: now 15 Nov 14:00; event 15 Nov 9–10 not in today's list; event 14 Nov 9–10 in 14 Nov's list.
  - `filtersAndSorts`: all-day, declined, cancelled excluded; two events returned soonest first.
  - `hasEvents`: false for `[]`; true for one event on 18 Nov; false for one on 19 Nov.
- [ ] **Step 2:** `./scripts/test.sh --filter AgendaWeekTests` → fails to compile.
- [ ] **Step 3:** Implement; delete `AgendaTimeline` and its tests.
- [ ] **Step 4:** `./scripts/test.sh` → all pass.

### Task 2: `ArtworkTint` adjustment (Core)

**Files:** Create `Sources/RavenIslandCore/ArtworkTint.swift`; Test `Tests/RavenIslandCoreTests/ArtworkTintTests.swift`.

**Produces:** `public enum ArtworkTint { public static func readable(red: Double, green: Double, blue: Double) -> (red: Double, green: Double, blue: Double) }` — inputs and outputs 0…1. Through HSB: brightness raised to at least 0.75; when saturation ≥ 0.12, saturation raised to at least 0.45; below 0.12 the colour stays grey.

- [ ] **Step 1: Failing tests:** `darkAverageIsLifted` (0.2, 0.02, 0.02) → max component ≥ 0.75 and red still largest; `blackBecomesLightGrey` (0, 0, 0) → three equal components ≥ 0.75; `greyStaysGrey` (0.3, 0.31, 0.3) → components within 0.02 of each other; `vividUnchanged` (0.1, 0.8, 0.3) → each within 0.01.
- [ ] **Step 2:** fails to compile. **Step 3:** implement. **Step 4:** `./scripts/test.sh` → all pass.

### Task 3: Content rule and the week source (Core + App)

**Files:** Modify `Sources/RavenIslandCore/IdleHome.swift`, `Tests/RavenIslandCoreTests/IdleHomeTests.swift`,
`Sources/RavenIslandApp/CalendarSource.swift`, `NotchController.swift`, `Snapshot.swift`.

**Produces:** `IdleHome.init(nowPlaying:showMusic:agenda:collapsedLabel:agendaOn:weekHasEvents: Bool = false)`;
`showsPanel = hasTrack || agendaRows > 0 || weekHasEvents` (all calendar parts zero when `agendaOn` is false).
`CalendarSource.week: [AgendaEvent]` (published: every qualifying event fetched for `AgendaWeek(now:).start…end`).

- [ ] **Step 1: Failing tests:** `weekEventOpensPanel` (no track, `agendaOn: true`, `weekHasEvents: true`, no today events → `showsPanel`, `showsAgendaHalf`); `weekIgnoredWhenAgendaOff` (`agendaOn: false`, `weekHasEvents: true` → `.none`).
- [ ] **Step 2:** fails. **Step 3:** implement; `CalendarSource` fetches the six-day range, publishes `week`, keeps `events` (today remaining) and `collapsedLabel`; `NotchController.idleHome()` passes `weekHasEvents: AgendaWeek(now: Date(), calendar: .current).hasEvents(calendar.week, …)`.
- [ ] **Step 4:** `swift build`, `./scripts/test.sh` → all pass.

### Task 4: Badge, tint, record (App)

**Files:** Modify `Sources/RavenIslandApp/IdleHomeView.swift`, `MusicSource.swift`, `Snapshot.swift`.

**Produces:** `MusicSource.tint: Color?` (published; set when artwork arrives, nil without);
`static func badge(for app: MusicApp) -> NSImage?` (via `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` then `icon(forFile:)`);
`struct SpinningRecord: View { var app: MusicApp; var playing: Bool; var animated: Bool; var size: CGFloat }`.

- [ ] **Step 1: Snapshot cases first:** `20-music-badge-tint` (artwork with a strong colour, Spotify),
  `20b-record-spotify` (no artwork, playing, `animated: false`), `20c-record-music` (Apple Music, paused).
  `NotchContentView` gains `tint: Color? = nil` and `badge: NSImage? = nil`.
- [ ] **Step 2:** Tint: draw the artwork into a 4×4 bitmap, average, pass through `ArtworkTint.readable`; computed off the main thread when artwork changes.
- [ ] **Step 3:** Views: artist text and the progress fill use `tint ?? .white`; the badge (18pt, inset 3pt, 1.5pt black ring) on the lower-left of the art or record; `SpinningRecord` replaces the note glyph (rotation via `TimelineView(.animation)` only while `playing && animated`; stopped angle kept).
- [ ] **Step 4:** build, tests, bundle, snapshots; read 11, 12, 15, 20*.

### Task 5: Week strip (App)

**Files:** Modify `Sources/RavenIslandApp/IdleHomeView.swift` (replace `AgendaTimelineView`/`EventBlock`), `NotchView.swift`, `Snapshot.swift`.

**Produces:** `struct AgendaWeekView: View { var week: [AgendaEvent]; var onOpenCalendar: () -> Void }`; `IdleHomePanel.agenda` becomes the week list.

- [ ] **Step 1: Snapshot cases first:** `21-week-today` (two events today), `21b-week-more` (five today),
  `21c-week-empty-today` (events only on another day), `21d-week-other-day` (snapshot renders with a
  `selected` override parameter set to tomorrow). Existing 11, 13, 14, 15, 17* fixtures switch to week data; 17/17b (timeline) are removed.
- [ ] **Step 2:** Layout per spec 9.4: month/year column; six day buttons (weekday short, date; today in a filled blue circle; selected column on a rounded `.white.opacity(0.1)` panel); under them two rows (`Agenda.timeLabel`, colour bar, title via `TextSafety.visible`) and "+N more", or the empty state (`calendar.badge.checkmark` glyph, copy from Global Constraints). Selected day is `@State`, reset to today when the view appears and when the day changes.
  Tapping an event row calls `onOpenCalendar` (brings Calendar forward only).
- [ ] **Step 3:** build, tests, bundle, snapshots; read 11, 13, 14, 21*: nothing past 96pt.

### Task 6: Docs and the menu bar icon

**Files:** `README.md`, `docs/SPEC.md` (F15), `CHANGELOG.md`, `docs/screens/11-idle-both-expanded.png`.
The island menu bar icon (`Sources/RavenIslandApp/MenuBarIcon.swift`, already written) is mentioned in CHANGELOG and README.

- [ ] Update F15 and README for the week strip, badge, tint, record; recopy the screenshot.

### Task 7: Verification

- [ ] **Step 1:** Separately: `./scripts/test.sh`, `python3 scripts/e2e.py`, `./scripts/build-app.sh`, snapshot command.
- [ ] **Step 2:** Comment hygiene on this round's changes.
- [ ] **Step 3:** Hand checks on the installed app (`./scripts/install-app.sh`): badge matches the
  playing app; tint follows the art; record turns while playing and stops on pause; clicking days
  shows their events; selection back to today after reopening; menu bar icon in light and dark.
- [ ] **Step 4:** Fresh read-only review against spec 9 and this plan; fix, rerun, re-review.
- [ ] **Step 5:** Stop and report; ask before committing.
