# Idle Home Round 2 Implementation Plan

> **For agentic workers:** run this plan inline, task by task, in one session on branch
> `feat/idle-home`. Do not use `superpowers:executing-plans` or
> `superpowers:subagent-driven-development`. **Never commit or push**: each task ends at a
> checkpoint where you report the diff and the real command output; the owner approves commits.

**Goal:** A compact Today timeline, a raven with headphones, bigger controls, a header mini
player while sessions run, Settings opening in front, and ravens that move their own bodies.

**Architecture:** Timeline layout and every new sprite frame are pure functions in
`RavenIslandCore`, unit-tested. Views in `RavenIslandApp` draw them. The only controller change
is the gear click (forced collapse, hover suppressed until the pointer leaves).

**Tech Stack:** Swift 6 toolchain in Swift 5 mode, SwiftPM, SwiftUI + AppKit, EventKit, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-15-idle-home-design.md`, section 8 (round 2), on top
of section 5 and the round 1 plan `docs/superpowers/plans/2026-11-15-idle-home-music-calendar.md`.

## Global Constraints

- Every round 1 Global Constraint still holds (macOS 14, Core imports Foundation only, no
  boring.notch code or assets, titles through `TextSafety.visible` and never on disk / log /
  diagnostics, fixed Apple Event strings, `i.scdn.co`-only opt-in network, no unasked prompts).
- Idle home height stays 96pt (`NotchGeometry.idleHomeHeight`); wing stays 38pt.
- Timeline window: 3 hours, starting at the latest full or half hour at or before now.
- Event block minimum height 12pt; at most 2 overlapping columns.
- Controls: previous / next symbols about 28pt, play/pause about 36pt, hit areas at least 36pt.
- Header mini player: only with sessions, a known track, `showMusic` on, and no request
  pending; never changes panel size.
- Redraw rates unchanged: `PixelSprites.frameDuration(for:)` values, `PixelBot` work
  durations (0.22 building, 0.4 other work) and the strollers' `tick` stay as they are.
- Reduce Motion: no bob, no blink cycling, no marquee, no note; still frames.
- All pixel art original, existing palette plus at most one new colour for the headphones.
- Commands: `./scripts/test.sh` (one suite: `--filter <Suite>`), `swift build`,
  `./scripts/build-app.sh`, `python3 scripts/e2e.py`,
  `"build/Raven Island.app/Contents/MacOS/Raven Island" --snapshot build/snapshots`.

## Review Focus

1. An event that started before the window and ends after it: one full-height block, no
   "Later" line. (Task 1, `spanningEventFillsWindow`)
2. Three or more events at the same time: two columns, the latest-starting ones dropped,
   nothing drawn outside the timeline. (Task 1, `thirdOverlapDropped`)
3. Window crossing midnight (now 23:20): hour marks continue past 00:00, events from tomorrow
   are not drawn, no "Later" line. (Task 1, `windowAcrossMidnight`)
4. A zero-length event (start == end): a 12pt block, not a crash or an invisible line.
   (Task 1, `zeroLengthEventGetsMinimumHeight`)
5. A decision arriving while the header mini player shows: the mini player disappears, the
   card is unchanged. (Task 5 snapshot `19c-header-mini-player-hidden-for-decision`, Task 8 hand check)

---

### Task 1: `AgendaTimeline` (Core)

**Files:**
- Modify: `Sources/RavenIslandCore/Agenda.swift`
- Test: `Tests/RavenIslandCoreTests/AgendaTimelineTests.swift`

**Interfaces — Produces:**

```swift
// AgendaEvent gains (initializer parameter last, defaulted):
public var color: UInt32?            // 0xRRGGBB, nil = default accent

