# Contributing

This is a personal project, shared in case it is useful. Issues and pull requests are
welcome, with no promise of how quickly they are looked at.

## Before you open a pull request

```sh
./scripts/test.sh          # unit tests
python3 scripts/e2e.py     # end-to-end tests against an isolated debug instance
./scripts/build-app.sh     # the app bundle still builds
```

- Keep `CrowsNestCore` free of AppKit so it stays unit-testable.
- Anything that touches approvals, the socket, or the installer needs a test, and a note
  in [docs/SECURITY-REVIEW.md](docs/SECURITY-REVIEW.md) if it changes the security model.
- All artwork and sounds must be original. Please don't add assets from other apps or
  games.
- UI changes: include a before/after from `Crow's Nest --snapshot DIR`.

## Reporting bugs

Use the bug report template. A diagnostic report (Settings → About → Export Diagnostic
Report) helps and contains no prompts, commands, or file paths. Security problems go
through [SECURITY.md](SECURITY.md), not public issues.
