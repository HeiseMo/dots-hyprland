#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path


DEFAULT_STATE_PATH = Path.home() / ".local" / "state" / "quickshell" / "user" / "orbitbar" / "state.json"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Send an Orbitbar choice back to a terminal session")
    parser.add_argument("--pid", required=True, type=int)
    parser.add_argument("--session-id", required=True)
    parser.add_argument("--choice-id", required=True)
    parser.add_argument("--state-path", default=str(DEFAULT_STATE_PATH))
    parser.add_argument("--response")
    return parser.parse_args()


def resolve_response_from_state(state_path: Path, session_id: str, choice_id: str) -> str:
    payload = json.loads(state_path.read_text(encoding="utf-8"))
    sessions = payload.get("sessions", [])
    for session in sessions:
        if not isinstance(session, dict) or session.get("session_id") != session_id:
            continue

        pending_action = session.get("pending_action")
        if isinstance(pending_action, dict):
            choices = pending_action.get("choices", [])
            if isinstance(choices, list):
                for choice in choices:
                    if isinstance(choice, dict) and choice.get("id") == choice_id:
                        response = choice.get("response")
                        if isinstance(response, str) and response:
                            return response

        legacy_choices = session.get("options", [])
        if isinstance(legacy_choices, list):
            for choice in legacy_choices:
                if isinstance(choice, dict) and choice.get("id") == choice_id:
                    response = choice.get("response")
                    if isinstance(response, str) and response:
                        return response

    raise SystemExit(f"Unable to resolve choice '{choice_id}' for session '{session_id}' from {state_path}")


def main() -> int:
    args = parse_args()
    if args.response:
        payload = args.response
    else:
        payload = resolve_response_from_state(Path(args.state_path), args.session_id, args.choice_id)

    tty_path = Path(os.readlink(f"/proc/{args.pid}/fd/0"))
    if not tty_path.exists():
        raise SystemExit(f"TTY path does not exist: {tty_path}")

    fd = os.open(str(tty_path), os.O_WRONLY | os.O_NONBLOCK)
    try:
        os.write(fd, payload.encode("utf-8"))
    finally:
        os.close(fd)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
