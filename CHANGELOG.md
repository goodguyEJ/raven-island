# Changelog

## Unreleased

### Added
- **Idle home.** With no sessions running, the notch shows what is playing in Spotify or
  Apple Music (play, pause, and skip in the open panel) and today's remaining calendar events,
  with the next start time beside the notch from an hour before. Calendar and Spotify album
  art are off until switched on in Settings → General → When nothing is running; album art is
  the app's only network request. Uninstall now also resets the Calendar and Automation
  permissions. A raven in headphones listens while music plays, the player's icon and colours
  from the album art mark the track (a spinning record when there is no art), a week strip shows
  six days with each day's events a click away, and a small player stays in the header while
  sessions run.
- **Temperatures.** An optional setting (off by default) adds a line in the lower right corner
  of the open panel with the CPU, SSD and battery temperatures, each green, yellow or red by
  range. Read from the Mac's own sensors every 3 seconds, only while the panel is open.
- Settings offers "Allow Calendar Access" when a rebuild has cleared the Calendar grant.
- When the calendar is off or not allowed, the open panel shows a small card with the one step
  that turns it on, instead of an empty space beside the music.

### Changed
- The menu bar icon is a small island with palms instead of the raven.
- The ravens are livelier: they breathe, blink, and move with what they are doing instead of
  standing still beside their props. While music plays, every raven wears headphones.
- The panel's Settings button closes the panel so Settings opens in front of it.

### Raven Island
- Crow's Nest is now **Raven Island**: a dynamic island for Claude Code, kept by a flock of
  smart 8-bit ravens. An existing install upgrades in place: the old hooks are replaced (never
  duplicated), your remembered status line and preferences carry over, and the old
  `~/.crowsnest` folder is removed once nothing points at it.
- Six original raven personas replace the field agents: Huginn the strategist, Muninn the
  archivist, Quill the scribe, Pip the scout, Nyx the night watch and Tinker the tinkerer,
  each with its own look and party trick.
- New logo: a raven on a pixel island under the moon.

### Panel
- The open panel's top corners curve outward into the top edge of the screen, so it hangs from
  the notch.
- Header: usage limits at the top left; sound on/off and Settings buttons at the top right.
- When a decision is waiting, the panel shows only that session and its card, with
  "Show all N sessions" to see the rest and "Show less" to go back.
- Decisions queue in the order they arrive: the card shows "Decision 1 of N", an "Up next" line
  names the next one, and it slides in by itself once the current one is answered.

### Fixes
- A waiting decision could be handed back to the terminal while you scrolled its card (the
  heartbeat paused during scrolling). It now keeps running.
- A denial elsewhere in the same session no longer withdraws an unrelated waiting decision.
- Questions waiting in the queue are no longer cut off by Claude Code's default hook timeout.
- A session with a decision waiting can't be cleared from the list.

## 0.1.0 — 2026-11-15

First public release.

### Panel
- Notch panel that lists every Claude Code session, most urgent first, with project,
  current activity, state, and time in state. Floating pill on displays without a notch.
- Opens on hover, and by itself when a session needs you.
- Check button on every row to clear it; "Clear N done" in the header; finished sessions
  clear themselves after a configurable delay.

### Approvals
- Allow, Deny, Deny with a note, Always allow (for explicit rules only), or hand back to
  the terminal, from the panel or with ⌃⌥Y / ⌃⌥N.
- Question cards (options and free text) and plan review cards (approve or send feedback).
- Safeguards: full content with a scroll-to-end gate, a short arming delay after each
  card change, visible markers for hidden characters, fallback to Claude Code's own prompt
  if the app is quit, crashed, or unresponsive.

### Characters
- Six original pixel-art field agents. Each session gets one; its animation shows what
  the session is doing: thinking, looking things up, running a command, building, waiting
  for approval or an answer, done, or error.
- Idle agents patrol beside the notch; point at one in the empty panel to see its trick.

### Security and performance hardening
- The helper only talks to the real app and validates every answer before Claude Code sees it.
- Heartbeats: a hung app falls back to Claude Code's own prompt within 3 seconds.
- Large tool output is dropped before sending; big search results no longer slow tool calls.
- Bad usage values can no longer crash the app; slow or flooding connections are bounded.
- Cards show the full working directory, path, and permission rule; shortcuts are off while
  typing a note; cards for dead sessions are cleaned up.
- See docs/SECURITY-REVIEW.md for both reviews and what is still open.

### Setup
- First-run setup window: explains exactly what will change, offers Watch only, warns if
  Claude Code isn't found or another tool also answers approvals. Nothing changes until you
  click Connect. The menu shows "Set Up…" whenever the app isn't connected.
- Universal (Apple silicon + Intel) downloads built by GitHub Actions on each release tag.
- Uninstall also removes the login item and refuses to half-remove.
- App identifier `io.github.goodguyej.crowsnest`.
- Sounds are off by default.
- The session list shows five sessions per page, with a pager and a count of how many more
  are running; sessions that start but never get a prompt clear themselves.

### Everything else
- Jump to the session's terminal: exact tab in Ghostty and Terminal.app, workspace window
  in VS Code and its forks, pane in tmux.
- Usage strip with the 5-hour and weekly limits and reset countdowns, read from the
  status line (your existing status line keeps working).
- Built-in synthesized sounds, custom sound packs, quiet hours.
- Settings window, launch at login, display choice, diagnostics export.
- Installer that backs up `settings.json`, merges rather than replaces, and uninstalls
  cleanly.
