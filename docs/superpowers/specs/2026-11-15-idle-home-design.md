# Idle home: music, calendar, and the features after them

Date: 2026-11-15. Status: draft for approval. Branch: `feat/idle-home`.

## 1. Intent

When no Claude Code session is running, the notch shows two strolling ravens and an empty
panel with the flock. That space should be useful: what is playing, and what is next on the
calendar. The reference is boring.notch (TheBoredTeam), whose shipped features are now
playing, calendar and reminders, a file shelf with AirDrop, a webcam mirror, a charging
indicator, gestures and notch sizing, and a replacement for the system volume and
brightness HUD.

Decisions made by the owner:

- First round is the idle home screen with **Music** and **Calendar**.
- Music talks to **Spotify and Apple Music directly** (option A below).
- Everything else from boring.notch is planned here as later phases, not built now.

Everything else in this document is the author's proposal unless marked "owner decided".

## 2. Goals, non-goals, anti-goals

Goals

- With no sessions, the collapsed notch shows a hint of what is playing and when the next
  event starts; the open panel shows the track with controls and today's remaining events.
- Sessions and approvals always win: the moment a session exists, the panel is exactly what
  it is today.
- Each widget can be turned off; with both off or empty, the ravens are shown as today.

Non-goals (this round)

- Music controls while sessions are running.
- Any player other than Spotify and Apple Music (browsers, podcast apps).
- Editing or creating calendar events, choosing which calendars to show, all-day events.
- A real audio visualizer (the bars are decorative).

Anti-goals (would make this a failure even if it works)

- Anything that delays, covers, or competes with an approval card.
- The panel opening by itself, or a sound playing, because a track changed or an event is near.
- A permission prompt the user did not trigger by clicking something.
- Track or event titles reaching disk, the log, or the diagnostic report.
- Code or assets copied from boring.notch. It is GPL-3.0; this project is MIT and its
  working rules require original work. Ideas only.
- A network request the user did not switch on.

## 3. Constraints found in the code

- `NotchGeometry` sizes the panel from `sessionCount` plus two flags (`idleStroll`,
  `crewStage`) that `NotchController` sets from settings. `NotchController.applyFrame()`
  makes the window exactly the size of the shape, so any idle content needs its size known
  to geometry, not just to SwiftUI.
- The panel is centred on the screen, so the two wings beside the notch must be the same
  width. The panel sits above the menu bar; wider wings cover menu bar items. Wings are
  38pt today (`NotchGeometry.wing`).
- `RavenIslandCore` must stay free of AppKit (CONTRIBUTING.md). Logic that can be tested
  goes there; EventKit, Apple Events and views go in `RavenIslandApp`.
- The app is not sandboxed and is ad-hoc signed (`scripts/build-app.sh`). macOS may ask for
  Calendar or Automation permission again after a rebuild, because the signature changes.
- Apple Events already go out through `/usr/bin/osascript` in `Jumper.swift`, and the
  Info.plist usage string only mentions terminals.
- The README, SPEC section 8 and the security review all state "no network connections".
- The panel is hidden from screen sharing by default (`hideFromScreenSharing`); idle
  content inherits that.
- `--snapshot DIR` renders every panel state; CONTRIBUTING asks for before/after snapshots
  on UI changes.

## 4. Approaches considered for music

| | A. Spotify and Apple Music directly | B. System now-playing feed | C. A now, B later behind a setting |
|---|---|---|---|
| Covers | The two apps | Every app, with artwork | The two apps, later all |
| Mechanism | Their track-change notifications plus Apple Events for controls | Private MediaRemote framework through a bundled third-party helper run by the system Perl (closed to apps since macOS 15.4) | Both |
| Risk | Spotify artwork is a web link | Private API can break on any macOS update; adds a third-party binary to an app in the approval path; not confirmed on macOS 26 | A's, plus an abstraction not needed yet |

**Owner decided: A.** It matches the request (Spotify), reuses a mechanism the app already
has, and needs no private API. B stays possible later (phase 8) because the music source
sits behind one small protocol either way: two players already need it.

Calendar has one sensible route: EventKit, read-only.

