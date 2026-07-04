# Agent Sessions

Agent Sessions is a local macOS menu bar app for tracking multiple Codex and Claude Code sessions from one menu bar item.

## MVP

- AppKit `NSStatusItem` menu bar app.
- Local event receiver: `http://127.0.0.1:7823/event`.
- Sessions are keyed by `agent + sessionId`.
- State persists to `~/Library/Application Support/Agent Sessions/state.json`.
- Menu bar label shows Codex and Claude as separate status items that open the same shared menu.
- Each icon uses the mono asset normally and switches to the color asset while Working.
- Waiting sessions tint the mono icon yellow.
- Menu state symbols use matching colors: Codex Working `#006EFE`, Claude Working `#cf8366`, and Waiting yellow.
- Waiting takes precedence over Working in the menu bar aggregate state.
- Menu groups sessions under custom `NSMenuItem.view` headers for `Codex` and `Claude Code`.
- Long session titles wrap at about 30 characters in the menu.
- The drop-down keeps the latest 5 visible sessions per agent across all states and hides inactive history after 24 hours.

## Build

```bash
swift test
swift run AgentSessions
```

To build the menu-bar-only `.app` bundle and install it to `/Applications`:

```bash
./scripts/build-app.sh
open "/Applications/Agent Sessions.app"
```

The app is assembled and ad-hoc signed on local disk, then installed to `/Applications` (override with `AGENT_SESSIONS_INSTALL_DIR`). Running it from local disk keeps Launch at Login working even before the Google Drive volume mounts.

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

Hook scripts ship as app resources:

- `Sources/AgentSessions/Resources/hooks/agent-sessions-codex-hook.sh`
- `Sources/AgentSessions/Resources/hooks/agent-sessions-claude-hook.sh`

They read hook JSON from stdin, post to `127.0.0.1:7823/event`, and always exit `0` so Codex or Claude Code continues normally when Agent Sessions is not running.

Install them either way:

- In-app: Settings > Hooks > Install (per agent).
- CLI: `./scripts/install-hooks.sh` (add `AGENT_SESSIONS_TRUST_PROJECT=1` to also trust this checkout in Codex).

Both copy the scripts to `~/Library/Application Support/Agent Sessions/hooks/` and register those copies in `~/.codex/hooks.json`, `~/.codex/config.toml` (`codex_hooks = true`), and `~/.claude/settings.json`, backing up each existing file as `<name>.bak.<timestamp>` first.
