# Security

## Reporting a vulnerability

Please report security problems privately through GitHub's
[private vulnerability reporting](https://github.com/goodguyEJ/raven-island/security/advisories/new)
rather than in a public issue. Include what you found, how to reproduce it, and what an
attacker could do with it.

This is a personal project maintained in spare time, so there is no response-time promise,
but reports are read and taken seriously.

## Security model in brief

- Requests can only be answered from the panel. The helper only talks to the app executable
  recorded at launch, and accepts only allow or deny answers in the exact shape Raven Island
  produces, never a broader permission rule than the request offered.
- Allow stays off until a card's content has been scrolled to the end, and for a moment
  after a card appears. Very large requests can only be denied or sent to the terminal.
- If the app stops responding (no heartbeat for 3 seconds), quits, or crashes, a request falls
  back to Claude Code's own prompt.
- The socket is readable only by your user. The app makes no network connections and
  writes nothing a session says or runs to disk.
- The panel asks macOS to keep it out of screen sharing and recordings (on by default).

The full review, including what is still open, is in
[docs/SECURITY-REVIEW.md](docs/SECURITY-REVIEW.md).
