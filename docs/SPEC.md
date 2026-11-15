# Crow's Nest — Product and Technical Spec

Implementation order is in
[PLAN.md](PLAN.md).

## 1. Purpose

A macOS app that shows the state of every running AI coding-agent session in the MacBook
notch, lets you approve or deny what the agent asks for without switching windows, and
takes you to the right terminal with one click. Built as a personal project.

### Non-goals

- Distribution, licensing, notarization, auto-update, onboarding flows.
- Behaviour is derived from Claude Code's public documentation only; all code, artwork, and
  sounds are original.
- Agents other than Claude Code (the design leaves room for them; see F12).

## 2. Target environment

| Item | Value |
|---|---|
| OS | macOS 14 or later; a notched MacBook gets the notch panel, other displays a floating pill |
| Toolchain | Swift 6 (command line tools are enough; Xcode is optional) → Swift Package Manager plus a bundle script |
| Agent | Claude Code (developed against 2.1.x) |
| Terminals with precise jump | Ghostty 1.4+, Terminal.app, VS Code family, tmux |

## 3. Architecture

```
Claude Code session ──hook──▶ crowsnest-bridge ──unix socket──▶ Crow's Nest.app
        ▲                         │                          ├─ SessionStore (state machine)
        └──── decision JSON ◀─────┘                          ├─ NotchWindow (AppKit panel + SwiftUI)
                                                             ├─ ApprovalQueue
Claude Code status line ──▶ crowsnest-bridge statusline ──socket──▶     ├─ Jumper (per terminal)
                              └─▶ user's previous status line├─ SoundEngine
                                                             ├─ UsageStore
                                                             └─ Notifiers (phone)
```

- **Crow's Nest.app** — menu-bar-less agent app (`LSUIElement`). Owns all state; nothing is
  persisted except settings and a small session cache.
- **crowsnest-bridge** — a tiny native CLI that Claude Code runs as a hook command. It reads
  the hook JSON from stdin, adds terminal context from its environment, sends it to the
  app, and for blocking events prints the app's decision to stdout. It must start fast
  (it runs on every tool call) and must never break the agent: on any error, or if the
  app is not running, it exits 0 with no output, which leaves Claude Code's normal
  behaviour in place.
- **crowsnest-bridge statusline** — wraps the status line slot to capture usage data (F7), then
  runs the previously configured status line so its output is unchanged.
- **Transport** — Unix domain socket at `~/.crowsnest/crowsnest.sock`, mode `0600`. Local only;
  no network listener.

### Wire format

One connection per hook invocation. Each message is a 4-byte big-endian length followed
by UTF-8 JSON.

```json
// bridge → app
{ "v": 1, "agent": "claude", "event": "<hook event name>", "blocking": true,
  "payload": { /* hook stdin JSON, unmodified */ },
  "context": { "termProgram": "ghostty", "tty": "/dev/ttys004", "tmuxPane": "%3",
               "ppidChain": [123, 456], "host": null } }

// app → bridge (blocking events only)
{ "v": 1, "stdout": "<exact JSON for Claude Code>" }   // or
{ "v": 1, "passthrough": true }                         // print nothing
```

The app, not the bridge, builds the hook response JSON, so hook-schema changes only
require an app update.

## 4. Integration with Claude Code

User-level hooks in `~/.claude/settings.json`, all running the same bridge command.

| Hook event | Used for | Blocking |
|---|---|---|
| SessionStart | create session; capture terminal context | no |
| UserPromptSubmit | → working; record prompt as the session title | no |
| PreToolUse | activity line ("Editing foo.swift") | no |
| PostToolUse / PostToolUseFailure | activity line; clears a pending approval | no |
| PermissionRequest | approval card (F3–F5) | **yes**, long timeout |
| Notification | → waiting for input / idle | no |
| SubagentStart / SubagentStop | subagent count on the row | no |
| PreCompact / PostCompact | "compacting" activity | no |
| Stop / StopFailure | → done / error; sound | no |
| SessionEnd | remove session | no |

