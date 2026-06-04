# Contributing

Thanks for helping improve Agent Sessions. This project is a local macOS menu bar app, so changes should stay focused, testable, and safe for local developer workflows.

## Development Setup

Requirements:

- macOS 26 or newer.
- Swift 6.2 or newer.
- A local checkout of this repository.

Run tests:

```bash
swift test
```

Run the app from SwiftPM:

```bash
swift run AgentSessions
```

Build the menu-bar `.app` bundle:

```bash
./scripts/build-app.sh
open "./Agent Sessions.app"
```

## Pull Requests

Before opening a pull request:

- Run `swift test`.
- Keep generated build output, `.build/`, `.swiftpm/`, and `Agent Sessions.app` out of commits.
- Include focused tests for parser, state, hook, or persistence behavior when those areas change.
- Update `README.md` or this guide when setup, hook behavior, or user-visible workflows change.
- Keep hook scripts fail-open so Codex and Claude Code continue normally when Agent Sessions is not running.

## Issues

Useful bug reports include:

- macOS and Swift versions.
- Whether the issue affects Codex, Claude Code, or both.
- The visible session state in the menu bar.
- Relevant hook event shape with secrets and private paths removed.
- Steps to reproduce from a clean app launch.

For vulnerabilities, do not open a public issue. Follow [SECURITY.md](SECURITY.md).
