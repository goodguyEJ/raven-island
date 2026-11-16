# Raven Island — Implementation Plan

> **Status:** phases 0–6 and 10 are built and shipped in 0.1.0. Phases 7–9 (phone alerts,
> remote sessions, other agents) are ideas only and are not planned for a particular release.

Companion to [SPEC.md](SPEC.md). Each phase ends in something
usable and has a concrete check; a phase is not done until its check passes on this Mac.

Order is by daily value first, risk second. Phases 0–5 are the core app. Phases 6–10 are
the long tail and can be reordered or dropped without affecting the core.

| Phase | Delivers | Spec features | Rough size |
|---|---|---|---|
| 0 | Project skeleton, build script, empty app that launches | — | S |
| 1 | Bridge, socket server, session store, installer | F9, F1 (data only) | M |
| 2 | Notch panel with live session list | F1, F2 | M |
| 3 | Approvals, questions, plan review | F3, F4, F5 | L |
| 4 | Jump to terminal | F6 | M |
| 5 | Sounds, settings window, launch at login | F8, F13 | M |
| 6 | Usage and quota display (built, then removed; see SPEC F7) | F7 | S–M |
| 7 | Phone alerts | F10 | S |
| 8 | Remote sessions over SSH | F11 | L |
| 9 | More agents | F12 | M per agent |
| 10 | Polish: external displays, diagnostics, custom jump rules | F2, F13, F6 | M |

---

## Phase 0 — Skeleton

1. Swift package with three targets: `RavenIslandApp` (executable, AppKit + SwiftUI),
   `ravenisland-bridge` (executable, Foundation only), `RavenIslandCore` (library shared by both:
   event models, socket framing, paths), plus `RavenIslandCoreTests`.
2. `scripts/build-app.sh`: `swift build -c release`, assemble `Raven Island.app` (Info.plist with
   `LSUIElement=true`, bundle id, icon placeholder), copy the bridge into
   `Contents/Helpers`, ad-hoc codesign.
3. `scripts/dev.sh`: build, kill any running instance, launch.
4. Git repo, `.gitignore`, README with build steps.

**Check:** `scripts/build-app.sh` produces an app that launches with no Dock icon and a
menu bar item with Quit. `swift test` runs.

## Phase 1 — Event pipeline

1. `RavenIslandCore`: Codable models for hook payloads (decode leniently; keep the raw JSON),
   the wire envelope, and the length-prefixed socket framing.
2. Socket server in the app: Unix domain socket at `~/.ravenisland/ravenisland.sock`, permissions
   `0600`, one connection per hook invocation, stale socket cleanup on launch.
3. `ravenisland-bridge`: read stdin, attach terminal context from the environment, connect with
   a short timeout, send, and for blocking events wait for the reply and print it to
   stdout. Any failure: exit 0 with no output so Claude Code behaves as if Raven Island were absent.
4. `SessionStore`: state machine from SPEC §5, keyed by session id; stale-session reaping.
5. Installer (`Raven Island.app/Contents/Helpers/ravenisland-bridge install|uninstall|status`): merge
   hook entries into `~/.claude/settings.json`, timestamped backup first, idempotent,
   entries tagged so uninstall removes only ours. Detect another tool's permission hooks and
   report them (SPEC §10) rather than touching them silently.
6. Debug window listing sessions and raw events.

**Check:** unit tests for decoding (using captured real payloads), state transitions, and
installer merge/uninstall round-trip on fixture settings files. Manually: start two Claude
Code sessions, see both in the debug window move through working → waiting → done. Quit
the app mid-session and confirm Claude Code is unaffected and hooks add no visible delay.

## Phase 2 — Notch panel

1. `NotchWindow`: borderless non-activating `NSPanel` above the menu bar, positioned from
   `NSScreen.safeAreaInsets` / `auxiliaryTopLeftArea`; joins all Spaces; ignores mouse
   outside its shape.
2. Collapsed state: notch-hugging pill with a status glyph and session count.
3. Expanded state on hover or click: session rows (project name, state, elapsed time,
   last activity line). Spring animation between states.
4. Auto-expand when a session needs attention; auto-collapse rules.
5. Fallback geometry for screens without a notch (floating pill, top centre).

**Check:** panel never takes keyboard focus from the terminal; works in full-screen
Spaces; correct on the built-in display; screenshots of collapsed, expanded, and
attention states reviewed.

## Phase 3 — Approvals, questions, plans

1. Spike first (half a day): on the installed Claude Code version, settle SPEC §11
   questions 1 and 2 — terminal behaviour while a permission hook is pending or times
   out, the `answers` shape for `AskUserQuestion`, and deny-with-message as plan
   feedback. Record findings in SPEC §4 and adjust F3–F5 if needed.
2. Pending-request queue: the bridge connection for a permission event stays open until
   the user decides, the request is resolved elsewhere, or it times out.
3. Approval card: tool name, a readable summary of the input (command text, file path
   plus diff preview for edits), Allow / Deny / Deny with message, "always allow" where
   the hook supports it.
4. Global shortcuts for Allow and Deny while a card is showing (user-configurable).
5. Resolution from elsewhere: if the user answers in the terminal, later events for that
   session dismiss the card.