## 5. Design: idle home (phase 1)

### 5.1 What the user sees

```
Collapsed, music playing, event later today:
 [art] ▮▯▮  ███ notch ███  10:30

Collapsed, nothing playing, event later today:
 (raven)    ███ notch ███  10:30

Open panel, no sessions:
 ┌──────────────────────────────────────────────────┐
 │ 5h 12% | 7d 40%      ███ notch ███        🔊 ⚙  │
 │ [art]  Song title            │ Today             │
 │        Artist                │ 10:30 Standup     │
 │  ⏮  ⏯  ⏭   ───●─────        │ 13:00 Planning    │
 │                              │ 15:30 Review      │
 └──────────────────────────────────────────────────┘
```

Collapsed

- Left wing: artwork thumbnail (or a note glyph) and three small bars that move while
  playing and rest while paused. Nothing playing: the strolling raven, as today.
- Right wing: start time of the next timed event ("10:30") once it is within 60 minutes,
  or "now" while one is running. Otherwise the second strolling raven, as today.
- Wings and the existing settings: the wings appear when strolling is on **or** either
  wing has idle content. A wing without content shows its raven when "Characters stroll
  by the notch" is on and stays empty when it is off. Turning "Show pixel characters" off
  does not hide the idle home; the two are independent.
- Only the time is shown collapsed, so the wings stay near today's 38pt and do not cover
  more of the menu bar. The builder may widen both wings by a few points if "10:30" does
  not fit at a readable size; anything beyond 48pt comes back to the owner.
- The floating pill on displays without a notch shows the same two items side by side.

Open panel (replaces `CrewStage` when either widget has content)

- Left half, music: artwork, title, artist, previous / play-pause / next, and a progress
  bar. Clicking the artwork or title brings the player to the front.
- Right half, calendar: "Today" and up to three remaining timed events, soonest first,
  each as start time and title; an event in progress is marked. Clicking an event opens
  the Calendar app.
- "Content" means a known track (playing or paused) or at least one remaining event.
  The idle home replaces `CrewStage` only when there is content; with none, the flock is
  shown exactly as today. Permission and empty states never count as content.
- One widget only: it takes the full width.
- Fixed height for the idle home area (96pt, close to `CrewStage.height` of 88) so the
  panel does not jump between states.

Permission and empty states

| State | Shown |
|---|---|
| Music, Automation not granted yet | Nothing until the player next changes track or pauses (that needs no permission); from then on the track shows. The first click on a control triggers the macOS prompt |
| Music, Automation denied | Track info keeps working; control buttons are dimmed with a tooltip pointing to System Settings |
| Calendar | Off by default. Turning on "Show today's events" in Settings triggers the macOS prompt; nothing in the panel ever asks |
| Calendar denied | No calendar half; Settings shows how to grant it |
| Calendar granted, no more events today, a track is showing | "Nothing else today" in the calendar half |

Behaviour rules

- Idle home is shown only when `sessions.isEmpty` and no request is pending. No change to
  any path with sessions.
- Nothing here calls `expand()`. Hover opens the panel as it does today.
- All titles go through `TextSafety.visible` like every other externally supplied string.
- Reduce Motion: bars and progress do not animate.

### 5.2 Music

Reading (no permission needed)

- Both players broadcast a distributed notification on every play, pause and track change:
  `com.spotify.client.PlaybackStateChanged` and `com.apple.Music.playerInfo`. The payload
  carries player state, title, artist, album and duration (Spotify also position).
- A pure parser in Core turns either payload into one `NowPlaying` value. Unknown or
  missing fields never crash; a payload without a title is treated as "nothing playing".
- When both players report playing, the most recent notification wins.
- When a player quits (`NSWorkspace.didTerminateApplicationNotification`), its state clears.

Controls and initial state (Automation permission, per player)

- Play/pause, next and previous are Apple Events to the player. The first click triggers
  the macOS Automation prompt for that player; this is the user's own action.
- At launch, and when a player starts, the app asks the player for its current track only
  if Automation is already granted (`AEDeterminePermissionToAutomateTarget` with
  ask = false) and the player is already running. It never launches a player.