Installer rules:

1. Back up `settings.json` with a timestamp before every write.
2. Merge, never replace: existing hook entries stay. Our entries are recognisable by the
   bridge path so `uninstall` removes exactly those.
3. Idempotent: running install twice changes nothing.
4. The hook command is guarded (`[ -x bridge ] && bridge …; exit 0`) so deleting the app
   cannot break Claude Code.
5. Claude Code watches its settings files and reloads hooks, so running sessions pick up
   the install without a restart.

### Hook facts this design relies on

Checked against the Claude Code hooks, status line, and settings documentation
(code.claude.com/docs/en/hooks, /statusline, /settings) on 2026-11-14.

- **Common stdin fields:** `session_id`, `transcript_path`, `cwd`, `permission_mode`,
  `hook_event_name`; `agent_id` / `agent_type` inside subagents. `Stop` carries
  `last_assistant_message`.
- **PermissionRequest input:** `tool_name`, `tool_input`, `mcp_server` for MCP tools,
  optional `permission_suggestions`. It fires for MCP tools too.
- **PermissionRequest output:**
  ```json
  { "hookSpecificOutput": { "hookEventName": "PermissionRequest",
      "decision": { "behavior": "allow" } } }
  { "hookSpecificOutput": { "hookEventName": "PermissionRequest",
      "decision": { "behavior": "deny", "message": "why", "interrupt": false } } }
  ```
  `updatedInput` and `updatedPermissions` are allow-only (the latter is how "always
  allow" is expressed, fed from `permission_suggestions`). No output means no decision.
- **Timeouts:** command hooks default to 600 s; a timed-out hook is cancelled and its
  output discarded. Our PermissionRequest entry sets a long explicit timeout. What the
  terminal does after a timeout is not documented (§11 #1).
- **Questions:** a `PreToolUse` hook on `AskUserQuestion` can answer by returning
  `permissionDecision: "allow"` with `updatedInput` = the original input plus an
  `answers` map of question text → chosen label (multi-select labels comma-joined).
- **Plans:** `ExitPlanMode`'s `tool_input` contains `plan` and `planFilePath`. Approve is
  allow; the documented way to push back is deny with a message.
- **Notification types:** `permission_prompt`, `idle_prompt`, `agent_needs_input`,
  `agent_completed`, `elicitation_dialog`, auth and quota types.
- **Environment:** hooks inherit the session's environment, so `TERM_PROGRAM`, `TMUX`,
  `TMUX_PANE` and similar are available to the bridge when the terminal sets them.
- **HTTP hooks exist** (Claude Code POSTs the event to a URL and reads the decision from
  the response). Not used: they cannot capture terminal context, and an unreachable
  server is reported as a hook error whenever the app is closed. The bridge fails silently.

## 5. Session model

```
            UserPromptSubmit            PermissionRequest
  idle ───────────────────▶ working ───────────────────▶ needsApproval
   ▲                         │  ▲                              │
   │        Stop             │  └──── decision / PostToolUse ──┘
   └──── done ◀──────────────┤
                             │ Notification (waiting for input)
                             └──────────▶ waitingForInput ── UserPromptSubmit ─▶ working
  any ── StopFailure ─▶ error        any ── SessionEnd ─▶ (removed)
```

Per session: id, agent, cwd and project name, title (first prompt, truncated), state,
state-since timestamp, last activity line, subagent count, terminal context, host.

Sessions with no event for a configurable time and no live owning process are reaped.
On app launch, sessions are rebuilt lazily from the next event each one sends.

## 6. Features

Each feature lists what "done" means.

### F1. Session monitoring
- Every Claude Code session on this Mac appears within a second of its first event.
- Row shows project, title, state, elapsed time in state, and the latest activity.
- Sorted: needs approval, waiting for input, working, done.
- Keeping the list short:
  - every row has a check button that clears it from the list;
  - "Clear N done" in the header clears every finished session at once;
  - clicking a finished session to jump to it also clears it (setting);
  - finished sessions clear themselves after a delay (default 5 minutes; 1, 15, 60, or never).
  A cleared session is still tracked and returns as soon as it starts a new prompt or its
  state changes, so clearing a working session hides it until it finishes or needs you.
  Sessions in an error state are never cleared automatically.

### F2. Notch panel
- Collapsed: sits flush around the notch; shows an aggregate glyph (colour and motion by
  the most urgent state) and session count.
- Expands on hover or click; collapses on mouse-out after a delay. (No Escape key: the
  panel never holds keyboard focus, and a system-wide Escape shortcut would break other apps.)
- Auto-expands when a session needs approval or input (configurable).
- Never becomes key window unless a text field in it is clicked; visible on all Spaces
  and over full-screen apps.
- No notch (external display, clamshell): floating pill at top centre. Display choice is
  a setting.
- Honours Reduce Motion.

### F3. Approvals
- A permission request shows a card: tool, readable summary (shell command; file path
  with diff preview for edits; server and tool for MCP calls), working directory.
- Actions: Allow, Deny, Deny with a message to the agent.
- Global shortcuts while a card is visible: ⌃⌥Y allow, ⌃⌥N deny. (Not ⌘Y / ⌘N: a
  system-wide ⌘N would hijack "New Window" in whatever app is in front.)
- If the request is answered in the terminal, the card disappears.
- If the app quits or the bridge times out, the terminal prompt still works.
- Multiple pending requests queue per session and across sessions.

### F4. Questions
- When the agent asks a multiple-choice question, show the options (single or
  multi-select) and a free-text field; the answer goes back to the agent.
- Number-key shortcuts for the first options.
- Mechanism: blocking `PreToolUse` hook matched to `AskUserQuestion`, answered with
  `updatedInput.answers` (§4).
- Because that hook runs before the terminal shows the question, the card has an
  "Answer in terminal" action that passes through. If auto-answering is switched off in
  settings, the hook is non-blocking and the card is just a notice with a jump button.

### F5. Plan review
- When the agent presents a plan, render it as Markdown in the panel with Approve and
  Send feedback.
- Mechanism: the permission request for `ExitPlanMode`; Approve returns allow, Send
  feedback returns deny with the feedback as the message.
- "Review in terminal" passes through.

### F6. Jump to terminal
- Clicking a row focuses the terminal that owns the session. The Terminal button on a
  card does the same after handing the decision back.
- The owning app is the nearest ancestor of the agent process that is a regular app; if
  the process tree is gone, the terminal's name (`TERM_PROGRAM`) is used instead.
- Precision by terminal:

  | Terminal | Method | Precision |
  |---|---|---|
  | Ghostty 1.4+ | AppleScript: find the terminal whose `tty` matches, `focus` it | Exact tab and split |
  | Terminal.app | AppleScript: select the tab whose `tty` matches | Exact tab |
  | VS Code family | Open the workspace folder that contains the session's cwd, read from the editor's window-state file | Window (not the individual terminal) |
  | tmux | `select-window` / `select-pane`, then the attached client's terminal app | Pane, then app |
  | Claude desktop app, anything else | Bring the app forward | App |

- The first scripted jump to Ghostty or Terminal triggers macOS's one-time "Crow's Nest wants
  to control…" prompt. If it is declined, or no terminal matches, the app is simply
  brought forward. With ad-hoc signing the prompt can reappear after a rebuild.
- Only values matching a strict device-path or pane-id pattern are put into a script.
- Later: user-defined jump rules (pattern → URL scheme or command).

### F7. Usage
- A strip at the bottom of the expanded panel shows the 5-hour and weekly subscription
  windows: a segmented bar, percent used, and time to reset. Orange from 75%, red from 90%.
- Source: the status line command's stdin, fields `rate_limits.five_hour.used_percentage`,
  `rate_limits.five_hour.resets_at` (epoch seconds), and the same under
  `rate_limits.seven_day`. Present only on subscription plans, only after the first
  response of a session, and either window may be missing; the strip shows what it has
  and hides when it has nothing.
- `crowsnest-bridge statusline` is installed as the status line command. It forwards the
  usage to the app, then runs the status line that was configured before (remembered in
  `~/.crowsnest/previous-statusline.json`) with the same input and passes its output through,
  so the visible status line is unchanged. Uninstall puts the previous command back.
- The last report is kept across relaunches; a window whose reset time has passed is dropped.
- Status lines are drawn by terminal sessions, so numbers appear after the first
  response in a terminal Claude Code session.

### F8. Sounds
- Distinct short synthesized tones for: needs approval, question, done, error. Played
  when a session enters that state; the same sound never stacks within a second.
- Per-event toggle, master volume, quiet hours (start and end hour, may wrap midnight).
- Custom packs: a folder under `~/.crowsnest/sounds/` with files named `approval`,
  `question`, `done`, `error` (wav, aiff, mp3, m4a, or caf). Missing files fall back to
  the built-in tone. `Crow's Nest --export-sounds DIR` writes the built-in set as a template.
- Not built: muting while a macOS Focus mode is on. Reading Focus status needs an
  entitlement an unsigned personal app does not have; quiet hours cover the need.

### F9. Install and setup
- First launch offers to install hooks; Integrations settings show status with Install /
  Repair / Uninstall.
- Detects and reports another tool that also answers permission requests (§10).

### F10. Phone alerts
- Optional forwarding of needs approval, question, done, and error to a phone push
  service (Bark or ntfy).
- Off by default. Setting for how much detail leaves the Mac: event and project name
  only, or including command text.

### F11. Remote sessions
- Monitor and approve sessions running on remote hosts over SSH.
- One command to set up a host; reconnects automatically; multiple hosts.
- Transport is an SSH reverse-forwarded Unix socket; nothing listens on a network port.

### F12. More agents
- Agent support is an adapter (how to install, how its events map to the session model,
  which of F3–F5 it can support).
- Only Claude Code is built until another agent is installed here.

### F13. Settings and housekeeping
- Settings window (from the menu bar icon): General (launch at login, auto-open, answer
  from panel, shortcuts on/off), Sounds, Integrations (hook status, install, uninstall),
  About.
- Launch at login uses the system login-items service, so the app needs a permanent
  location: `scripts/install-app.sh` copies it to `~/Applications`.
- Display choice (built-in notch display, or the display with the menu bar), diagnostics
  export (no prompts, commands, or paths), app icon, `scripts/uninstall.sh`.
- Not built: appearance options, rebinding shortcuts, custom jump rules, custom agents.

### F14. Pixel characters
- A crew of six original field agents, drawn in code as pixel art (`Personas.swift`): each frame
  is 16 rows by 20 columns, the agent on the left and its prop, drawn at the same scale, on the
  right. They are in a
  big-head, small-body style: Bolt the field lead (aviators, earpiece, red tie), Merlo the
  analyst (glasses, navy suit), Kage the infiltrator (beanie, headset, tactical top), Nova the
  pilot (ponytail, aviators), Pesto the handler (moustache, brown suit), and Sleuth the
  investigator (fedora, trench coat). Each session gets one, and keeps it.
- Party tricks are in character: flashing a badge, pulling up intel on a tablet, radioing in,
  saluting, handing over a briefcase, finding a clue.
- Each character is drawn once, standing. Walking, cheering, blinking, and the props for
  every state are composed onto that drawing, so any character can show any state.
- What a working character does depends on what its session is doing:

  | Work | Shown as | When |
  |---|---|---|
  | Thinking | A thought bubble that fills, then lights up | After a prompt, and between tool calls |
  | Looking things up | A magnifying glass | Reading, searching, fetching, look-up tools |
  | Running a command | A terminal prompt with a blinking cursor | Shell commands |
  | Building | Hammering a brick wall | Editing and writing files, subagents |

  The row's status text says the same thing in words.
- Other states: waving beside a "!" (needs approval), looking at a "?" (waiting),
  cheering by the finished wall with a flag (done), sparks (error).
- Idle characters walk back and forth. A session that has started but not been given
  anything paces in its row.
- With nothing running, two of the crew stroll beside the notch (a different pair each
  hour), and the expanded panel shows the whole crew strolling. Pointing at one makes it
  stop, hop, and do its party trick, with its name and motto underneath.
- Settings: characters on or off (off brings back plain status icons), and strolling by
  the notch on or off. Everything is still when Reduce Motion is on.
- The strollers beside the notch redraw twice a second to keep idle CPU use around 1%.

## 7. Failure behaviour

| Situation | Result |
|---|---|
| App not running | Bridge exits 0 silently; Claude Code behaves as stock |
| App hangs on a non-blocking event | Bridge gives up after 150 ms |
| Pending approval, app quits | Bridge sees the socket close, passes through; terminal prompt remains |
| App hung before acknowledging (2 s) or between heartbeats (3 s) | Bridge passes through |
| Something other than the recorded app owns the socket | Bridge sends nothing and passes through |
| Answer not in the exact allowed shape | Bridge discards it and passes through |
| More than 40 requests waiting | Further requests pass through |
| Malformed or unknown event | Logged, ignored |
| Unknown fields in hook JSON | Preserved in raw payload; decoding is lenient |
| Stale socket file | Removed at launch if no listener answers |

## 8. Privacy and security

- All processing is local. No analytics, no accounts.
- The socket is user-only (`0600`) inside a `0700` directory.
- Hook payloads can contain file contents and commands: kept in memory only, never
  written to logs unless debug logging is switched on.
- Phone alerts (F10) are the only feature that sends data off the machine, and are
  opt-in with a detail-level setting.
- "Allow" from the notch has the same effect as allowing in the terminal, so the card
  must show exactly what is being approved, and shortcuts only act on the visible card.

## 9. Performance budget

- Bridge: under 15 ms for non-blocking events, end to end.
- App idle: under 1% CPU, under 80 MB memory.
- Panel animation at display refresh rate.

## 10. Coexistence with other tools

Hooks are additive, so another tool can observe sessions alongside Crow's Nest, but two tools
must not both answer permission requests. The installer reports any other command on the
permission hook and never removes entries it did not create.

## 11. Open questions (resolved by spikes before the phase that needs them)

| # | Question | Needed by |
|---|---|---|
| 1 | Does a real question card's answer reach the agent (the `answers` shape) | live check |
| 2 | Does a plan card appear for `ExitPlanMode`, and does feedback read to the agent as plan feedback | live check |
| 3 | Can the terminal prompt still be used while a card is open | live check |
| 4 | Jump to an exact Ghostty tab, a VS Code window, and a tmux pane with real sessions | live check |

### Phase 3 spike results (Claude Code 2.1.311, 2026-11-14)

- **Confirmed:** a permission hook returning allow runs the tool; deny with a message
  blocks it and the agent quotes the message. Verified with real sessions, including one
  approved through Crow's Nest end to end.
- **Confirmed:** `permission_suggestions` contains mixed kinds (`addDirectories`,
  `setMode`, `addRules`). "Always allow" applies only `addRules` + allow entries.
- **Not testable headlessly:** `AskUserQuestion` and `ExitPlanMode` are unavailable in
  non-interactive sessions, so questions 1–2 need an interactive session.
- **Design does not depend on question 3:** every card has a Terminal action that
  releases the hook, and a card disappears when the hook is cancelled or the same tool
  call completes.
