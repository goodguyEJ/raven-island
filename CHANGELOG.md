# Changelog

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
