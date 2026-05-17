#!/bin/bash
set -u

STATE="${1:-Working}"
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
      *claude*|*Claude*) echo "$pid"; return 0 ;;
    esac
    pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
    max=$((max - 1))
  done
  return 1
}

AGENT_PID="$(find_agent_pid 2>/dev/null || true)"

payload="$(
  STATE="$STATE" HOOK_JSON="$HOOK_JSON" TERM_PROGRAM="${TERM_PROGRAM:-}" AGENT_PID="${AGENT_PID:-}" /usr/bin/python3 - <<'PY' 2>/dev/null
import json, os, sys

try:
    event = json.loads(os.environ.get("HOOK_JSON") or "{}")
except Exception:
    event = {}

state = os.environ.get("STATE") or "Working"
if state == "Auto":
    state = "Working"
elif state == "ToolFail":
    state = "Idle" if event.get("is_interrupt") is True else "Working"
elif state == "Waiting":
    message = (event.get("message") or "").lower()
    state = "Waiting" if "permission" in message or "confirm" in message else "Idle"

hook_event = event.get("hook_event_name") or ""

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

def clean_text(value):
    if not isinstance(value, str):
        return ""
    return " ".join(value.split())[:160]

transcript_path = event.get("transcript_path") or event.get("transcriptPath") or ""
session_id = event.get("session_id") or event.get("sessionId") or ""
if not session_id and isinstance(transcript_path, str) and transcript_path:
    name = os.path.basename(transcript_path)
    if name.endswith(".jsonl"):
        session_id = name[:-6]

title = ""
if hook_event == "UserPromptSubmit":
    title = clean_text(
        event.get("prompt")
        or event.get("user_prompt")
        or event.get("content")
        or event.get("message")
    )

payload = {
    "agent": "Claude Code",
    "sessionId": session_id or "default",
    "state": state,
    "title": title,
    "cwd": event.get("cwd") or "",
    "event": hook_event,
    "terminal": term_map.get(os.environ.get("TERM_PROGRAM") or "", os.environ.get("TERM_PROGRAM") or ""),
    "pid": pid,
}
sys.stdout.write(json.dumps(payload, separators=(",", ":")))
PY
)"

if [ -z "${payload:-}" ]; then
  payload="{\"agent\":\"Claude Code\",\"sessionId\":\"default\",\"state\":\"${STATE}\"}"
fi

if [ "$STATE" = "Ended" ]; then
  curl -fsS -m 2 -X POST "http://${HOST}:${PORT}/event" \
    -H 'Content-Type: application/json' \
    --data-raw "$payload" >/dev/null 2>&1 || true
else
  curl -fsS -m 1 -X POST "http://${HOST}:${PORT}/event" \
    -H 'Content-Type: application/json' \
    --data-raw "$payload" >/dev/null 2>&1 &
fi

exit 0
