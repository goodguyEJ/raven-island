# Security Review

Crow's Nest sits in the approval path of an AI coding agent that can run shell commands and
edit files. A bug here is not cosmetic: it can mean something runs that you did not approve.
This document records the two reviews the project went through before its first public
release, and what is still open.

## First review

### Method

Two passes over the whole codebase (about 4,000 lines of Swift plus the scripts):

- **Hands-on tests** against the running app, including deliberately hostile input.
- **An independent read** of all the source by a reviewer that had not seen the first
  pass's conclusions.

Fixes were then verified by re-running the hands-on checks and by the automated
end-to-end suite (`scripts/e2e.py`).

### Threat model

1. **The supervised agent misbehaving** or being prompt-injected. It runs as you, so it
   can run anything you already allowed it to run.
2. **Other local processes** running as your user.
3. **Hostile content inside hook payloads**: commands, file paths, plans, questions, and
   session ids reaching the UI, scripts, or the file system.
4. **Plain bugs** that make you approve something you did not mean to, or that hang or
   break Claude Code sessions.
5. **Damage to `~/.claude/settings.json`.**

Out of scope: an attacker who already has root, or who can modify the app bundle.

### Findings and status

"Verified" means re-tested after the fix. "Built" means the fix is in and compiles but
needs a person at the screen to confirm the behaviour.

### High

| # | Finding | Status |
|---|---|---|
| 1 | Any local process, including the agent itself, could approve a waiting request through a test-only `resolve` command on the socket | **Fixed, verified.** The command exists only in debug builds. A release helper rejects it, and a waiting request stays waiting. |
| 2 | Approval cards could hide part of what was being approved: long commands below the fold, edits and files cut off, some input fields not shown, invisible or right-to-left characters drawn as-is | **Fixed, built** (completed in the second review, R2-5). Allow and its shortcut stay off until the content has been scrolled to the end; every input field is listed; requests over 400 lines or 40,000 characters cannot be allowed from the card. |

### Medium

| # | Finding | Status |
|---|---|---|
| 3 | A click or shortcut could land on a card you had not read, if one card replaced another at the moment of the press | **Fixed, built.** Buttons and shortcuts ignore input for 0.6 s after a card changes; a refused shortcut beeps. |
| 4 | If the app hung (rather than quit), a permission request waited on it for up to 24 hours | **Partly fixed here**: only a hang before the card appeared was covered. Completed in the second review (R2-2). |
| 5 | Local processes could exhaust the app's connections and stop its listener | **Fixed, verified**, with slow-trickle connections completed in the second review (R2-7). Waiting requests are capped at 40; the listener retries on resource errors. |
| 6 | The panel, which shows prompts, commands, and file contents, appeared in screen shares and recordings | **Fixed, partly verified.** The panel asks macOS to exclude it from capture (on by default, with a setting). The window reports itself as not shareable; whether every modern capture tool honours that has not been tested. |
| 7 | The Settings "Install" button rewrote settings without installing the helper, leaving hooks that silently did nothing | **Fixed, built.** It copies the helper first and refuses to continue without it. |
| 8 | Installing replaced a symlinked `settings.json` (a dotfiles setup) with a regular file | **Fixed, verified.** The link is kept and the real file is updated. |
| 9 | Markdown links in agent-written plan text could be clickable under a misleading label | **Fixed, built.** Plan text is rendered with links removed. |
| 10 | Several features had never run against a real session | **Partly.** The request queue, fallbacks, and limits now have end-to-end tests. Question and plan cards, real usage numbers, and some terminal jumps still need live confirmation. |

### Low

| # | Finding | Status |
|---|---|---|
| 11 | `sessions` and `pending` returned prompts and folder paths to any local process | **Fixed, verified.** They return states and ids only. |
| 12 | "Always allow" showed its rule on one line and not where it would be saved | **Fixed** (completed in R2-5). The full rule and its destination are shown inside the scrolling area. |
| 13 | An environment variable could redirect the socket that carries decisions | **Fixed, verified.** Honoured in debug builds only. |
| 14 | Uninstalling removed a whole hook group, including other commands in it | **Fixed** (unit test). |
| 15 | Settings backups piled up indefinitely and may contain secrets from `env` | **Partly.** Only the newest five are kept. |
| 16 | Input checks for terminal devices and tmux panes accepted a trailing newline | **Fixed** (unit test). Harmless before the fix. |
| 17 | tmux was looked up on the app's limited PATH, and ran on the main thread | **Fixed, built.** Looked up in the usual locations, run off the main thread with a timeout. |
| 18 | Taking over the status line dropped its `refreshInterval` | **Fixed** (unit test). |
| 19 | Forged events from a local process can add fake sessions or cards, or dismiss a real card (never approve one) | **Open.** |
| 20 | The remembered status-line command is run through a shell on every refresh; one approved write to `~/.crowsnest/previous-statusline.json` gives lasting code execution outside `settings.json` | **Open.** |
| 21 | Uninstalling when the remembered status line is missing clears the status line | **Open.** |
| 22 | No lock against Claude Code writing `settings.json` at the same moment; the file is rewritten with sorted keys | **Open.** |
| 23 | A session row can show "Working" while its card is still waiting, with parallel tool calls | **Open.** |
| 24 | The app is ad-hoc signed: macOS re-asks for Automation permission after rebuilds, and nothing verifies the helper matches the app | **Partly.** A message from a different protocol version is passed through. |