6. Question card (options, multi-select, free text) and plan card (Markdown rendering,
   approve / send feedback), subject to the spike.

**Check:** scripted scenarios — allow a shell command, deny an edit with a message, answer
in the terminal while the card is open, quit the app while a request is pending (the
terminal prompt must still work), two sessions asking at once.

## Phase 4 — Jump to terminal

1. Capture at session start: `TERM_PROGRAM`, tmux pane, tty, parent process chain, cwd.
2. `Jumper` protocol with one implementation per terminal. First: Ghostty and the
   VS Code integrated terminal (the two installed here), then tmux pane selection.
3. Generic fallback: activate the owning app.
4. Spike per terminal to find the most precise supported method (scripting interface,
   URL scheme, CLI); document the precision achieved in SPEC F6.

**Check:** with three sessions across Ghostty tabs and VS Code, clicking each row brings
the right window (and tab, where supported) to the front.

## Phase 5 — Sounds, settings, launch at login

1. Sound engine: short synthesized tones per event via `AVAudioEngine`, original sound
   design; per-event enable and volume; custom pack folder (`~/.ravenisland/sounds/<pack>/`).
2. Settings window: General, Appearance, Sounds, Shortcuts, Integrations, About.
3. Launch at login via `SMAppService`. Quiet hours / respect Focus.

**Check:** each event plays its sound once; settings persist across relaunch.

## Phase 6 — Usage (removed)

Built, then removed: see SPEC F7.

1. Status line helper that forwards the usage fields to the app and then runs the user's
   previous status line command, so their status line keeps working.
2. Usage strip in the expanded panel: 5-hour and weekly percentages, reset countdowns,
   warning thresholds.

**Check:** numbers match `/usage` in Claude Code.

## Phase 7 — Phone alerts

1. Notifier protocol; Bark and ntfy implementations; off by default.
2. Per-event toggles; content level setting (title only vs. include command text),
   because this sends data to a third-party service.

**Check:** approval needed and task done arrive on the phone within a few seconds.

## Phase 8 — Remote sessions

1. Cross-compile or script-based bridge for Linux hosts.
2. `ravenisland-bridge remote add <host>`: copy bridge, install hooks remotely, open an SSH connection
   with a reverse-forwarded socket, reconnect with backoff.
3. Host badge on remote sessions; jump opens the local terminal attached to that host.

**Check:** a session on a remote box appears, can be approved from the notch, survives a
dropped connection.

## Phase 9 — More agents

1. `AgentAdapter` protocol (install, event mapping, capabilities).
2. One adapter at a time, starting with whichever agent gets installed next. Each needs
   its own research into that tool's hook or notification mechanism.

**Check:** per adapter, the Phase 1 and Phase 3 scenarios that the agent's mechanism allows.

## Phase 10 — Polish

External-display behaviour and display picker, diagnostic report export, custom jump
rules, custom agents, app icon, accessibility pass (VoiceOver labels, reduced motion).

## Phase 11 — Idle home (music, calendar)

Built. With no sessions, the notch shows what is playing in Spotify or Apple Music and today's
remaining events. Design: [superpowers/specs/2026-11-15-idle-home-design.md](superpowers/specs/2026-11-15-idle-home-design.md);
plan: [superpowers/plans/2026-11-15-idle-home-music-calendar.md](superpowers/plans/2026-11-15-idle-home-music-calendar.md).

## Phases 12–18 — After the idle home

Each gets its own short design before it is built, and plugs into the idle home.

| Phase | Feature | Approach | New permission | Main risk or open decision |
|---|---|---|---|---|
| 12 | Battery and charging | IOKit power source info and its change notification; percentage in the open panel, a short collapsed indicator on plug or unplug | None | A collapsed-only flash is the limit; it must not open the panel |
| 13 | Reminders | EventKit reminders beside the calendar list; tick to complete | Reminders | Ticking is a write, the first one outside Claude Code settings. Read-only is the alternative |
| 14 | File shelf with AirDrop | Drop files on the notch to park them, drag them out again, AirDrop through the system sharing service | None (not sandboxed) | The panel must open on drag-enter, a new way of opening; whether the shelf survives a restart |
| 15 | Mirror | Camera preview in the panel, running only while it is shown after a click | Camera | Camera access in an app that sits in the approval path; must be visibly off by default |
| 16 | Gestures and sizing | Two-finger swipe down to open and up to close, beside hover; pill size on displays without a notch | None | Scroll events over the menu bar area behave differently per macOS version |
| 17 | Volume and brightness HUD | Replace the system overlay | Accessibility or Input Monitoring, plus private APIs | Highest risk: private APIs, a keyboard-level permission for an app in the approval path. Needs a spike and an explicit yes before any design |
| 18 | Anything playing | System now-playing feed, behind a setting | None | Private framework and a third-party helper; confirm licence and macOS 26 behaviour first |

---

## Working rules

- Tests for everything in `RavenIslandCore` and the installer; UI verified by running the app.
- The installer never writes `settings.json` without a backup, and never removes entries
  it did not create.
- Original work: behaviour comes from Claude Code's public documentation; all code,
  artwork, and sounds are written for this project.
- Commit at the end of each phase.