public struct AgendaTimeline: Equatable, Sendable {
    public struct Block: Equatable, Sendable {
        public var event: AgendaEvent
        public var top: Double       // 0...1 of the window
        public var height: Double    // 0...1, at least minimumHeight
        public var column: Int       // 0 or 1
        public var columns: Int      // 1 or 2
    }
    public static let span: TimeInterval = 3 * 3600
    public var start: Date
    public var end: Date
    public var hourMarks: [Date]      // full hours with start <= mark <= end
    public var nowOffset: Double      // 0...1
    public var blocks: [Block]
    public var later: AgendaEvent?
    public init(events: [AgendaEvent], now: Date, calendar: Calendar, minimumHeight: Double)
}
```

Rules: same event filter as `remainingToday` (timed, not declined, not cancelled, `end > now`,
start before tomorrow's midnight), no row cap; blocks for events overlapping
`[start, end)` (a zero-length event counts if `start <= e.start < end`); top/bottom clipped to
the window; height raised to `minimumHeight`, moved up if it would pass 1. Columns: greedy by
start time; an event takes the first column free at its start; with both taken it is dropped;
`columns` is 2 for any block that overlaps a kept block in the other column. `later`: when no
event with `now < start < end` exists, the earliest event with `start >= end` that is still
before midnight; otherwise nil.

- [ ] **Step 1: Write the failing tests** in `@Suite struct AgendaTimelineTests`, same UTC
  fixture as `AgendaTests` (`at(_ h:)`, `ev(...)` with the id as given), `minimumHeight: 0.1`,
  now `at(14)` unless stated:
  - `windowStartsAtHalfHour`: now `at(14.33)` → `start == at(14)`, `end == at(17)`,
    `hourMarks == [at(14), at(15), at(16), at(17)]`, `nowOffset` ≈ 0.11 (±0.001); now `at(14.5)` → `start == at(14.5)`.
  - `blockPositions`: event 15–16, now `at(14)` → one block, `top == 1.0/3`, `height == 1.0/3`, `column == 0`, `columns == 1`.
  - `spanningEventFillsWindow`: event 13–18, now `at(14)` → `top == 0`, `height == 1`, `later == nil`.
  - `zeroLengthEventGetsMinimumHeight`: event 15–15 → `height == 0.1`; event 16.95–17 → `top + height <= 1`.
  - `twoOverlapsShareColumns`: events 15–16 and 15.5–16.5 → columns `[0, 1]`, both `columns == 2`.
  - `thirdOverlapDropped`: events 15–16 (a), 15–16 (b), 15.25–16 (c) → ids `["a", "b"]`.
  - `laterLine`: event 14–15 running and event 18–19, now `at(14.5)` → `later?.id == "18"`;
    add event 16–16.5 → `later == nil`.
  - `windowAcrossMidnight`: now `at(23.4)` → `start == at(23)`, `hourMarks.last == at(26)`; an event at 24.5–25 → no block, `later == nil`.
  - `declinedCancelledAllDayIgnored`: one of each in the window → `blocks.isEmpty`.
- [ ] **Step 2:** `./scripts/test.sh --filter AgendaTimelineTests` → fails to compile.
- [ ] **Step 3:** Implement `color` on `AgendaEvent` and `AgendaTimeline` in `Agenda.swift`.
  Half-hour floor uses `calendar.dateComponents([.hour, .minute], from: now)`.
- [ ] **Step 4:** `./scripts/test.sh` → all pass (existing `AgendaTests` unchanged).

**Checkpoint:** report; no commit.

---

### Task 2: Livelier ravens and the headphone raven (Core)

**Files:**
- Modify: `Sources/RavenIslandCore/Personas.swift`
- Test: `Tests/RavenIslandCoreTests/UsageAndSpriteTests.swift` (new tests beside the sprite tests)

**Interfaces — Produces:**

```swift
extension PixelSprites {
    /// Playing: head bob plus a rising note (at least 4 frames). Paused: one frame, headphones on.
    public static func listeningFrames(persona: Persona, playing: Bool) -> [[String]]
}
```

`frames(for:persona:work:)`, `walkFrames` and `trickFrames` keep their signatures; their
cycles now also move the raven: composition helpers beside `armsUp` / `blinking`
(`breathing` = torso and head 1 pixel down, `headTilted`, `leaning`, `wingToChin`,
`footTapping`, `headTurned`, `hopping`), combined with the existing prop frames. Cycle lengths
may grow (repeat the prop frames) but `frameDuration` values do not change. Headphones: a
band over the head and ear cups at an eye row, adjusted per persona so each hat stays visible;
new palette key `"P"` (one colour) in `sharedColors`; the note uses existing `"W"`.

- [ ] **Step 1: Write the failing tests:**

```swift
func body(_ frame: [String]) -> String { frame.map { String($0.prefix(PixelSprites.bodyWidth)) }.joined() }

