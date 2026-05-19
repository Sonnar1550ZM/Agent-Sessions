#!/bin/bash
set -u

STATE="${1:-Working}"
HOST="${AGENT_SESSIONS_HOST:-127.0.0.1}"
PORT="${AGENT_SESSIONS_PORT:-7823}"
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

def sanitized_title(value):
    if not isinstance(value, str):
        return ""
    title = " ".join(value.split())
    return title[:160]

def text_from_value(value):
    if isinstance(value, str):
        return value
    if isinstance(value, dict):
        for key in ("prompt", "message", "input", "text", "user_prompt", "userPrompt", "content"):
            text = text_from_value(value.get(key))
            if text:
                return text
    if isinstance(value, list):
        parts = []
        for item in value:
            text = text_from_value(item)
            if text:
                parts.append(text)
        return " ".join(parts)
    return ""

def prompt_title(event):
    if hook_event != "UserPromptSubmit":
        return ""
    for key in ("prompt", "message", "input", "text", "user_prompt", "userPrompt", "content"):
        title = sanitized_title(text_from_value(event.get(key)))
        if title:
            return title
    payload = event.get("payload")
    if isinstance(payload, dict):
        for key in ("prompt", "message", "input", "text", "user_prompt", "userPrompt", "content"):
            title = sanitized_title(text_from_value(payload.get(key)))
            if title:
                return title
    return ""

transcript_path = event.get("transcript_path") or event.get("transcriptPath") or ""
session_id = event.get("session_id") or event.get("sessionId") or ""
if not session_id and isinstance(transcript_path, str) and transcript_path:
    name = os.path.basename(transcript_path)
    if name.endswith(".jsonl"):
        session_id = name[:-6]

if not session_id or session_id == "default":
    sys.exit(0)

payload = {
    "agent": "Claude Code",
    "sessionId": session_id,
    "state": state,
    "title": prompt_title(event),
    "cwd": event.get("cwd") or "",
    "event": hook_event,
    "terminal": term_map.get(os.environ.get("TERM_PROGRAM") or "", os.environ.get("TERM_PROGRAM") or ""),
    "pid": pid,
    "transcriptPath": transcript_path,
}
sys.stdout.write(json.dumps(payload, separators=(",", ":")))
PY
)"

if [ -z "${payload:-}" ]; then
  exit 0
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