- Position for the progress bar: taken from the payload or one query, then advanced from
  the timestamp while playing. No polling.

Artwork

- Apple Music: read from the current track through Apple Events (needs the same Automation
  grant). Missing artwork (some streamed tracks) falls back to the note glyph.
- Spotify: the player only exposes a web address. Loading it is **off by default** behind
  a setting. When on: HTTPS only, host must be `i.scdn.co`, ephemeral session with no
  cookies or cache on disk, response capped at 2 MB, image kept in memory for the current
  track only. When off: the note glyph.

### 5.3 Calendar

- EventKit, `requestFullAccessToEvents` (macOS 14). EventKit offers no read-only grant;
  the app only ever reads.
- Events: today from now until midnight, timed only, not declined, not cancelled, from all
  calendars. Sorted by start; an event still running counts as current.
- Refresh on `EKEventStoreChanged`, at the next boundary (60 minutes before a start, a
  start, or an end), at midnight, and on wake. No periodic polling.
- Selection and labelling (which events, "now" versus a time, 12/24-hour from the user's
  locale) are pure functions in Core over a small `AgendaEvent` value type.

### 5.4 Code shape

New in `RavenIslandCore` (pure, unit-tested)

- `NowPlaying.swift`: `NowPlaying` value (player, title, artist, album, state, duration,
  position, timestamp), the two payload parsers, position-at-date.
- `Agenda.swift`: `AgendaEvent`, "remaining today" selection, next-up, time labels.
- `IdleHome.swift`: `IdleHome` value saying which widgets have content, used by geometry
  and views so they cannot disagree.

New in `RavenIslandApp`

- `MusicSource.swift`: a small `MusicPlayer` protocol with Spotify and Apple Music
  implementations (notification name, bundle identifier, scripts), plus the observable
  `MusicSource` that owns the current `NowPlaying` and artwork.
- `CalendarSource.swift`: observable wrapper over `EKEventStore`.
- `IdleHomeView.swift`: collapsed wing views and the open panel's idle home.

Changed

- `NotchGeometry`: an `idleHome` field next to `idleStroll` / `crewStage`; collapsed and
  expanded sizes account for it when `sessionCount == 0`.
- `NotchView`: `collapsedBody` and the empty branch of `expandedBody` use the new views.
- `NotchController`: subscribes to the two sources and settings, updates geometry and
  calls `applyFrame()`, the way it already does for `showCharacters`.
- `Settings` / `SettingsView`: an "Idle screen" section in General with `showMusic`
  (default on), `showCalendar` (default off; turning it on asks for access),
  `spotifyArtwork` (default off).
- `main.swift`: creates the sources and passes them to the controller.
- `Snapshot.swift`: idle states with fixed sample data: both, music only, calendar only,
  permission rows, for notch and pill.
- `Diagnostics.swift`: the three settings, permission status, and whether each source has
  content, as booleans. Never titles.
- `scripts/build-app.sh`: reword `NSAppleEventsUsageDescription` to cover music players;
  add `NSCalendarsFullAccessUsageDescription`.
- Uninstall (`scripts/uninstall.sh` and Settings → Integrations → Uninstall): also reset
  the app's Calendar and Automation grants (`tccutil reset Calendar` / `AppleEvents` for
  the bundle identifier), in keeping with "puts everything back".
- Docs: README (features, "What this changes on your Mac", the network line), SPEC (new
  feature entries and section 8), SECURITY-REVIEW (new inputs: notification payloads from
  other apps, artwork download), CHANGELOG, PLAN (new phases).

### 5.5 Safety and privacy

- Distributed notifications can be posted by any local process, so payloads are untrusted
  input: length-capped, shown through `TextSafety.visible`, never interpreted.
- Scripts sent to players are fixed strings; nothing from a payload is ever placed in one.
- Nothing from either source is written to disk or to the in-app log.
- The only network use is the opt-in Spotify artwork fetch, with the limits in 5.2.
- The approval path is untouched: no change to `AppModel` request handling, the socket,
  the bridge, or hot keys.

### 5.6 Verification

