#!/usr/bin/env python3
from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path

ALLOWED_TOOLS = {"codex", "claude", "gemini", "kimi"}


def main() -> int:
    state_path = Path.home() / ".local" / "state" / "quickshell" / "user" / "orbitbar" / "state.json"
    if not state_path.exists():
        return notify("Orbitbar", "No live agent sessions found.")

    try:
        payload = json.loads(state_path.read_text(encoding="utf-8"))
    except Exception:
        return notify("Orbitbar", "Could not read Orbitbar state.")

    sessions = payload.get("sessions", [])
    if not isinstance(sessions, list) or not sessions:
        return notify("Orbitbar", "No live agent sessions found.")

    agent_sessions = [
        session for session in sessions
        if isinstance(session, dict) and str(session.get("tool") or "").strip() in ALLOWED_TOOLS
    ]
    if not agent_sessions:
        return notify("Orbitbar", "No live agent sessions found.")

    address = str((agent_sessions[0] or {}).get("window_address") or "").strip()
    if not address:
        return notify("Orbitbar", "Latest agent session has no window address.")

    helper = Path(__file__).with_name("focus_terminal.py")
    subprocess.run(
        [
            "python",
            str(helper),
            "--address",
            address,
            "--special-name",
            "agents",
            "--move-to-special",
            "--show-special",
            "--focus",
        ],
        check=False,
    )
    return 0


def notify(summary: str, body: str) -> int:
    if shutil.which("notify-send"):
        subprocess.run(["notify-send", summary, body, "-a", "Orbitbar"], check=False)
    else:
        print(f"{summary}: {body}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
