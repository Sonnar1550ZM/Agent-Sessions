#!/bin/bash
set -u

HOST="${AGENTSBAR_HOST:-127.0.0.1}"
PORT="${AGENTSBAR_PORT:-7823}"
HOOK_JSON="$(cat)"

find_agent_pid() {
  local pid="$PPID"
  local max=8
  while [ "$max" -gt 0 ] && [ -n "$pid" ] && [ "$pid" -gt 1 ]; do
    local name
    name="$(ps -o comm= -p "$pid" 2>/dev/null)"
    case "$name" in
      *codex*|*Codex*) echo "$pid"; return 0 ;;
    esac
    pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
    max=$((max - 1))
  done
  return 1
}

AGENT_PID="$(find_agent_pid 2>/dev/null || true)"

payload="$(
  HOOK_JSON="$HOOK_JSON" TERM_PROGRAM="${TERM_PROGRAM:-}" AGENT_PID="${AGENT_PID:-}" /usr/bin/python3 - <<'PY' 2>/dev/null
import json, os, sys

try:
    event = json.loads(os.environ.get("HOOK_JSON") or "{}")
except Exception:
    event = {}

hook_event = event.get("hook_event_name") or ""
if hook_event in ("UserPromptSubmit", "PreToolUse"):
    state = "Working"
elif hook_event == "Notification":
    state = "Waiting"
elif hook_event in ("SessionEnd",):
    state = "Ended"
else:
    state = "Idle"

term_map = {
    "iTerm.app": "iTerm",
    "Apple_Terminal": "Terminal",
    "vscode": "VS Code",
    "WarpTerminal": "Warp",
    "ghostty": "Ghostty",
    "Hyper": "Hyper",
    "WezTerm": "WezTerm",
    "kitty": "kitty",
    "tabby": "Tabby",
    "alacritty": "Alacritty",
}

try:
    pid = int(os.environ.get("AGENT_PID") or 0) or None
except Exception:
    pid = None

def sanitized_title(value):
    if not isinstance(value, str):
        return ""
    title = " ".join(value.split())
    return title[:160]

def prompt_title(event):
    if hook_event != "UserPromptSubmit":
        return ""
    for key in ("prompt", "message", "input", "text", "user_prompt", "userPrompt"):
        title = sanitized_title(event.get(key))
        if title:
            return title
    payload = event.get("payload")
    if isinstance(payload, dict):
        for key in ("prompt", "message", "input", "text", "user_prompt", "userPrompt"):
            title = sanitized_title(payload.get(key))
            if title:
                return title
    return ""

payload = {
    "agent": "Codex",
    "sessionId": event.get("session_id") or event.get("sessionId") or "default",
    "state": state,
    "title": prompt_title(event),
    "cwd": event.get("cwd") or "",
    "event": hook_event,
    "terminal": term_map.get(os.environ.get("TERM_PROGRAM") or "", os.environ.get("TERM_PROGRAM") or ""),
    "pid": pid,
}
sys.stdout.write(json.dumps(payload, separators=(",", ":")))
PY
)"

if [ -z "${payload:-}" ]; then
  payload='{"agent":"Codex","sessionId":"default","state":"Idle"}'
fi

curl -fsS -m 1 -X POST "http://${HOST}:${PORT}/event" \
  -H 'Content-Type: application/json' \
  --data-raw "$payload" >/dev/null 2>&1 &

exit 0