- Unit tests (Core): both parsers with real-shaped, partial, oversized and wrong-typed
  payloads; position-at-date while playing and paused; agenda selection around midnight,
  for running, back-to-back, declined, cancelled and all-day events; labels.
- Snapshots: the new idle states, compared with today's `4-expanded-empty` and
  `4b-collapsed-empty`.
- Existing unit and end-to-end tests still pass unchanged (the approval path is untouched).
- By hand on the built app: Spotify and Apple Music play/pause/skip, both prompts, denial
  of each prompt, a session starting while music plays (panel switches to sessions), an
  approval arriving while the idle home is open (card takes over), Reduce Motion, a
  display without a notch.

### 5.7 To confirm by a short spike before building on it

1. Exact payload keys and units of the two notifications on the current Spotify and
   Music versions (duration in ms, Spotify position in seconds are expected).
2. Reading Apple Music artwork through Apple Events, and what streamed tracks return.
3. Whether the Calendar prompt appears for the ad-hoc signed bundle, and whether the
   grant survives a rebuild by `scripts/dev.sh` (each build is re-signed).
4. Whether "10:30" fits the 38pt wing at a readable size.

Spike results (2026-11-15, macOS 26, Spotify current release)

1. Spotify `com.spotify.client.PlaybackStateChanged`, confirmed over play, pause, resume and
   skip: `Player State` String (`Playing`, `Paused`); `Name`, `Artist`, `Album`,
   `Album Artist` String; `Duration` NSNumber in **milliseconds** (242467 for a 4:02 track);
   `Playback Position` NSNumber in **seconds** (140.214 at pause); `Track ID` String
   (`spotify:track:…`); also `Has Artwork`, `Disc Number`, `Track Number`, `Play Count`.
   Apple Music `com.apple.Music.playerInfo`: only a `Stopped` payload was seen (it carries
   `Player State` alone); the library on the test Mac is empty, so `Total Time` and
   `PersistentID` remain **unconfirmed** and follow the plan's table.
2. Spotify `artwork url of current track` returns an `https://i.scdn.co/…` address.
   Apple Music artwork could not be checked (empty library): **unconfirmed**.
   Finding: `tell application id "com.apple.Music"` **launches** Music when it is not
   running, so every script must be guarded by a running check, as the plan requires.
3. Hand check (2026-11-15): the Calendar prompt appears for the ad-hoc signed bundle, with the
   usage string. A rebuild by `scripts/dev.sh` re-signs the app and macOS forgets both the
   Calendar and the Automation grants. Settings now offers "Allow Calendar Access" when the
   switch is on but access was never asked, so the prompt still follows a click.
4. "10:30" at 11pt semibold monospaced digits is 32.8pt wide, so it fits 38pt. A 12-hour
   label such as "3:30 PM" is 45.7pt and fits only through `minimumScaleFactor(0.8)`
   (36.6pt). The wing stays 38pt.

### 5.8 Left to the builder

File-internal structure, view layout details and exact sizes within the limits above,
`osascript` versus in-process `NSAppleScript` (artwork data likely needs the latter),
wording of the small state rows, and snapshot fixture content.

## 6. Later phases (outline; each gets its own short design before it is built)

Order is by value against risk. Each phase is independent of the others and plugs into the
idle home from phase 1. Features boring.notch only lists as planned (Bluetooth, weather,
lock screen widgets, notifications, extensions) are not planned here.

| Phase | Feature | Approach | New permission | Main risk or open decision |
|---|---|---|---|---|
| 2 | Battery and charging | IOKit power source info and its change notification; percentage in the open panel, a short collapsed indicator on plug or unplug | None | A collapsed-only flash is the limit; it must not open the panel |
| 3 | Reminders | EventKit reminders beside the calendar list; tick to complete | Reminders | Ticking is a write, the first one outside Claude Code settings. Read-only is the alternative |
| 4 | File shelf with AirDrop | Drop files on the notch to park them, drag them out again, AirDrop through the system sharing service | None (not sandboxed) | The panel must open on drag-enter, a new way of opening; whether the shelf survives a restart |
| 5 | Mirror | Camera preview in the panel, running only while it is shown after a click | Camera | Camera access in an app that sits in the approval path; must be visibly off by default |
| 6 | Gestures and sizing | Two-finger swipe down to open and up to close, beside hover; pill size on displays without a notch | None | Scroll events over the menu bar area behave differently per macOS version |
| 7 | Volume and brightness HUD | Replace the system overlay | Accessibility or Input Monitoring, plus private APIs | Highest risk: private APIs, a keyboard-level permission for an app in the approval path. Needs a spike and an explicit yes before any design |
| 8 | Anything playing | Option B from section 4, behind a setting | None | Private framework and a third-party helper; confirm licence and macOS 26 behaviour first |

