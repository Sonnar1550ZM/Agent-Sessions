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

hook_event = event.get("hook_event_name") or ""

def first_string(*values):
    for value in values:
        if isinstance(value, str) and value.strip():
            return value.strip()
    return ""

def notification_type(event):
    candidates = [
        event.get("notification_type"),
        event.get("notificationType"),
        event.get("type"),
        event.get("name"),
    ]
    for key in ("notification", "payload"):
        value = event.get(key)
        if isinstance(value, dict):
            candidates.extend([
                value.get("notification_type"),
                value.get("notificationType"),
                value.get("type"),
                value.get("name"),
            ])
    return first_string(*candidates).lower()

def tool_name(event):
    candidates = [
        event.get("tool_name"),
        event.get("toolName"),
        event.get("name"),
    ]
    for key in ("tool", "tool_use", "toolUse", "payload"):
        value = event.get(key)
        if isinstance(value, dict):
            candidates.extend([
                value.get("name"),
                value.get("tool_name"),
                value.get("toolName"),
            ])
    return first_string(*candidates)

def requires_user_input_tool(name):
    compact = "".join(ch for ch in name.lower() if ch.isalnum())
    return (
        "askuserquestion" in compact
        or "requestuserinput" in compact
    )

def session_start_source(event):
    return first_string(event.get("source"), event.get("session_start_source")).lower()

def waits_for_user(event):
    if hook_event in ("PermissionRequest", "AskUserQuestion"):
        return True
    if hook_event == "PreToolUse" and requires_user_input_tool(tool_name(event)):
        return True
    if hook_event == "Notification":
        kind = notification_type(event)
        return kind in (
            "permission_prompt",
            "permission_request",
            "elicitation_dialog",
            "ask_user_question",
            "choice_prompt",
            "choice_dialog",
            "question_prompt",
        )
    return False

state = os.environ.get("STATE") or "Working"
if hook_event == "SessionStart" and session_start_source(event) == "resume":
    sys.exit(0)
if hook_event == "Notification" and not waits_for_user(event):
    sys.exit(0)
if hook_event == "PreCompact":
    state = "Working"
elif hook_event == "PostCompact":
    state = "Idle"
elif waits_for_user(event):
    state = "Waiting"
elif state == "Auto":
    state = "Working"
elif state == "ToolFail":
    state = "Idle" if event.get("is_interrupt") is True else "Working"
elif state == "Waiting":
    state = "Working"

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
    if hook_event == "PreCompact":
        return "Compacting context"
    if hook_event == "PostCompact":
        return "Context compacted"
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

title = prompt_title(event)
payload = {
    "agent": "Claude",
    "sessionId": session_id,
    "state": state,
    "title": title,
    "cwd": event.get("cwd") or "",
    "event": hook_event,
    "terminal": term_map.get(os.environ.get("TERM_PROGRAM") or "", os.environ.get("TERM_PROGRAM") or ""),
    "pid": pid,
    "transcriptPath": transcript_path,
    "latestUserPrompt": title if hook_event == "UserPromptSubmit" and title else None,
}
sys.stdout.write(json.dumps(payload, separators=(",", ":")))
PY
)"

if [ -z "${payload:-}" ]; then
  exit 0
fi

if [ "${AGENT_SESSIONS_DRY_RUN:-}" = "1" ]; then
  printf '%s\n' "$payload"
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