@Test func ravensMoveInEveryState() {
    for p in PixelSprites.personas {
        for state in SessionState.allCases {
            let kinds: [WorkKind] = state == .working ? WorkKind.allCases : [.building]
            for kind in kinds {
                let frames = PixelSprites.frames(for: state, persona: p, work: kind)
                #expect(Set(frames.map(body)).count >= 2, "\(p.id) \(state)/\(kind) body never moves")
            }
        }
        #expect(Set(PixelSprites.walkFrames(persona: p).map(body)).count >= 2)
    }
}
@Test func ravensBlinkWhileWorking() {
    for p in PixelSprites.personas where !p.eyeRows.isEmpty {
        let frames = PixelSprites.frames(for: .working, persona: p, work: .thinking)
        #expect(frames.contains { f in p.eyeRows.allSatisfy { !f[$0].contains("W") && !f[$0].contains("K") } })
    }
}
@Test func frameDurationsUnchanged() {
    #expect(PixelSprites.frameDuration(for: .working) == 0.22)
    #expect(PixelSprites.frameDuration(for: .needsApproval) == 0.3)
    #expect(PixelSprites.frameDuration(for: .waitingForInput) == 0.45)
    #expect(PixelSprites.frameDuration(for: .done) == 0.45)
    #expect(PixelSprites.frameDuration(for: .error) == 0.35)
    #expect(PixelSprites.frameDuration(for: .idle) == 0.25)
}
@Test func listeningRavenWearsHeadphones() {
    for p in PixelSprites.personas {
        let playing = PixelSprites.listeningFrames(persona: p, playing: true)
        wellFormed(playing, "\(p.id) listening")
        #expect(playing.count >= 4)
        #expect(playing.allSatisfy { $0.joined().contains("P") })
        #expect(Set(playing.map(body)).count >= 2)
        let paused = PixelSprites.listeningFrames(persona: p, playing: false)
        #expect(paused.count == 1); #expect(paused[0].joined().contains("P"))
        #expect(paused[0] != PixelSprites.walkFrames(persona: p)[0])
    }
}
```

  `ravensBlinkWhileWorking`: if a persona's eye rows hold no `W` or `K` pixels when standing,
  `blinking` has no effect on it; such a persona is excluded by checking its standing frame first.
- [ ] **Step 2:** `./scripts/test.sh --filter UsageAndSpriteTests` → `listeningFrames` undefined.
- [ ] **Step 3:** Implement. Existing tests (`wellFormed` distinct frames, props carried,
  props at scale) must keep passing.
- [ ] **Step 4:** `./scripts/test.sh` → all pass. Build the bundle and render the snapshot;
  extend `Snapshot.writeSpriteSheet` with two columns, "listen" (a playing frame) and
  "paused", and read `0-characters.png`: every hat visible with headphones, poses readable.

**Checkpoint:** report with the sprite sheet path; no commit.

---

### Task 3: Compact Today timeline view (App)

**Files:**
- Modify: `Sources/RavenIslandApp/IdleHomeView.swift`, `CalendarSource.swift`, `Snapshot.swift`

**Interfaces — Consumes:** `AgendaTimeline`, `AgendaEvent.color` (Task 1).

- [ ] **Step 1: Snapshot cases first** (in `writeIdleHome`): events with colours, now-relative;
  `17-idle-timeline-overlap` (two overlapping events), `17b-idle-timeline-later` (only an event
  4 hours out → "Later" line), and update existing 11/13/15 fixtures to give events colours.
- [ ] **Step 2:** `CalendarSource`: map `EKEvent.calendar.cgColor` to `UInt32` RGB; publish
  `events` without the 3-row cap (add `limit: Int? = maxRows` to `Agenda.remainingToday`, pass `nil`).
- [ ] **Step 3:** Replace `agendaHalf` in `IdleHomePanel` with an `AgendaTimelineView`:
  `TimelineView(.periodic(from: .now, by: 30))` builds `AgendaTimeline(events:now:calendar:
  minimumHeight: 12 / drawableHeight)`; "Today" caption; hour labels (locale hour only, e.g.
  "2 PM" / "14") at 9.5pt 0.45 opacity with 0.12-opacity lines; red now-line with a 4pt dot
  (`Color(red: 1, green: 0.27, blue: 0.23)`); blocks as rounded rectangles in the event colour
  at 0.35 opacity with a 2pt left bar at full colour and the title (11pt, one line, clipped,
  `TextSafety.visible`); "Later: <time> <title>" line at 10.5pt 0.6 opacity; "Nothing else
  today" when no event is left today. Whole timeline tap → `onOpenCalendar`. Accessibility:
  one element per block, "<time> <title>".
- [ ] **Step 4:** `swift build`; `./scripts/test.sh`; bundle + snapshots; read 11, 13, 14,
  15, 17, 17b: nothing outside 96pt, readable at 12pt blocks, red line correct.

**Checkpoint:** report with PNG paths; no commit.

---

### Task 4: Bigger controls and the collapsed headphone raven (App)

**Files:**
- Modify: `Sources/RavenIslandApp/IdleHomeView.swift`, `PixelBot.swift`, `NotchView.swift`, `Snapshot.swift`

**Interfaces — Consumes:** `listeningFrames` (Task 2). **Produces:** `PixelBot.Mode.listening(playing: Bool)`.

- [ ] **Step 1: Snapshot cases first:** `18-idle-raven-listening-collapsed` (notch, playing),
  `18b-idle-raven-paused-collapsed`, `18c-idle-raven-pill`, and
  `18d-idle-characters-off-collapsed` (`characters: false` → artwork and bars as today).
- [ ] **Step 2:** `PixelBot`: add `.listening(playing:)` using `listeningFrames`, frame
  duration 0.5, label "Listening" / "Paused".
- [ ] **Step 3:** `NotchView.collapsedBody` left slot (and the pill): when
  `idle.hasTrack && characters`, `PixelBot(mode: .listening(playing: idle.isPlaying), persona:
  crew[hour % crew.count], size: side, animated: animated)`; else the round 1 `IdleMusicWing`.
- [ ] **Step 4:** `IdleHomePanel.musicHalf`: controls row as in spec 8.5 (symbols 28/36pt,
  frames at least 36pt), elapsed and remaining labels (10.5pt monospaced digits, 0.55 opacity,
  `m:ss`) either side of the bar; hidden with the bar when there is no duration. Keep
  `MusicControlButton` (add a `size` parameter).
- [ ] **Step 5:** build, tests, bundle, snapshots; read 11, 12, 14, 15, 18*: controls fit
  96pt, raven fits the 38pt wing, wings symmetric.

**Checkpoint:** report; no commit.

---

### Task 5: Header mini player (App)

**Files:**
- Modify: `Sources/RavenIslandApp/NotchView.swift`, `IdleHomeView.swift`, `Snapshot.swift`

**Interfaces — Produces:** `struct HeaderMiniPlayer: View { var nowPlaying: NowPlaying; var
compact: Bool; var allowed: Bool; var animated: Bool; var onPlayPause: () -> Void; var
onOpenPlayer: () -> Void }` and `struct Marquee: View { var text: String; var animated: Bool }`.

- [ ] **Step 1: Snapshot cases first** (main loop, sessions present, `usage` set):
  `19-header-mini-player` (working sessions + playing track), `19b-header-mini-player-compact`
  (a finished session so "Clear 1 done" shows), `19c-header-mini-player-hidden-for-decision`
  (track + `bash` request: no mini player). `NotchContentView` already takes `nowPlaying`.
- [ ] **Step 2:** In `NotchContentView.header`, right side, before "Clear N done": show
  `HeaderMiniPlayer` when `!sessions.isEmpty && request == nil`, `nowPlaying` non-nil;
  `compact = finished > 0`. Name width = remaining space, at least 40pt, else hidden.
- [ ] **Step 3:** `Marquee`: measures the text; if it fits, static; else scrolls right to left
  at 25pt/s with a 1.5s pause at the start, via `TimelineView(.animation)`; `animated == false`
  → `lineLimit(1)` with tail truncation. Text through `TextSafety.visible`.
- [ ] **Step 4:** build, tests, bundle, snapshots; read 19*, 3, 7: existing session and card
  snapshots byte-identical to before when no track is passed (compare with `cmp`).

**Checkpoint:** report; no commit.

---

### Task 6: Settings in front (App)

**Files:**
- Modify: `Sources/RavenIslandApp/NotchController.swift`, `main.swift`

**Interfaces:** `NotchController.onOpenSettings: (CGRect?) -> Void` — `nil` means "anywhere",
a rect is the panel frame to open below. `AppDelegate.showSettings(below: CGRect? = nil)`.

- [ ] **Step 1:** `NotchController`: the root view's gear calls a new `openSettingsFromPanel()`:
  without a pending request, `collapse(force: true)` (skips the `hovering` guard) and set
  `suppressHover = true`, then `onOpenSettings(nil)`; with a request pending, leave the panel
  and call `onOpenSettings(panel.frame)`. `hoverChanged`: while `suppressHover`, ignore
  entering; on exit clear it. No other hover or expand change.
- [ ] **Step 2:** `AppDelegate.showSettings(below:)`: with a rect, place the window's top
  12pt under its `minY`, centred on its `midX`, clamped to `NSScreen.main.visibleFrame`;
  the menu bar item keeps calling `showSettings()`.
- [ ] **Step 3:** `swift build`; `./scripts/test.sh`; `python3 scripts/e2e.py` (approval path
  untouched: same 31 checks pass).

**Checkpoint:** report; no commit. Behaviour is checked by hand in Task 8.

---

### Task 7: Docs

**Files:** `README.md`, `docs/SPEC.md` (F14, F15), `CHANGELOG.md`, `docs/screens/11-idle-both-expanded.png`

- [ ] **Step 1:** README "When nothing is running": timeline, headphone raven, mini player in
  the header while sessions run. Recopy the screenshot from the new snapshot.
- [ ] **Step 2:** SPEC F14: ravens breathe, blink and move per state; F15: timeline, headphone
  raven, controls, header mini player (hidden while a decision waits), gear closes the panel.
- [ ] **Step 3:** CHANGELOG "Added" entry extended; a "Changed" line for livelier ravens.

**Checkpoint:** report; no commit.

---

### Task 8: Final verification

- [ ] **Step 1:** Run separately and record exit status: `./scripts/test.sh`,
  `python3 scripts/e2e.py`, `./scripts/build-app.sh`, the snapshot command. Byte-compare the
  pre-round-2 cases that have no track against a build of HEAD rendered at the same moment;
  `0-characters` is expected to differ.
- [ ] **Step 2:** Comment hygiene over this round's changes.
- [ ] **Step 3: Hand checks** with the owner on `./scripts/dev.sh` (run from the repository
  folder): the 12 round 1 checks, plus: timeline matches Calendar for today; headphone raven
  bobs while playing and stands while paused; controls easy to hit; mini player shows with a
  session and music, scrolls a long name, and disappears when a decision arrives; gear opens
  Settings in front and the panel stays closed until the pointer leaves and returns; gear
  during a decision opens Settings below the panel; session ravens visibly move while working;
  Reduce Motion stills everything; Activity Monitor CPU for the open panel not higher than
  before (note the figure).
- [ ] **Step 4:** Fresh read-only review of the whole branch against spec section 8, this
  plan's Global Constraints and Review Focus, with the Step 1 output. Fix blockers, rerun, re-review.
- [ ] **Step 5:** Stop. Report files, results, hand checks, review, limitations. Wait for the
  owner before any commit.