## 7. Calls made by the author, for the owner to check

1. Collapsed notch shows only the event's start time, not its title, to avoid covering the
   menu bar.
2. Idle widgets never open the panel or play a sound.
3. Music controls are not available while sessions are running.
4. All-day, declined and cancelled events are left out; all calendars are included.
5. Spotify artwork is off by default because it is the app's first network request.
6. No permission prompt appears until the user clicks something. So Calendar is off
   until switched on in Settings, and music shows from the next track change after launch.
7. The bars beside the artwork are decorative, not driven by the audio.
8. The HUD replacement is last and may be dropped.
9. The collapsed notch shows an event's time only from 60 minutes before it starts.
10. The idle home replaces the flock only when there is a track or an event to show.
11. Idle home and "Show pixel characters" are independent settings.
12. Uninstall resets the Calendar and Automation grants.

## 8. Round 2: owner feedback after the first build (2026-11-15)

Status: draft for approval. Same branch, same constraints as section 5 unless changed here.

### 8.1 Intent

The first build worked but read as a list, not a glance. The owner wants the calendar to look
like a small macOS Calendar day view, a raven that visibly listens while music plays, controls
big enough to hit without aiming, music reachable while sessions run, and a Settings window
that is not hidden behind the panel. Album art not showing was the opt-in setting being off,
which stays as designed (5.2).

### 8.2 Decisions (owner decided)

1. **Calendar: compact Today timeline**, inside the existing 96pt idle area. No Tomorrow column,
   no reminders (reminders stay phase 3).
2. **Headphone raven in the collapsed notch only**, replacing the artwork and bars there.
3. **Bigger music controls** in the open idle panel.
4. **Mini player in the header row while sessions run**: a scrolling track name and
   play/pause. This reverses section 2's non-goal "music controls while sessions are running"
   and "the panel is exactly what it is today" for the header only.
5. **Settings opens in front**: clicking the gear in the panel closes the panel first.

### 8.3 Goals, non-goals, anti-goals (changes only)

- Goal: a glance at the open panel tells what is happening in the next few hours without
  reading.
- Non-goal: Tomorrow, reminders, all-day events, scrolling or zooming the timeline.
- Anti-goal (kept and sharpened): the mini player never shows while a decision is waiting,
  never changes the panel's height, and never moves the session list or a card.

### 8.4 Approaches considered

| Piece | Chosen | Rejected, and why |
|---|---|---|
| Calendar | Drawn in SwiftUI in the idle panel: a fixed 3-hour window | Embedding Apple's widget (not possible for a third-party app); a scrollable day (does not fit 96pt, and scrolling a hover panel is awkward) |
| Headphone raven | Headphones as a prop overlaid on the existing raven frames (`PixelSprites.overlaying`), so any of the six can wear them | A seventh, dedicated raven (breaks "each raven keeps its look", more art) |
| Bigger controls | Relayout of the music half | None worth listing |
| Mini player | Inside the header's right side, left of the sound and Settings buttons | A new row under the header (adds ~24pt and shifts every session layout) |
| Settings behind panel | Collapse the panel, then open Settings | Raising the Settings window above the panel (a normal window above the menu bar level behaves badly) |

### 8.5 Design

**Compact Today timeline** (replaces the agenda rows in `IdleHomePanel`)

```
 Today                        ← caption, as now
 2 PM ─────────────────────
 ━━━━● now line (red) ━━━━━
       ▌Standup              ← block in the calendar's colour
 3 PM ─────────────────────
       ▌Planning
 4 PM ─────────────────────
       Later: 6:09 PM Review ← only when the next event starts after the window
```

