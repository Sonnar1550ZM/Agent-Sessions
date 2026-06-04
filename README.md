# Agent Sessions

Agent Sessions is a local macOS menu bar app for tracking multiple Codex and Claude Code sessions from one menu bar item.

It is designed for maintainers and developers who run several coding-agent sessions at once and need a compact, local status surface for work in progress, waiting approvals, and recent session context.

[![CI](https://github.com/Sonnar1550ZM/Agent-Sessions/actions/workflows/ci.yml/badge.svg)](https://github.com/Sonnar1550ZM/Agent-Sessions/actions/workflows/ci.yml)

## Features

- AppKit `NSStatusItem` menu bar app.
- Local event receiver: `http://127.0.0.1:7823/event`.
- Sessions are keyed by `agent + sessionId`.
- State persists to `~/Library/Application Support/Agent Sessions/state.json`.
- Codex and Claude appear as separate status items that open the same shared menu.
- Provider icons use mono assets normally and switch to color assets while working.
- Waiting sessions tint the provider icon yellow and take precedence over Working in aggregate state.
- Menu groups sessions under custom `NSMenuItem.view` headers for `Codex` and `Claude`.
- Long session titles wrap at about 30 characters in the menu.
- The drop-down keeps the latest 5 visible sessions per agent across all states and hides inactive history after 24 hours.

## Requirements

- macOS 26 or newer.
- Swift 6.2 or newer.
- Codex and/or Claude Code hook events posted to the local receiver.

## Build

```bash
swift test
swift run AgentSessions
```

To build a menu-bar-only `.app` bundle:

```bash
./scripts/build-app.sh
open "./Agent Sessions.app"
```

## Event API

Send events with JSON:

```bash
curl -fsS -X POST http://127.0.0.1:7823/event \
  -H 'Content-Type: application/json' \
  --data '{"agent":"Codex","sessionId":"codex-a","state":"Working","title":"Implement MVP","cwd":"/tmp/project","event":"UserPromptSubmit","terminal":"Warp","pid":12345}'
```

Accepted fields:

- `agent`: `Codex`, `Claude`, or `Claude Code`.
- `sessionId` or `session_id`: session identifier.
- `state`: `Working`, `Waiting`, `Idle`, or `Ended`.
- `title`
- `cwd`
- `event`
- `terminal`
- `pid`
- `updatedAt` or `updated_at`
- `parentSessionId` or `parent_session_id`
- `subagentNickname` or `subagent_nickname`
- `subagentRole` or `subagent_role`
- `subagentDepth` or `subagent_depth`
- `transcriptPath` or `transcript_path` for Claude transcript/subagent detection

## Hooks

Hook scripts live in `scripts/`:

- `scripts/agent-sessions-codex-hook.sh`
- `scripts/agent-sessions-claude-hook.sh`

They read hook JSON from stdin, post to `127.0.0.1:7823/event`, and always exit `0` so Codex or Claude Code continues normally when Agent Sessions is not running.

## Privacy and Security

Agent Sessions is local-first. The app listens on loopback, stores state under the current user's Application Support directory, and does not require API keys. Hook scripts post local status events to the receiver and are written to fail open so agent workflows continue if the menu bar app is not running.

Report vulnerabilities using the process in [SECURITY.md](SECURITY.md).

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, test, and review expectations.

## License

Agent Sessions is licensed under the [MIT License](LICENSE).
