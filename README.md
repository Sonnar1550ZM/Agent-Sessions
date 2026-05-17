# AgentsBar

AgentsBar is a local macOS menu bar app for tracking multiple Codex and Claude Code sessions from one menu bar item.

## MVP

- SwiftUI `MenuBarExtra` app.
- Local event receiver: `http://127.0.0.1:7823/event`.
- Sessions are keyed by `agent + sessionId`.
- State persists to `~/Library/Application Support/AgentsBar/state.json`.
- Menu bar label shows Codex and Claude icons side by side.
- Each icon uses the mono asset normally and switches to the color asset while Working.
- Waiting sessions tint the mono icon yellow.
- Waiting takes precedence over Working in the menu bar aggregate state.
- Menu groups sessions under `Codex` and `Claude Code`.
- Idle and Ended history is kept to the latest 5 sessions per agent and hidden after 24 hours.

## Build

```bash
swift test
swift run AgentsBar
```

To build a menu-bar-only `.app` bundle:

```bash
./scripts/build-app.sh
open ./AgentsBar.app
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

## Hooks

Hook scripts live in `scripts/`:

- `scripts/agentsbar-codex-hook.sh`
- `scripts/agentsbar-claude-hook.sh`

They read hook JSON from stdin, post to `127.0.0.1:7823/event`, and always exit `0` so Codex or Claude Code continues normally when AgentsBar is not running.