- Window: 3 hours, starting at the most recent full or half hour at or before now (now at
  14:20 → 14:00–17:00). It moves on the existing refresh boundaries plus every half hour.
- Hour lines with short labels (locale 12/24-hour, no minutes); a red now-line with a dot.
- Events: timed, not declined, not cancelled, overlapping the window, as rounded blocks in
  their calendar's colour (`EKCalendar.cgColor`), with the title in one line, clipped. A
  block is at least 12pt tall so a 15-minute event stays readable. Overlapping events share
  the width side by side, at most two columns; a third overlapping event is not drawn.
- "Later" line: when no event that has not started yet starts inside the window, but one starts
  later today, one line at the bottom: "Later: <time> <title>" for the earliest of those. A
  running event does not suppress it. (Builder's call, recorded.)
- A third overlapping event that is not drawn is the one that starts latest; it does not lead
  to a "Later" line. (Builder's call, recorded.)
- Empty: "Nothing else today", as now, when no event is left today.
- Content rule from 5.1 is unchanged: the calendar counts as content only when an event is
  left today. Clicking anywhere on the timeline opens Calendar.
- Core: a pure function computes the window, the hour marks, and each event's vertical span
  and column within it, so layout is unit-tested. `AgendaEvent` gains a colour (as an RGB
  value, so Core stays free of AppKit). `Agenda.remainingToday` stops capping at three rows
  for the timeline; the collapsed label and diagnostics are unchanged.

**Headphone raven** (collapsed notch, left wing; floating pill, beside the time)

- Shown while a track is known and "Show pixel characters" is on. With characters off, the
  artwork and bars stay, as now.
- The raven is the one that would stroll on that side this hour. It stands still, facing
  right, wearing headphones: a band over the head and ear cups at eye level, drawn per persona
  so hats (top hat, beret, hood, hard hat) stay visible under or around the band.
- Playing: head bob on a beat of about 0.5s, and a small music note rises beside it every few
  seconds. Paused: headphones on, no bob, no note. Reduce Motion: still frame.
- Original pixel art drawn for this project, in the existing palette. Added to the sprite sheet
  snapshot.

**Bigger controls** (open idle panel, music half)

```
 [art 56]  Night Drive
           The Sample Band
           1:21 ───────●────────── -2:13
                ⏮      ⏯      ⏭
```

- Previous and next about 28pt symbols, play/pause about 36pt, spread evenly under the
  progress bar; hit areas at least 36pt. Elapsed and remaining time either side of the bar
  (hidden with the bar when there is no duration). Dimmed state and tooltip as now.

**Mini player in the header** (only when sessions exist, a track is known, `showMusic` is on,
and no decision is waiting)

```
 5h 12% | 7d 40%      ███ notch ███   ♪ Night Dri ⏯  🔊 ⚙
```

- Right side of the header, left of the sound and Settings buttons: a small note glyph, the
  title scrolling right to left in the space left over, and a play/pause button. On a 185pt
  notch that leaves the name about 85pt; the name area takes whatever remains, at least 40pt.
- When "Clear N done" is showing there is no room: only the note and play/pause remain.
- The name scrolls only when it does not fit, at a slow, steady speed with a pause at the
  start; with Reduce Motion it does not scroll and ends in "…". Text through
  `TextSafety.visible`.
- Clicking the name brings the player forward; play/pause sends the same fixed Apple Event.
- No change to panel size, the session list, cards, or the collapsed notch with sessions.

**Settings in front**

- Owner decided: the gear button in the panel closes the panel even though the pointer is on
  it, then opens Settings. Hover does not reopen the panel until the pointer has left the
  panel's area and come back. This is a deliberate change to the hover logic, limited to this
  click.
- While a decision is waiting the panel stays open (decisions win), and the Settings window
  opens just below the panel instead, clamped to the screen's visible area.
- Opening Settings from the menu bar is unchanged.

**Livelier ravens** (owner decided; all ravens, session rows and idle alike)

- Today every working frame draws the same standing raven; only the prop changes, so the bird
  looks frozen. Each state's frames now also move the raven itself.
- Always: a 1-pixel breathing bob about once a second and a blink every few seconds, in every
  state including the stroll.
- Per state: thinking, head tilt and a wing to the chin; searching, leaning toward the lens;
  running, tapping a foot; building, wing lifting with each hammer strike; waiting, head
  turning between viewer and "?"; done, a small hop with the cheer.
- Same redraw rate as today: motion is composed into the existing frames (more frames per
  cycle where needed, same tick), so idle and open-panel CPU do not rise (see SECURITY-REVIEW
  R2-15). Reduce Motion: still frames as today. The sprite sheet snapshot shows the new poses.
- Approach: body poses as pixel edits composed onto each persona's standing frame, like
  `armsUp` and `blinking` today, so all six ravens get them without redrawing each one.

### 8.6 Constraints kept

Everything in section 5.5 and the round 1 plan's Global Constraints, except as changed in
8.2 item 4 (header mini player) and 8.2 item 5 (the gear click may close a hovered panel).
Idle height stays 96pt; the wing stays 38pt.

Calls made by the author, for the owner to check: calendar colours on event blocks; at most
two overlapping columns; with "Show pixel characters" off the collapsed wing keeps artwork
and bars; the header name gets about 85pt on a 185pt notch, and only the note and play/pause
when "Clear N done" shows; the "Later" line and dropped-overlap rules above.

### 8.7 Verification

- Unit tests for the timeline layout (window start, hour marks, spans, the 12pt minimum,
  two-column overlap, the third overlapping event dropped, "Later" line, midnight).
- Snapshots: timeline with several events, an overlap, the "Later" line, empty; headphone
  raven playing and paused for all six personas on the sprite sheet; bigger controls; header
  mini player with and without "Clear N done"; existing cases unchanged.
- Hand checks: the round 1 list, plus: mini player appears with sessions and hides when a
  decision arrives; Settings opens in front.

### 8.8 Left to the builder

Exact pixel art of the headphones per persona, block corner radius and colours' opacity,
scroll speed, spacing.

## 9. Round 3: player badge, artwork colours, record, week strip (2026-11-15)

Status: draft for approval. Same branch and PR. Everything in sections 5 and 8 holds unless
changed here.

### 9.1 Intent

The owner wants the open idle panel to look closer to the reference they shared (a screenshot
of boring.notch): which player is playing at a glance, colour taken from the music, something
alive when there is no artwork, and a calendar that shows the week and lets them look at another
day without leaving the notch. boring.notch is GPL-3.0: the screenshot is a reference for ideas
only; no code or assets.

### 9.2 Decisions (owner decided)

1. A badge with the playing app's icon on the **lower-left** corner of the artwork.
2. The artist name and the progress bar are **tinted from the artwork**.
3. With no artwork, a **spinning record** instead of the note glyph.
4. The calendar side takes the reference's format: month and year, a **week strip** with today
   highlighted, and the selected day's events or "No events today" under it.
5. **Clicking a day shows its events** in place.

### 9.3 Approaches considered

| Piece | Chosen | Rejected, and why |
|---|---|---|
| Badge | The installed app's own icon from macOS (`NSWorkspace.icon(forFile:)` on the app's URL), drawn at runtime | Bundling Spotify or Apple logos (third-party trademarks; CONTRIBUTING forbids other apps' artwork) |
| Tint | Average colour of the artwork drawn into a tiny bitmap, then raised in brightness and saturation to read on black | A dominant-colour histogram (more code, little visible difference at this size) |
| No artwork | A record drawn in SwiftUI, turning while playing | Keeping the note glyph (owner asked for the record) |
| Days shown | Six days: two before today, today, three after | The calendar week Mon–Sat (on a Saturday nothing after today would show) |
| Day click | Shows that day's events under the strip | Opening Calendar on that day (leaves the notch) |

### 9.4 Design

**Music half** (open idle panel)

```
 ┌────────┐  Night Drive
 │  art   │  The Sample Band          ← artist in the tint
 │        │  1:21 ━━━━━━──────── -2:12 ← filled part in the tint
 └[▣]─────┘       ⏮    ⏯    ⏭
   └ app icon, 18pt, lower-left, dark ring
```

- Badge: the playing app's icon (Spotify or Music) at about 18pt, inset 3pt from the lower-left
  corner, with a 1.5pt black ring. Shown on artwork and on the record. If macOS has no icon for
  the app, no badge.
- Tint: computed once per artwork image. Without artwork the player's colour (Spotify green,
  Music red) is used instead, matching the record (owner feedback: the panel read too bland).
  The elapsed time takes the tint in semibold; the remaining time stays dim. The tint
  is never darker than a minimum brightness and never fully grey (a floor on saturation only
  when the average has a hue), so text stays readable on black. Title stays white.
- Record: same size and corner radius box as the artwork. A near-black disc with three faint
  groove rings, a centre label in the player's colour (Spotify green `#1DB954`, Music red
  `#FA2D48` — plain colours, not logos) and a spindle hole. Turns about one revolution every
  2 seconds while playing, holds its angle when paused, still with Reduce Motion. The badge
  sits on it the same way.
