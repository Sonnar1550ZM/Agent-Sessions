#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

ROOT="$ROOT" /usr/bin/python3 - <<'PY'
import json
import os
import pathlib
import shutil
from datetime import datetime

root = pathlib.Path(os.environ["ROOT"])
home = pathlib.Path.home()
stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
trust_project = os.environ.get("AGENT_SESSIONS_TRUST_PROJECT") == "1"

codex_hooks_path = home / ".codex" / "hooks.json"
codex_config_path = home / ".codex" / "config.toml"
claude_settings_path = home / ".claude" / "settings.json"

# Canonical scripts ship inside the app target's resources; installed copies
# live in Application Support so registered paths survive checkout moves.
# Keep this in sync with AgentHookInstaller in AgentSessionsCore.
script_source_dir = root / "Sources" / "AgentSessions" / "Resources" / "hooks"
install_dir = home / "Library" / "Application Support" / "Agent Sessions" / "hooks"


def install_script(name: str) -> pathlib.Path:
    install_dir.mkdir(parents=True, exist_ok=True)
    destination = install_dir / name
    shutil.copy2(script_source_dir / name, destination)
    destination.chmod(0o755)
    return destination


codex_script = install_script("agent-sessions-codex-hook.sh")
claude_script = install_script("agent-sessions-claude-hook.sh")
CODEX_HOOK_MARKERS = (
    "agent-sessions-codex-hook",
)
CLAUDE_HOOK_MARKERS = (
    "agent-sessions-claude-hook",
)
CODEX_FEATURE_MARKER = "agent-sessions-managed-codex-hooks"


def backup(path: pathlib.Path) -> None:
    if path.exists():
        shutil.copy2(path, path.with_name(path.name + f".bak.{stamp}"))


def load_json(path: pathlib.Path) -> dict:
    if not path.exists():
        return {}
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def save_json(path: pathlib.Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(value, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")


def replace_managed_hook(entry: dict, new_command: str, markers: tuple[str, ...]) -> None:
    hooks = entry.setdefault("hooks", [])
    kept = []
    for hook in hooks:
        command = hook.get("command", "") if isinstance(hook, dict) else ""
        if any(marker in command for marker in markers):
            continue
        kept.append(hook)
    kept.append({"type": "command", "command": new_command})
    entry["hooks"] = kept


def remove_managed_event_hooks(hooks: dict, event_name: str, markers: tuple[str, ...]) -> None:
    entries = hooks.get(event_name)
    if not isinstance(entries, list):
        return

    kept_entries = []
    for entry in entries:
        if not isinstance(entry, dict):
            kept_entries.append(entry)
            continue

        event_hooks = entry.get("hooks")
        if not isinstance(event_hooks, list):
            kept_entries.append(entry)
            continue

        kept_hooks = []
        for hook in event_hooks:
            command = hook.get("command", "") if isinstance(hook, dict) else ""
            if any(marker in command for marker in markers):
                continue
            kept_hooks.append(hook)

        if kept_hooks:
            updated_entry = dict(entry)
            updated_entry["hooks"] = kept_hooks
            kept_entries.append(updated_entry)

    if kept_entries:
        hooks[event_name] = kept_entries
    else:
        hooks.pop(event_name, None)


def ensure_codex_hooks() -> None:
    backup(codex_hooks_path)
    data = load_json(codex_hooks_path)
    hooks = data.setdefault("hooks", {})
    command = f"'{codex_script}' # agent-sessions-codex-hook"

    defaults = {
        "PostToolUse": {},
        "PostCompact": {},
        "PreToolUse": {},
        "PreCompact": {},
        "PermissionRequest": {},
        "SessionStart": {"matcher": "startup|resume"},
        "Stop": {},
        "UserPromptSubmit": {},
    }

    for event_name, default_entry in defaults.items():
        entries = hooks.setdefault(event_name, [])
        if not entries:
            entries.append(dict(default_entry))
        for entry in entries:
            if event_name in ("PostToolUse", "PreToolUse") and entry.get("matcher") == "Bash":
                entry.pop("matcher", None)
            for key, value in default_entry.items():
                entry.setdefault(key, value)
            replace_managed_hook(entry, command, CODEX_HOOK_MARKERS)

    save_json(codex_hooks_path, data)


def ensure_claude_hooks() -> None:
    backup(claude_settings_path)
    data = load_json(claude_settings_path)
    hooks = data.setdefault("hooks", {})
    states = {
        "SessionEnd": "Ended",
        "Notification": "Waiting",
        "PermissionRequest": "Waiting",
        "PreCompact": "Working",
        "PostCompact": "Idle",
        "PostToolUseFailure": "ToolFail",
        "SessionStart": "Idle",
        "Stop": "Idle",
        "PreToolUse": "Working",
        "UserPromptSubmit": "Working",
        "PostToolUse": "Auto",
    }

    for event_name, state in states.items():
        entries = hooks.setdefault(event_name, [])
        if not entries:
            entries.append({})
        command = f"'{claude_script}' {state} # agent-sessions-claude-hook"
        for entry in entries:
            replace_managed_hook(entry, command, CLAUDE_HOOK_MARKERS)

    for event_name in ("Elicitation",):
        remove_managed_event_hooks(hooks, event_name, CLAUDE_HOOK_MARKERS)

    save_json(claude_settings_path, data)


def ensure_codex_config() -> None:
    backup(codex_config_path)
    codex_config_path.parent.mkdir(parents=True, exist_ok=True)
    text = codex_config_path.read_text(encoding="utf-8") if codex_config_path.exists() else ""
    lines = text.splitlines()

    features_index = None
    for index, line in enumerate(lines):
        if line.strip() == "[features]":
            features_index = index
            break

    if features_index is None:
        if lines and lines[-1].strip():
            lines.append("")
        lines.extend(["[features]", f"codex_hooks = true  # {CODEX_FEATURE_MARKER}"])
    else:
        next_section = len(lines)
        for index in range(features_index + 1, len(lines)):
            stripped = lines[index].strip()
            if stripped.startswith("[") and stripped.endswith("]"):
                next_section = index
                break

        codex_hooks_index = None
        for index in range(features_index + 1, next_section):
            if lines[index].split("#", 1)[0].strip().startswith("codex_hooks"):
                codex_hooks_index = index
                break

        if codex_hooks_index is None:
            lines.insert(features_index + 1, f"codex_hooks = true  # {CODEX_FEATURE_MARKER}")
        else:
            lines[codex_hooks_index] = f"codex_hooks = true  # {CODEX_FEATURE_MARKER}"

    codex_config_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def ensure_agent_sessions_project_trust() -> None:
    text = codex_config_path.read_text(encoding="utf-8") if codex_config_path.exists() else ""
    project_header = f'[projects."{root}"]'
    if project_header in text:
        return
    with codex_config_path.open("a", encoding="utf-8") as handle:
        handle.write("\n")
        handle.write(project_header + "\n")
        handle.write('trust_level = "trusted"\n')


ensure_codex_hooks()
ensure_claude_hooks()
ensure_codex_config()
if trust_project:
    ensure_agent_sessions_project_trust()

print(f"Installed hook scripts in {install_dir}")
print(f"Updated {codex_hooks_path}")
print(f"Updated {codex_config_path}")
print(f"Updated {claude_settings_path}")
if not trust_project:
    print("Skipped project trust update; set AGENT_SESSIONS_TRUST_PROJECT=1 to enable it.")
PY