## Second review (2026-11-15)

### Method

Three independent reviewers read the whole codebase (about 5,000 lines), each with one focus:
security and correctness, performance, and a new user's setup and trust. The security reviewer
formed its findings before reading the first review, then checked each "Fixed" claim above
against the code. The top findings were then reproduced against an isolated test copy of the
app, and every fix below has an automated end-to-end check (`scripts/e2e.py`, 28 checks).

### Findings and status

| # | Finding | Severity | Status |
|---|---|---|---|
| R2-1 | The helper trusted whatever process was listening on the socket. A local process that replaced the socket file could approve requests and add a blanket "allow every shell command" rule, with no card shown (reproduced) | High | **Fixed, verified.** The helper checks the process on the other end is the app executable recorded at launch, and sends it nothing otherwise. Every answer is checked against the exact shape Crow's Nest produces: only allow or deny, no rewritten input, and permission rules only if the request itself offered them. |
| R2-2 | After the card appeared, a hung app blocked the session for up to 24 hours (reproduced) | High | **Fixed, verified.** The app sends a heartbeat every second from its main thread while a card is up; the helper falls back to Claude Code's own prompt after 3 seconds of silence. It also stops waiting if Claude Code goes away. |
| R2-3 | A forged usage report with an absurd reset time crashed the app on every launch (reproduced) | High | **Fixed, verified.** Reset times outside a sane window are ignored, and the countdown cannot trap. |
| R2-4 | Large tool results added 0.25–1.2 s to every tool call and doubled the app's memory (measured) | High | **Fixed, verified.** Tool output is dropped before anything else and JSON is parsed with Foundation's fast parser: 20,000 search matches now cost 15 ms (was 244 ms), 100,000 cost 51 ms (was 1.2 s), and memory stays flat. |
| R2-5 | Cards still cut the working directory, file path, and "Always allow" rule; the length check ignored extra fields; ⌃⌥Y worked while typing a deny note | High | **Fixed, built.** All shown in full inside the scrolling area; the length check covers every field; shortcuts are off while a note field is open. |
| R2-6 | Cards for sessions whose process died stayed forever, pinning the panel and the shortcuts | High | **Fixed, built.** Waiting requests are finished when their session is cleaned up. The hook command now uses `exec`, so the helper ends with the hook. |
| R2-7 | Connections trickling one byte at a time were never dropped and tied up the app | Medium | **Fixed, verified.** Each message must arrive within 2 seconds in total; real events still get through while 40 connections trickle. |
| R2-8 | Invisible-character marking missed many characters (line separators, non-breaking spaces, variation selectors, tag characters, blank look-alikes, stacked marks); session rows were not sanitised | Medium | **Fixed** (unit tests). |
| R2-9 | The release menu offered a debug window showing prompts and paths, not hidden from capture | Medium | **Fixed.** Debug builds only. |
| R2-10 | The installed helper was never refreshed after the app updated, and an older status-line entry was never upgraded | Medium | **Fixed.** The app refreshes an installed helper at launch; install upgrades the status-line entry and keeps its refresh setting. |
| R2-11 | The chained status-line command could kill the helper with a broken pipe | Low | **Fixed.** |
| R2-12 | Any accept error other than a few known ones stopped the listener for good | Low | **Fixed.** Only a closed listener stops it. |
| R2-13 | Events are decoded on parallel threads and can be applied out of order | Medium | **Open.** |
| R2-14 | Uninstalling with the helper missing deletes the saved status line and leaves the hooks; the login item is not removed | Medium | **Fixed.** Uninstall falls back to the helper inside the app, refuses to delete `~/.crowsnest` while hooks still point at it, and removes the login item. |
| R2-15 | The open panel uses about 16% CPU while animating (sprites redrawn pixel by pixel) | Medium | **Open.** Idle is under 1%. |
| R2-16 | A tmux socket path from the environment is only checked for a leading "/" | Low | **Open.** |

### Residual risk to be aware of

The helper's trust check relies on files in `~/.crowsnest`, which your user account can write.
A process that can already write anywhere in your home folder (or run arbitrary commands as
you) could replace the helper itself or point the trust record elsewhere. That is outside what
a same-user tool can defend against; the checks above stop the cheap attacks (replacing the
socket, forging answers, broadening permission rules).

## Design properties that held up

- A decision is written only to the connection that created the request. Forged events
  cannot approve anything.
- Card buttons are bound to the request they were drawn for.
- The helper exits silently on every failure path. Quitting, crashing, or hanging the app
  falls back to Claude Code's own prompt (within 3 seconds for a hang).
- The socket is user-only inside a user-only folder; oversized messages are rejected.
- AppleScript and tmux calls take strictly validated values as arguments, never through a
  shell.
- "Always allow" applies only explicit allow rules, never mode changes or folder grants.
- The installer refuses invalid JSON, backs up first, is idempotent, and uninstall
  restores the original content (the same settings; keys are re-sorted).
- Nothing a session says or runs is written to disk. Only preferences and usage
  percentages persist. The diagnostics report contains no prompts, commands, or paths.
  The app makes no network connections.

## Things to know before you run it

- **Automation permission.** Allowing Crow's Nest to control Ghostty or Terminal lets it
  send any scripting command to them. It only uses "focus a tab", built from a validated
  device path, but the permission itself is broad.
- **Managed machines.** A tool that answers permission prompts and registers global
  shortcuts may fall under your organisation's policy. Check before using it on a work
  machine.