- The collapsed headphone raven, controls, and progress layout from round 2 are unchanged.

**Calendar half** (replaces the round 2 timeline)

```
 Nov   Thu Fri  Sat  Sun Mon Tue
 2026  13  14  (15)  16  17  18      ← today in a blue circle; selected day in a panel tint
 ───────────────────────────────
  9:30  ▌Standup
 13:00  ▌Planning            +2 more
   — or —
        [calendar icon]
        No events today
        Enjoy your free time!
```

- Left: month (short name) over year, in the locale.
- Strip: six days, from two days before today to three after. Each day: weekday (short, locale)
  over the date. Today: the date in a filled blue circle. Selected day (today by default): a
  rounded panel behind its column. Days are buttons; clicking selects.
- Under the strip: the selected day's timed events, not declined, not cancelled, soonest first,
  at most two rows (start time in the locale's style, colour bar, title through
  `TextSafety.visible`), then "+N more" if there are more. For today, only events not yet ended,
  as now. For other days, all of that day's events. An event is listed under every day it
  overlaps, as Calendar does, so an overnight event shows on both days (builder's call).
  Clicking a row brings Calendar forward, as today; it does not jump to the day, which would need
  Apple Events to Calendar and a new permission (builder's call).
- Empty selected day: a calendar glyph, "No events today" (or "No events" for another day),
  and "Enjoy your free time!" under it, in secondary text.
- Selection goes back to today when the panel collapses and at midnight.
- Height stays 96pt.

**Content and data**

- CalendarSource reads events for the six-day window instead of today only, and publishes them
  grouped by day. Refresh triggers stay as in 5.3 (store change, wake, next boundary, midnight).
- What counts as content changes (owner left it to the author's judgement): the calendar side
  counts as content when any of the six days has an event, so the user can look ahead even when
  today is clear and nothing is playing. With an empty week, the flock comes back as before.
  The collapsed time label still uses today only.
- Diagnostics: `eventsToday` stays; titles are still never reported.

### 9.5 Constraints kept

Everything in 5.5, 8.6 and the plans' Global Constraints. Idle height 96pt, wing 38pt. No
network beyond the opt-in Spotify art. No prompt beyond a user's click. Core stays free of
AppKit (the tint computation, which needs image drawing, lives in the app target; its pure
colour adjustment is in Core and unit-tested).

### 9.6 Verification

- Unit tests: the six-day window across a month and year boundary, grouping by day, the
  selected day's rows (today excludes ended events, other days do not), "+N more", the colour
  adjustment (dark, grey, saturated inputs).
- Snapshots: art with badge and tint; record with badge, Spotify and Music; week strip with
  today selected and events; another day selected; empty day; "+N more".
- Hand checks: the badge matches the playing app; the tint follows the art and resets without
  it; the record turns and stops; clicking days shows their events; the selection resets after
  the panel closes.

### 9.7 Left to the builder

Exact sizes inside the 96pt, ring and badge shading, groove opacity, the selected-day panel
colour, the tint's exact floor values.
