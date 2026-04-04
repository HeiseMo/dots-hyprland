#!/usr/bin/env python3
from __future__ import annotations

import argparse
import asyncio
import fcntl
import json
import os
import re
import signal
import sqlite3
import subprocess
import time
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any


def now_iso() -> str:
    return datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def compact_text(value: str, limit: int = 80) -> str:
    text = " ".join(value.split())
    if len(text) <= limit:
        return text
    return text[: limit - 1].rstrip() + "…"


def format_token_count(value: Any) -> str:
    try:
        tokens = int(value or 0)
    except (TypeError, ValueError):
        return ""

    if tokens <= 0:
        return ""
    if tokens >= 1_000_000:
        return f"{tokens / 1_000_000:.1f}M tok"
    if tokens >= 1_000:
        return f"{tokens / 1_000:.1f}k tok"
    return f"{tokens} tok"


@dataclass
class SessionState:
    session_id: str
    payload: dict[str, Any] = field(default_factory=dict)

    def merge(self, incoming: dict[str, Any]) -> None:
        for key, value in incoming.items():
            if key == "session_id":
                continue
            if value is None:
                self.payload.pop(key, None)
                continue
            self.payload[key] = value

        self.payload["session_id"] = self.session_id
        self.payload["updated_at"] = now_iso()

    def as_dict(self) -> dict[str, Any]:
        return dict(self.payload)


class OrbitbarBridge:
    def __init__(self, socket_path: Path, state_path: Path) -> None:
        self.socket_path = socket_path
        self.state_path = state_path
        self.lock_path = state_path.with_suffix(".lock")
        self.special_workspace_name = "agents"
        self.codex_state_db_path = Path.home() / ".codex" / "state_5.sqlite"
        self.codex_log_db_path = Path.home() / ".codex" / "logs_1.sqlite"
        self.codex_session_index_path = Path.home() / ".codex" / "session_index.jsonl"
        self.event_sessions: dict[str, SessionState] = {}
        self.discovered_sessions: dict[str, dict[str, Any]] = {}
        self.managed_terminal_workspaces: dict[str, str] = {}
        self.server: asyncio.AbstractServer | None = None
        self.discovery_task: asyncio.Task[None] | None = None
        self.lock_handle: Any | None = None

    async def start(self) -> None:
        self.socket_path.parent.mkdir(parents=True, exist_ok=True)
        self.state_path.parent.mkdir(parents=True, exist_ok=True)
        self.acquire_singleton_lock()

        if self.socket_path.exists():
            self.socket_path.unlink()

        self.server = await asyncio.start_unix_server(
            self.handle_client,
            path=str(self.socket_path),
        )
        self.discovery_task = asyncio.create_task(self.discovery_loop())
        await self.flush_state()

    async def stop(self) -> None:
        if self.server is not None:
            self.server.close()
            await self.server.wait_closed()
            self.server = None

        if self.discovery_task is not None:
            self.discovery_task.cancel()
            try:
                await self.discovery_task
            except asyncio.CancelledError:
                pass
            self.discovery_task = None

        if self.socket_path.exists():
            self.socket_path.unlink()

        if self.lock_handle is not None:
            try:
                self.lock_handle.seek(0)
                self.lock_handle.truncate()
                fcntl.flock(self.lock_handle.fileno(), fcntl.LOCK_UN)
            except Exception:
                pass
            try:
                self.lock_handle.close()
            except Exception:
                pass
            self.lock_handle = None

    async def handle_client(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
    ) -> None:
        try:
            while True:
                line = await reader.readline()
                if not line:
                    break

                line = line.strip()
                if not line:
                    continue

                try:
                    event = json.loads(line)
                    if not isinstance(event, dict):
                        raise ValueError("event must be a JSON object")
                    self.apply_event(event)
                    await self.flush_state()
                    writer.write(b'{"ok":true}\n')
                    await writer.drain()
                except Exception as exc:  # noqa: BLE001
                    writer.write(
                        json.dumps({"ok": False, "error": str(exc)}).encode("utf-8") + b"\n"
                    )
                    await writer.drain()
        finally:
            writer.close()
            await writer.wait_closed()

    def apply_event(self, event: dict[str, Any]) -> None:
        session_id = event.get("session_id")
        if not session_id or not isinstance(session_id, str):
            raise ValueError("missing required string field: session_id")

        if event.get("remove") is True:
            self.event_sessions.pop(session_id, None)
            return

        tool = event.get("tool")
        status = event.get("status")
        if tool is None or status is None:
            raise ValueError("events must include tool and status unless remove=true")

        session = self.event_sessions.get(session_id)
        if session is None:
            session = SessionState(session_id=session_id)
            self.event_sessions[session_id] = session

        session.merge(event)

    async def flush_state(self) -> None:
        merged = self.build_merged_sessions()
        sessions = sorted(
            merged,
            key=self.sort_key,
        )

        payload = {
            "updated_at": now_iso(),
            "session_count": len(sessions),
            "sessions": sessions,
        }

        tmp_path = self.state_path.with_suffix(".tmp")
        tmp_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        tmp_path.replace(self.state_path)

    def build_merged_sessions(self) -> list[dict[str, Any]]:
        merged: dict[str, dict[str, Any]] = {
            session_id: dict(payload)
            for session_id, payload in self.discovered_sessions.items()
        }

        for session_id, session in self.event_sessions.items():
            existing = merged.get(session_id, {})
            existing.update(session.as_dict())
            merged[session_id] = existing

        return [self.normalize_session_payload(payload) for payload in merged.values()]

    def normalize_session_payload(self, session: dict[str, Any]) -> dict[str, Any]:
        payload = dict(session)
        payload["ui_state"] = self.ui_state_for_session(payload)
        payload["summary"] = self.summary_for_session(payload)
        payload["primary_action"] = self.primary_action_for_session(payload)
        payload["urgency_rank"] = self.urgency_rank_for_session(payload)
        payload["activity_timestamp"] = self.activity_timestamp_for_session(payload)
        return payload

    def ui_state_for_session(self, session: dict[str, Any]) -> str:
        status = str(session.get("status") or "idle")
        if status == "error":
            return "error"
        if session.get("pending_action") or session.get("requires_action") or status in {"approval_required", "question"}:
            return "needs_input"
        if status in {"working", "monitoring"}:
            return "working"
        if status == "done":
            return "done"
        return "idle"

    def summary_for_session(self, session: dict[str, Any]) -> str:
        pending_action = session.get("pending_action")
        if isinstance(pending_action, dict):
            detail = str(pending_action.get("detail") or "").strip()
            if detail:
                return compact_text(detail, 120)

        for key in ("detail", "preview"):
            value = str(session.get(key) or "").strip()
            if value and value not in {"No action needed right now.", "Codex session is live in the terminal."}:
                return compact_text(value, 120)

        recent = session.get("recent")
        if isinstance(recent, list):
            for entry in recent:
                if isinstance(entry, str) and entry.strip():
                    return compact_text(entry, 120)

        project = str(session.get("project") or session.get("cwd") or "").strip()
        tool = str(session.get("tool") or "agent").strip()
        ui_state = str(session.get("ui_state") or self.ui_state_for_session(session))
        if ui_state == "needs_input":
            return f"{tool.capitalize()} is waiting in the terminal."
        if ui_state == "working":
            return f"Working in {Path(project).name}." if project else f"{tool.capitalize()} is active."
        if ui_state == "done":
            return f"Finished in {Path(project).name}." if project else f"{tool.capitalize()} finished."
        if ui_state == "error":
            return f"{tool.capitalize()} hit an error."
        return f"Watching {Path(project).name}." if project else f"{tool.capitalize()} is idle."

    def primary_action_for_session(self, session: dict[str, Any]) -> dict[str, Any] | None:
        pending_action = session.get("pending_action")
        if isinstance(pending_action, dict):
            response_mode = str(pending_action.get("response_mode") or "")
            choices = pending_action.get("choices")
            if response_mode == "focus_terminal":
                return {
                    "id": "focus_terminal",
                    "label": "Open terminal",
                    "kind": "focus_terminal",
                    "emphasized": True,
                }
            if isinstance(choices, list):
                for choice in choices:
                    if isinstance(choice, dict):
                        primary_choice = dict(choice)
                        primary_choice.setdefault("kind", "choice")
                        primary_choice.setdefault("emphasized", True)
                        return primary_choice

        actions = session.get("actions")
        if isinstance(actions, list):
            for action in actions:
                if isinstance(action, dict):
                    return dict(action)

        return None

    def urgency_rank_for_session(self, session: dict[str, Any]) -> int:
        status = str(session.get("status") or "idle")
        ui_state = str(session.get("ui_state") or self.ui_state_for_session(session))

        if ui_state == "needs_input":
            if status == "approval_required":
                return 0
            if status == "question":
                return 1
            return 2
        if ui_state == "error":
            return 3
        if ui_state == "working":
            return 4
        if ui_state == "done":
            return 6
        return 7

    def activity_timestamp_for_session(self, session: dict[str, Any]) -> int:
        value = session.get("activity_timestamp")
        try:
            return int(value)
        except (TypeError, ValueError):
            pass

        updated_at = str(session.get("updated_at") or "")
        return self.iso_to_epoch(updated_at)

    def acquire_singleton_lock(self) -> None:
        self.lock_path.parent.mkdir(parents=True, exist_ok=True)
        handle = self.lock_path.open("a+", encoding="utf-8")

        for attempt in range(5):
            try:
                fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                handle.seek(0)
                handle.truncate()
                handle.write(f"{os.getpid()}\n")
                handle.flush()
                self.lock_handle = handle
                return
            except BlockingIOError:
                owner_pid = self.read_lock_owner_pid(handle)
                if owner_pid and owner_pid != os.getpid() and self.is_bridge_process(owner_pid):
                    try:
                        os.kill(owner_pid, signal.SIGTERM)
                    except OSError:
                        pass
                    time.sleep(0.25)
                    if attempt >= 2 and self.is_bridge_process(owner_pid):
                        try:
                            os.kill(owner_pid, signal.SIGKILL)
                        except OSError:
                            pass
                        time.sleep(0.1)
                    continue

                time.sleep(0.1)

        handle.close()
        raise RuntimeError("another Orbitbar bridge instance is already running")

    @staticmethod
    def read_lock_owner_pid(handle: Any) -> int | None:
        try:
            handle.seek(0)
            content = handle.read().strip()
        except Exception:
            return None

        try:
            return int(content)
        except (TypeError, ValueError):
            return None

    @staticmethod
    def is_bridge_process(pid: int) -> bool:
        try:
            cmdline = Path(f"/proc/{pid}/cmdline").read_text(encoding="utf-8").replace("\x00", " ")
        except Exception:
            return False
        return "orbitbar_bridge.py" in cmdline

    async def discovery_loop(self) -> None:
        while True:
            try:
                self.discovered_sessions = self.discover_sessions()
                await self.flush_state()
            except Exception:
                pass
            await asyncio.sleep(2.0)

    def discover_sessions(self) -> dict[str, dict[str, Any]]:
        proc = subprocess.run(
            ["ps", "-eo", "pid=,ppid=,tty=,comm=,args="],
            capture_output=True,
            text=True,
            check=True,
        )

        processes: dict[int, dict[str, Any]] = {}
        for raw_line in proc.stdout.splitlines():
            line = raw_line.strip()
            if not line:
                continue
            parts = line.split(None, 4)
            if len(parts) < 5:
                continue
            pid, ppid, tty, comm, args = parts
            try:
                processes[int(pid)] = {
                    "pid": int(pid),
                    "ppid": int(ppid),
                    "tty": tty,
                    "comm": comm,
                    "args": args,
                }
            except ValueError:
                continue

        hypr_clients: dict[int, dict[str, Any]] = {}
        try:
            clients_proc = subprocess.run(
                ["hyprctl", "clients", "-j"],
                capture_output=True,
                text=True,
                check=True,
            )
            for client in json.loads(clients_proc.stdout):
                pid = client.get("pid")
                if isinstance(pid, int):
                    hypr_clients[pid] = client
        except Exception:
            hypr_clients = {}

        tool_specs = [
            ("gemini", "gemini"),
            ("codex", "codex"),
            ("claude", "claude"),
            ("kimi", "kimi"),
        ]
        terminal_names = {"kitty", "ghostty", "wezterm", "alacritty", "foot", "konsole"}

        discovered: dict[str, dict[str, Any]] = {}
        matched_pids: list[tuple[str, int]] = []
        gemini_projects = self.load_gemini_projects()

        for process in processes.values():
            args = process["args"].lower()
            tool_name = None
            for slug, needle in tool_specs:
                if self.matches_tool_process(process, needle):
                    tool_name = slug
                    break
            if tool_name is None:
                continue
            if tool_name == "codex" and "app-server" in args:
                continue

            matched_pids.append((tool_name, process["pid"]))

        redundant: set[int] = set()
        for tool_name, pid in matched_pids:
            current = processes.get(pid)
            visited: set[int] = set()
            while current and current["pid"] not in visited:
                visited.add(current["pid"])
                parent = processes.get(current["ppid"])
                if parent is None:
                    break
                parent_args = parent["args"].lower()
                if tool_name in parent_args and "app-server" not in parent_args:
                    redundant.add(parent["pid"])
                current = parent

        live_sessions: list[dict[str, Any]] = []

        for tool_name, pid in matched_pids:
            if pid in redundant:
                continue
            process = processes[pid]

            terminal_pid = None
            current = process
            visited: set[int] = set()
            while current and current["pid"] not in visited:
                visited.add(current["pid"])
                if current["comm"] in terminal_names:
                    terminal_pid = current["pid"]
                    break
                current = processes.get(current["ppid"])

            if terminal_pid is None:
                continue

            client = hypr_clients.get(terminal_pid) if terminal_pid else None
            cwd = ""
            try:
                cwd = os.readlink(f"/proc/{process['pid']}/cwd")
            except OSError:
                cwd = ""

            project_name = Path(cwd).name if cwd else ""
            live_sessions.append({
                "tool_name": tool_name,
                "process": process,
                "client": client,
                "terminal_pid": terminal_pid,
                "cwd": cwd,
                "project_name": project_name,
            })

        live_sessions = self.deduplicate_live_sessions(live_sessions, processes)

        gemini_assignments = self.assign_gemini_sessions(
            [session for session in live_sessions if session["tool_name"] == "gemini"],
            gemini_projects,
        )
        codex_assignments = self.assign_codex_sessions(
            [session for session in live_sessions if session["tool_name"] == "codex"],
        )

        for live_session in live_sessions:
            tool_name = str(live_session["tool_name"])
            process = dict(live_session["process"])
            client = live_session["client"]
            terminal_pid = live_session["terminal_pid"]
            cwd = str(live_session["cwd"])
            project_name = str(live_session["project_name"])
            codex_thread_id = str(live_session.get("codex_thread_id") or "")
            workspace_name = str((client.get("workspace", {}) or {}).get("name") or "") if client else None
            title = project_name or (client.get("title", "") if client else "") or f"{tool_name} session"
            external_meta = self.build_tool_external_meta(
                tool_name=tool_name,
                process=process,
                cwd=cwd,
                project_name=project_name,
                title=title,
                gemini_assignments=gemini_assignments,
                codex_assignments=codex_assignments,
                codex_thread_id=codex_thread_id,
            )

            terminal_title = client.get("title", "") if client else ""
            detail = str(external_meta.get("detail") or "No action needed right now.")
            preview = external_meta.get("preview")
            command_candidate = self.extract_command_candidate(external_meta)
            sensitive_input_required = self.is_sensitive_command(command_candidate)
            actions: list[dict[str, Any]] = []
            pending_action: dict[str, Any] | None = None
            status = str(external_meta.get("status") or "monitoring")
            lower_terminal_title = terminal_title.lower()
            if any(token in lower_terminal_title for token in ("action required", "permission request", "approval required")):
                pending_action = self.build_pending_action(tool_name, external_meta, kind="approval_required")
                status = "approval_required"
            elif "ask" in lower_terminal_title:
                pending_action = self.build_pending_action(tool_name, external_meta, kind="question")
                status = "question"

            if pending_action:
                detail = str(pending_action.get("detail") or detail)
                preview = pending_action.get("preview") or preview
                sensitive_input_required = sensitive_input_required or (
                    str(pending_action.get("response_mode") or "") == "focus_terminal"
                )

            requires_action = bool(pending_action or external_meta.get("requires_action"))

            if client and client.get("address"):
                actions.append({
                    "id": "focus_terminal",
                    "label": "Enter password" if sensitive_input_required else "Jump to terminal",
                    "emphasized": bool(requires_action or sensitive_input_required),
                })

            meta_title = external_meta.get("title") or title
            provider_session_id = external_meta.get("provider_session_id")
            session_id = f"{tool_name}:{process['pid']}"

            discovered[session_id] = {
                "session_id": session_id,
                "tool": tool_name,
                "status": status,
                "title": meta_title,
                "detail": detail,
                "project": project_name or None,
                "cwd": cwd or None,
                "workspace": workspace_name,
                "terminal_app": client.get("class") if client else None,
                "terminal_title": client.get("title") if client else None,
                "window_address": client.get("address") if client else None,
                "terminal_pid": client.get("pid") if client else terminal_pid,
                "pid": process["pid"],
                "requires_action": requires_action,
                "sensitive_input_required": sensitive_input_required,
                "actions": actions,
                "options": (pending_action or {}).get("choices", []),
                "pending_action": pending_action,
                "recent": external_meta.get("recent", []),
                "preview": preview,
                "provider": external_meta.get("provider"),
                "provider_session_id": provider_session_id,
                "tokens_used": external_meta.get("tokens_used"),
                "token_usage_label": external_meta.get("token_usage_label"),
                "token_usage_detail": external_meta.get("token_usage_detail"),
                "model": external_meta.get("model"),
                "age": external_meta.get("age"),
                "activity_timestamp": external_meta.get("activity_timestamp"),
                "updated_at": now_iso(),
            }

        return discovered

    def build_tool_external_meta(
        self,
        tool_name: str,
        process: dict[str, Any],
        cwd: str,
        project_name: str,
        title: str,
        gemini_assignments: dict[int, dict[str, Any]],
        codex_assignments: dict[int, dict[str, Any]],
        codex_thread_id: str = "",
    ) -> dict[str, Any]:
        base_meta: dict[str, Any] = {
            "title": title,
            "detail": "No action needed right now.",
            "preview": None,
            "recent": [],
            "provider": None,
            "provider_session_id": None,
            "age": "",
            "status": "monitoring",
            "requires_action": False,
            "approval_mode": "",
            "last_tool_call": None,
            "change_summary": None,
            "activity_timestamp": 0,
        }

        if tool_name == "gemini":
            base_meta.update(gemini_assignments.get(process["pid"], {}))
        elif tool_name == "claude":
            base_meta.update(self.read_claude_project_session(cwd))
        elif tool_name == "kimi":
            base_meta["provider"] = "Kimi CLI"
        elif tool_name == "codex":
            base_meta.update(
                self.read_codex_project_session(
                    cwd,
                    thread_id_hint=codex_thread_id,
                    thread_hint=codex_assignments.get(process["pid"]),
                )
            )

        return base_meta

    def deduplicate_live_sessions(
        self,
        live_sessions: list[dict[str, Any]],
        processes: dict[int, dict[str, Any]],
    ) -> list[dict[str, Any]]:
        selected: dict[tuple[str, int | None, str], dict[str, Any]] = {}

        for live_session in live_sessions:
            tool_name = str(live_session.get("tool_name") or "")
            process = live_session.get("process")
            if not isinstance(process, dict):
                continue

            if tool_name == "codex":
                codex_cwd = self.extract_codex_command_cwd(process, processes)
                if codex_cwd:
                    live_session["cwd"] = codex_cwd
                    live_session["project_name"] = Path(codex_cwd).name
                live_session["codex_thread_id"] = self.extract_codex_thread_id(process, processes)

            tty = str(process.get("tty") or "")
            terminal_pid = live_session.get("terminal_pid")
            codex_thread_id = str(live_session.get("codex_thread_id") or "")
            if tool_name == "codex" and codex_thread_id:
                key = (tool_name, int(process.get("pid") or 0), codex_thread_id)
            else:
                key = (tool_name, terminal_pid if isinstance(terminal_pid, int) else None, tty)
            existing = selected.get(key)
            if existing is None or self.live_session_priority(live_session) > self.live_session_priority(existing):
                selected[key] = live_session

        return list(selected.values())

    def live_session_priority(self, live_session: dict[str, Any]) -> tuple[int, int, int, int]:
        tool_name = str(live_session.get("tool_name") or "")
        process = live_session.get("process")
        if not isinstance(process, dict):
            return (0, 0, 0, 0)

        has_explicit_thread = 1 if tool_name == "codex" and live_session.get("codex_thread_id") else 0
        is_primary_comm = 1 if str(process.get("comm") or "").lower() == tool_name else 0
        start_ticks = self.get_process_start_ticks(int(process.get("pid") or 0))
        pid = int(process.get("pid") or 0)
        return (has_explicit_thread, is_primary_comm, start_ticks, pid)

    def walk_process_lineage(
        self,
        process: dict[str, Any],
        processes: dict[int, dict[str, Any]],
    ) -> list[dict[str, Any]]:
        lineage: list[dict[str, Any]] = []
        current = process
        visited: set[int] = set()

        while current and int(current.get("pid") or 0) not in visited:
            pid = int(current.get("pid") or 0)
            visited.add(pid)
            lineage.append(current)
            parent = processes.get(int(current.get("ppid") or 0))
            if parent is None:
                break
            current = parent

        return lineage

    def extract_codex_thread_id(
        self,
        process: dict[str, Any],
        processes: dict[int, dict[str, Any]],
    ) -> str:
        patterns = (
            r"shell_snapshots/([0-9a-f-]{36})\.[^/\s]+\.sh",
            r"thread[_-]?id[= ]([0-9a-f-]{36})",
        )

        for entry in self.walk_process_lineage(process, processes):
            args = str(entry.get("args") or "")
            for pattern in patterns:
                match = re.search(pattern, args)
                if match:
                    return match.group(1)

        return ""

    def extract_codex_command_cwd(
        self,
        process: dict[str, Any],
        processes: dict[int, dict[str, Any]],
    ) -> str:
        patterns = (r"--command-cwd\s+(\S+)", r"--sandbox-policy-cwd\s+(\S+)")

        for entry in self.walk_process_lineage(process, processes):
            args = str(entry.get("args") or "")
            for pattern in patterns:
                match = re.search(pattern, args)
                if match:
                    try:
                        return str(Path(match.group(1)).resolve())
                    except Exception:
                        return match.group(1)

        return ""

    @staticmethod
    def matches_tool_process(process: dict[str, Any], needle: str) -> bool:
        args = str(process.get("args", "")).lower()
        comm = str(process.get("comm", "")).lower()
        if needle not in args:
            return False

        if needle == "codex" and comm != "codex":
            return False

        if comm in {"rg", "grep", "sed", "cat", "ps"}:
            return False

        if comm in {"bash", "sh", "zsh", "fish"}:
            inspection_tokens = (
                " rg ",
                " grep ",
                " sed ",
                " cat ",
                " ps -",
                "pgrep ",
                "orbitbar_bridge.py",
                "quickshell list",
                "quickshell log",
            )
            if any(token in args for token in inspection_tokens):
                return False

        return True

    def load_gemini_projects(self) -> dict[str, str]:
        path = Path.home() / ".gemini" / "projects.json"
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
            projects = payload.get("projects", {})
            if isinstance(projects, dict):
                return {str(key): str(value) for key, value in projects.items()}
        except Exception:
            pass
        return {}

    def resolve_gemini_project_alias(self, cwd: str, gemini_projects: dict[str, str]) -> str:
        if not cwd:
            return Path.home().name

        resolved_cwd = str(Path(cwd).resolve())
        best_alias = ""
        best_length = -1
        for project_path, alias in gemini_projects.items():
            try:
                resolved_project = str(Path(project_path).resolve())
            except Exception:
                continue

            if resolved_cwd == resolved_project or resolved_cwd.startswith(resolved_project + os.sep):
                if len(resolved_project) > best_length:
                    best_alias = alias
                    best_length = len(resolved_project)

        if best_alias:
            return best_alias
        return Path(cwd).name or Path.home().name

    def assign_gemini_sessions(
        self,
        live_sessions: list[dict[str, Any]],
        gemini_projects: dict[str, str],
    ) -> dict[int, dict[str, Any]]:
        assignments: dict[int, dict[str, Any]] = {}
        grouped: dict[str, list[dict[str, Any]]] = {}

        for live_session in live_sessions:
            alias = self.resolve_gemini_project_alias(str(live_session["cwd"]), gemini_projects)
            grouped.setdefault(alias, []).append(live_session)

        for alias, project_sessions in grouped.items():
            parsed_sessions = self.read_gemini_project_sessions(alias)
            project_sessions.sort(key=lambda item: self.get_process_start_ticks(int(item["process"]["pid"])))
            selected_sessions = parsed_sessions[-len(project_sessions):]
            for live_session, parsed_session in zip(project_sessions, selected_sessions):
                assignments[int(live_session["process"]["pid"])] = parsed_session

        return assignments

    def assign_codex_sessions(self, live_sessions: list[dict[str, Any]]) -> dict[int, dict[str, Any]]:
        assignments: dict[int, dict[str, Any]] = {}
        grouped: dict[str, list[dict[str, Any]]] = {}

        for live_session in live_sessions:
            process = live_session.get("process")
            if not isinstance(process, dict):
                continue

            explicit_thread_id = str(live_session.get("codex_thread_id") or "")
            if explicit_thread_id:
                thread = self.find_codex_thread(str(live_session.get("cwd") or ""), thread_id_hint=explicit_thread_id)
                if thread is not None:
                    assignments[int(process["pid"])] = thread
                    continue

            cwd = str(live_session.get("cwd") or "")
            if cwd:
                grouped.setdefault(cwd, []).append(live_session)

        for cwd, project_sessions in grouped.items():
            recent_threads = self.read_codex_threads_for_cwd(cwd, limit=max(len(project_sessions) + 4, 8))
            if not recent_threads:
                continue

            project_sessions.sort(key=lambda item: self.get_process_start_ticks(int(item["process"]["pid"])))
            selected_threads = recent_threads[-len(project_sessions):]
            for live_session, thread in zip(project_sessions, selected_threads):
                assignments[int(live_session["process"]["pid"])] = thread

        return assignments

    def build_pending_action(
        self,
        tool_name: str,
        session_meta: dict[str, Any],
        *,
        kind: str,
    ) -> dict[str, Any] | None:
        if tool_name == "gemini":
            return self.build_gemini_pending_action(session_meta)
        if tool_name == "codex":
            return self.build_codex_pending_action(session_meta, kind=kind)
        return self.build_generic_pending_action(tool_name, session_meta, kind=kind)

    def build_gemini_pending_action(self, session_meta: dict[str, Any]) -> dict[str, Any]:
        command = self.extract_command_candidate(session_meta)
        if command:
            executable = command.split()[0]
            detail = f"Allow execution of: '{executable}'?"
            preview = command
        else:
            detail = "Gemini is waiting for your approval."
            preview = session_meta.get("preview")

        return {
            "kind": "command_approval",
            "response_mode": "focus_terminal" if self.is_sensitive_command(command) else "direct_tty",
            "detail": detail,
            "preview": preview,
            "choices": [
                {
                    "id": "allow_once",
                    "label": "Allow once",
                    "description": "Run this command a single time.",
                    "response": "1\n",
                },
                {
                    "id": "allow_session",
                    "label": "Allow session",
                    "description": "Keep allowing similar commands in this Gemini session.",
                    "response": "2\n",
                },
                {
                    "id": "deny_suggest_changes",
                    "label": "Suggest changes",
                    "description": "Deny execution and ask Gemini to revise the plan.",
                    "response": "3\n",
                },
            ],
        }

    def build_codex_pending_action(self, session_meta: dict[str, Any], *, kind: str) -> dict[str, Any]:
        last_tool_call = session_meta.get("last_tool_call")
        if not isinstance(last_tool_call, dict):
            last_tool_call = {}

        tool_kind = str(last_tool_call.get("kind") or "")
        preview = (
            str(last_tool_call.get("patch_preview") or "")
            or str(last_tool_call.get("command") or "")
            or str(session_meta.get("preview") or "")
        )
        command = str(last_tool_call.get("command") or "")
        change_summary = session_meta.get("change_summary")
        response_mode = "focus_terminal" if self.is_sensitive_command(command) else "direct_tty"

        if kind == "question":
            questions = last_tool_call.get("questions")
            detail = "Codex is asking for input."
            if isinstance(questions, list) and questions:
                first_question = questions[0]
                if isinstance(first_question, dict):
                    detail = str(first_question.get("question") or detail)
            return {
                "kind": "question",
                "response_mode": "focus_terminal",
                "detail": detail,
                "preview": preview or None,
                "choices": [],
                "change_summary": None,
            }

        if tool_kind == "apply_patch":
            file_count = 0
            if isinstance(change_summary, dict):
                file_count = int(change_summary.get("file_count") or 0)
            detail = "Review and approve Codex changes?"
            if file_count > 0:
                detail = f"Review and approve Codex changes to {file_count} file{'s' if file_count != 1 else ''}?"
            return {
                "kind": "change_review",
                "response_mode": response_mode,
                "detail": detail,
                "preview": preview or None,
                "choices": self.build_binary_choices(),
                "change_summary": change_summary,
            }

        if command:
            executable = command.split()[0]
            detail = f"Allow Codex to run '{executable}'?"
        else:
            detail = "Codex is waiting for approval."

        return {
            "kind": "command_approval",
            "response_mode": response_mode,
            "detail": detail,
            "preview": preview or None,
            "choices": self.build_binary_choices(),
            "change_summary": None,
        }

    def build_generic_pending_action(
        self,
        tool_name: str,
        session_meta: dict[str, Any],
        *,
        kind: str,
    ) -> dict[str, Any]:
        preview = self.extract_command_candidate(session_meta) or session_meta.get("preview")
        return {
            "kind": "question" if kind == "question" else "command_approval",
            "response_mode": "focus_terminal",
            "detail": f"{tool_name.capitalize()} needs your input in the terminal.",
            "preview": preview or None,
            "choices": [],
            "change_summary": None,
        }

    @staticmethod
    def build_binary_choices() -> list[dict[str, Any]]:
        return [
            {
                "id": "approve",
                "label": "Approve",
                "description": "Send approval back to the live Codex session.",
                "response": "1\n",
            },
            {
                "id": "decline",
                "label": "Decline",
                "description": "Reject the pending Codex action.",
                "response": "2\n",
            },
        ]

    @staticmethod
    def is_sensitive_command(command: str) -> bool:
        stripped = command.strip().lower()
        if not stripped:
            return False
        return stripped.startswith(("sudo ", "doas ", "passwd", "su ", "pkexec "))

    def extract_command_candidate(self, session_meta: dict[str, Any]) -> str:
        candidates: list[str] = []
        preview = session_meta.get("preview")
        if isinstance(preview, str) and preview.strip():
            candidates.append(preview)

        recent = session_meta.get("recent")
        if isinstance(recent, list):
            for entry in recent:
                if isinstance(entry, str) and entry.strip():
                    candidates.append(entry)

        for candidate in candidates:
            backtick_match = re.search(r"`([^`]+)`", candidate)
            if backtick_match:
                return compact_text(backtick_match.group(1), 240)

            stripped = candidate.strip()
            if stripped.startswith(("sudo ", "pacman ", "paru ", "yay ", "npm ", "pnpm ", "bun ", "python ", "bash ", "sh ")):
                return compact_text(stripped, 240)

        return ""

    def read_gemini_project_sessions(self, project_alias: str) -> list[dict[str, Any]]:
        home = Path.home()
        gemini_root = home / ".gemini"
        chat_dir = gemini_root / "tmp" / project_alias / "chats"
        if not chat_dir.exists():
            return []

        session_files = sorted(chat_dir.glob("session-*.json"), key=lambda path: path.stat().st_mtime, reverse=True)
        if not session_files:
            return []

        parsed_sessions: list[dict[str, Any]] = []
        for path in session_files:
            try:
                payload = json.loads(path.read_text(encoding="utf-8"))
            except Exception:
                continue
            messages = payload.get("messages", [])
            if not isinstance(messages, list) or not messages:
                continue

            first_user = next((message for message in messages if message.get("type") == "user"), None)
            last_message = messages[-1]
            title = project_alias
            if first_user:
                title = compact_text(self.extract_gemini_message_text(first_user), 34) or title

            detail = "No action needed right now."
            status = "monitoring"
            activity_timestamp = 0
            if isinstance(last_message, dict):
                last_type = last_message.get("type")
                if last_type == "user":
                    detail = "Gemini is responding in the terminal."
                    status = "working"
                elif last_type == "info":
                    info_text = compact_text(self.extract_gemini_message_text(last_message), 120)
                    if info_text:
                        detail = info_text

            recent = []
            for message in messages[-3:]:
                label = message.get("type", "message")
                text = compact_text(self.extract_gemini_message_text(message), 90)
                if text:
                    recent.append(f"{label}: {text}")

            preview = None
            if isinstance(last_message, dict):
                preview = compact_text(self.extract_gemini_message_text(last_message), 240)

            age = ""
            sort_timestamp = payload.get("lastUpdated") or payload.get("startTime") or ""
            if isinstance(sort_timestamp, str):
                try:
                    dt = datetime.fromisoformat(sort_timestamp.replace("Z", "+00:00"))
                    activity_timestamp = int(dt.timestamp())
                    delta = datetime.now(UTC) - dt.astimezone(UTC)
                    minutes = int(delta.total_seconds() // 60)
                    if minutes < 60:
                        age = f"{max(1, minutes)}m"
                    else:
                        age = f"{max(1, minutes // 60)}h"
                except Exception:
                    age = ""

            parsed_sessions.append({
                "title": title,
                "detail": detail,
                "preview": preview,
                "recent": recent,
                "provider": "Gemini CLI",
                "provider_session_id": payload.get("sessionId"),
                "age": age,
                "requires_action": False,
                "status": status,
                "activity_timestamp": activity_timestamp,
                "_sort_timestamp": str(sort_timestamp),
            })

        parsed_sessions.sort(key=lambda item: str(item.get("_sort_timestamp", "")))
        for session in parsed_sessions:
            session.pop("_sort_timestamp", None)
        return parsed_sessions

    def read_claude_project_session(self, cwd: str) -> dict[str, Any]:
        if not cwd:
            return {}

        project_slug = self.claude_project_slug(cwd)
        index_path = Path.home() / ".claude" / "projects" / project_slug / "sessions-index.json"
        if not index_path.exists():
            return {}

        try:
            payload = json.loads(index_path.read_text(encoding="utf-8"))
        except Exception:
            return {}

        entries = payload.get("entries", [])
        if not isinstance(entries, list) or not entries:
            return {}

        latest = max(entries, key=lambda item: int(item.get("fileMtime", 0)))
        title = compact_text(str(latest.get("firstPrompt") or Path(cwd).name or "Claude session"), 34)
        detail = compact_text(str(latest.get("summary") or "No action needed right now."), 120)
        recent = self.read_claude_recent_messages(Path(str(latest.get("fullPath", ""))))
        preview = recent[-1] if recent else None
        return {
            "title": title,
            "detail": detail,
            "preview": preview,
            "recent": recent,
            "provider": "Claude Code",
            "provider_session_id": latest.get("sessionId"),
            "age": self.relative_age_from_iso(str(latest.get("modified", ""))),
            "requires_action": False,
            "status": "monitoring",
            "activity_timestamp": self.iso_to_epoch(str(latest.get("modified", ""))),
        }

    def read_codex_project_session(
        self,
        cwd: str,
        *,
        thread_id_hint: str = "",
        thread_hint: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        thread = thread_hint if isinstance(thread_hint, dict) else self.find_codex_thread(cwd, thread_id_hint=thread_id_hint)
        if thread is None:
            return self.read_codex_session_index_fallback(cwd)

        thread_id = str(thread.get("id") or "")
        activity = self.read_codex_thread_activity(thread_id)
        return {
            "title": compact_text(str(thread.get("title") or Path(cwd).name or "Codex session"), 34),
            "detail": str(activity.get("detail") or "Codex session is live in the terminal."),
            "preview": activity.get("preview"),
            "recent": activity.get("recent", []),
            "provider": "Codex CLI",
            "provider_session_id": thread_id or None,
            "age": self.relative_age_from_epoch(thread.get("updated_at")),
            "requires_action": False,
            "status": "monitoring",
            "approval_mode": str(thread.get("approval_mode") or ""),
            "last_tool_call": activity.get("last_tool_call"),
            "change_summary": activity.get("change_summary"),
            "activity_timestamp": int(activity.get("activity_timestamp") or thread.get("updated_at") or 0),
            "tokens_used": int(thread.get("tokens_used") or 0),
            "token_usage_label": format_token_count(thread.get("tokens_used")),
            "token_usage_detail": f"{int(thread.get('tokens_used') or 0):,} tokens used" if int(thread.get("tokens_used") or 0) > 0 else "",
            "model": str(thread.get("model") or ""),
        }

    def find_codex_thread(self, cwd: str, *, thread_id_hint: str = "") -> dict[str, Any] | None:
        if not self.codex_state_db_path.exists():
            return None

        if thread_id_hint:
            exact_rows = self.query_sqlite(
                self.codex_state_db_path,
                """
                    select id, title, cwd, approval_mode, updated_at
                    , tokens_used, model
                    from threads
                    where id = ?
                    limit 1
                """,
                (thread_id_hint,),
            )
            if exact_rows:
                return exact_rows[0]

        if not cwd:
            return None

        resolved_cwd = str(Path(cwd).resolve())
        query = """
            select id, title, cwd, approval_mode, updated_at
            , tokens_used, model
            from threads
            where cwd = ?
            order by updated_at desc
            limit 1
        """
        rows = self.query_sqlite(self.codex_state_db_path, query, (resolved_cwd,))
        if rows:
            return rows[0]

        fallback_query = """
            select id, title, cwd, approval_mode, updated_at
            , tokens_used, model
            from threads
            order by updated_at desc
            limit 8
        """
        for row in self.query_sqlite(self.codex_state_db_path, fallback_query):
            row_cwd = str(row.get("cwd") or "")
            if not row_cwd:
                continue
            try:
                resolved_row_cwd = str(Path(row_cwd).resolve())
            except Exception:
                continue
            if resolved_row_cwd == resolved_cwd:
                return row
        return None

    def read_codex_threads_for_cwd(self, cwd: str, limit: int = 8) -> list[dict[str, Any]]:
        if not cwd or not self.codex_state_db_path.exists():
            return []

        resolved_cwd = str(Path(cwd).resolve())
        rows = self.query_sqlite(
            self.codex_state_db_path,
            """
                select id, title, cwd, approval_mode, updated_at
                , tokens_used, model
                from threads
                where cwd = ?
                order by updated_at asc
                limit ?
            """,
            (resolved_cwd, int(max(1, limit))),
        )
        if rows:
            return rows

        fallback_rows: list[dict[str, Any]] = []
        for row in self.query_sqlite(
            self.codex_state_db_path,
            """
                select id, title, cwd, approval_mode, updated_at
                , tokens_used, model
                from threads
                order by updated_at desc
                limit 24
            """,
        ):
            row_cwd = str(row.get("cwd") or "")
            if not row_cwd:
                continue
            try:
                resolved_row_cwd = str(Path(row_cwd).resolve())
            except Exception:
                continue
            if resolved_row_cwd == resolved_cwd:
                fallback_rows.append(row)

        fallback_rows.reverse()
        return fallback_rows[-limit:]

    def read_codex_session_index_fallback(self, cwd: str) -> dict[str, Any]:
        if not self.codex_session_index_path.exists():
            return {}

        latest: dict[str, Any] | None = None
        try:
            for raw_line in self.codex_session_index_path.read_text(encoding="utf-8").splitlines():
                if not raw_line.strip():
                    continue
                entry = json.loads(raw_line)
                if isinstance(entry, dict):
                    latest = entry
        except Exception:
            return {}

        if latest is None:
            return {}

        return {
            "title": compact_text(str(latest.get("thread_name") or Path(cwd).name or "Codex session"), 34),
            "detail": "Codex session is live in the terminal.",
            "preview": None,
            "recent": [],
            "provider": "Codex CLI",
            "provider_session_id": latest.get("id"),
            "age": self.relative_age_from_iso(str(latest.get("updated_at") or "")),
            "requires_action": False,
            "status": "monitoring",
            "approval_mode": "",
            "last_tool_call": None,
            "change_summary": None,
            "activity_timestamp": self.iso_to_epoch(str(latest.get("updated_at") or "")),
            "tokens_used": 0,
            "token_usage_label": "",
            "token_usage_detail": "",
            "model": "",
        }

    def read_codex_thread_activity(self, thread_id: str) -> dict[str, Any]:
        if not thread_id or not self.codex_log_db_path.exists():
            return {}

        query = """
            select ts, feedback_log_body
            from logs
            where thread_id = ?
              and feedback_log_body is not null
            order by id desc
            limit 60
        """
        rows = self.query_sqlite(self.codex_log_db_path, query, (thread_id,))
        tool_calls: list[dict[str, Any]] = []
        for row in rows:
            body = row.get("feedback_log_body")
            if not isinstance(body, str):
                continue
            parsed = self.parse_codex_tool_call_log(body)
            if parsed is not None:
                parsed["ts"] = int(row.get("ts") or 0)
                tool_calls.append(parsed)

        recent = [str(entry.get("summary")) for entry in tool_calls[:3] if entry.get("summary")]
        latest = tool_calls[0] if tool_calls else None
        preview = latest.get("preview") if latest else None
        detail = "Codex session is live in the terminal."
        change_summary = latest.get("change_summary") if latest else None
        if latest:
            if latest.get("kind") == "apply_patch":
                file_count = int((change_summary or {}).get("file_count") or 0)
                detail = (
                    f"Last Codex change touched {file_count} file{'s' if file_count != 1 else ''}."
                    if file_count > 0 else
                    "Codex recently proposed a patch."
                )
            elif latest.get("kind") == "exec_command":
                command = str(latest.get("command") or "")
                if command:
                    detail = f"Last Codex command: {compact_text(command, 96)}"
            elif latest.get("kind") == "request_user_input":
                detail = "Codex recently asked for user input."

        return {
            "detail": detail,
            "preview": preview,
            "recent": recent,
            "last_tool_call": latest,
            "change_summary": change_summary,
            "activity_timestamp": int((latest or {}).get("ts") or 0),
        }

    def parse_codex_tool_call_log(self, body: str) -> dict[str, Any] | None:
        marker = "ToolCall: "
        if marker not in body:
            return None

        payload = body.split(marker, 1)[1]
        if payload.startswith("exec_command "):
            raw_args = payload[len("exec_command "):]
            call_data = self.parse_trailing_json_object(raw_args)
            if not isinstance(call_data, dict):
                return None
            command = str(call_data.get("cmd") or "")
            return {
                "kind": "exec_command",
                "command": command,
                "preview": compact_text(command, 240),
                "summary": f"exec: {compact_text(command, 90)}" if command else "exec command",
            }

        if payload.startswith("request_user_input "):
            raw_args = payload[len("request_user_input "):]
            call_data = self.parse_trailing_json_object(raw_args)
            questions = call_data.get("questions") if isinstance(call_data, dict) else None
            first_question = ""
            if isinstance(questions, list) and questions and isinstance(questions[0], dict):
                first_question = str(questions[0].get("question") or "")
            return {
                "kind": "request_user_input",
                "questions": questions if isinstance(questions, list) else [],
                "preview": compact_text(first_question, 240) if first_question else None,
                "summary": f"question: {compact_text(first_question, 90)}" if first_question else "question",
            }

        if payload.startswith("apply_patch "):
            patch_text = payload[len("apply_patch "):]
            change_summary = self.summarize_patch(patch_text)
            files = change_summary.get("files", [])
            if files:
                file_preview = ", ".join(str(name) for name in files[:4])
                if len(files) > 4:
                    file_preview += ", …"
            else:
                file_preview = "patch"
            return {
                "kind": "apply_patch",
                "patch_preview": self.preview_patch(patch_text),
                "preview": self.preview_patch(patch_text),
                "change_summary": change_summary,
                "summary": f"patch: {file_preview}",
            }

        return None

    @staticmethod
    def parse_trailing_json_object(raw_value: str) -> dict[str, Any] | None:
        candidate = raw_value.strip()
        if " thread_id=" in candidate:
            candidate = candidate.split(" thread_id=", 1)[0].rstrip()
        try:
            parsed = json.loads(candidate)
        except Exception:
            return None
        return parsed if isinstance(parsed, dict) else None

    def summarize_patch(self, patch_text: str) -> dict[str, Any]:
        files = re.findall(r"^\*\*\* (?:Update|Add|Delete) File: (.+)$", patch_text, re.MULTILINE)
        return {
            "file_count": len(files),
            "files": files[:12],
        }

    def preview_patch(self, patch_text: str, line_limit: int = 18) -> str:
        lines = patch_text.splitlines()
        preview_lines = lines[:line_limit]
        preview = "\n".join(preview_lines).strip()
        if len(lines) > line_limit:
            preview += "\n..."
        if len(preview) > 1200:
            preview = preview[:1199].rstrip() + "…"
        return preview

    def query_sqlite(
        self,
        db_path: Path,
        query: str,
        params: tuple[Any, ...] = (),
    ) -> list[dict[str, Any]]:
        if not db_path.exists():
            return []
        try:
            connection = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
            connection.row_factory = sqlite3.Row
            try:
                rows = connection.execute(query, params).fetchall()
            finally:
                connection.close()
        except sqlite3.Error:
            return []
        return [dict(row) for row in rows]

    @staticmethod
    def claude_project_slug(cwd: str) -> str:
        return "-" + str(Path(cwd).resolve()).strip("/").replace("/", "-")

    def read_claude_recent_messages(self, session_path: Path) -> list[str]:
        if not session_path.exists():
            return []

        recent: list[str] = []
        try:
            lines = session_path.read_text(encoding="utf-8").splitlines()
        except Exception:
            return []

        for raw_line in lines[-5:]:
            try:
                entry = json.loads(raw_line)
            except Exception:
                continue

            entry_type = str(entry.get("type", "message"))
            message = entry.get("message", {})
            if isinstance(message, dict):
                content = message.get("content")
                text = self.extract_claude_content_text(content)
            else:
                text = ""
            text = compact_text(text, 90)
            if text:
                recent.append(f"{entry_type}: {text}")

        return recent[-3:]

    @staticmethod
    def extract_claude_content_text(content: Any) -> str:
        if isinstance(content, str):
            return content
        if isinstance(content, list):
            parts: list[str] = []
            for item in content:
                if isinstance(item, dict):
                    if isinstance(item.get("text"), str):
                        parts.append(item["text"])
                    elif isinstance(item.get("thinking"), str):
                        parts.append(item["thinking"])
            return "\n".join(parts)
        return ""

    def relative_age_from_iso(self, value: str) -> str:
        if not value:
            return ""
        try:
            dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
            delta = datetime.now(UTC) - dt.astimezone(UTC)
            minutes = int(delta.total_seconds() // 60)
            if minutes < 60:
                return f"{max(1, minutes)}m"
            return f"{max(1, minutes // 60)}h"
        except Exception:
            return ""

    def relative_age_from_epoch(self, value: Any) -> str:
        try:
            timestamp = int(value)
        except (TypeError, ValueError):
            return ""
        delta = int(datetime.now(UTC).timestamp()) - timestamp
        minutes = max(1, delta // 60)
        if minutes < 60:
            return f"{minutes}m"
        return f"{max(1, minutes // 60)}h"

    def iso_to_epoch(self, value: str) -> int:
        if not value:
            return 0
        try:
            return int(datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp())
        except Exception:
            return 0

    def ensure_terminal_in_special(self, client: dict[str, Any] | None) -> str | None:
        # Routing removed — window placement is now the user's responsibility via keybinds.
        if not client:
            return None
        workspace = client.get("workspace", {}) or {}
        return str(workspace.get("name") or "") or None

    def restore_orphaned_terminals(
        self,
        active_terminal_addresses: set[str],
        hypr_clients: dict[int, dict[str, Any]],
    ) -> None:
        # Routing removed — no-op.
        self.managed_terminal_workspaces.clear()

    @staticmethod
    def get_process_start_ticks(pid: int) -> int:
        try:
            with open(f"/proc/{pid}/stat", encoding="utf-8") as handle:
                stat = handle.read().split()
            return int(stat[21])
        except Exception:
            return pid

    @staticmethod
    def extract_gemini_message_text(message: dict[str, Any]) -> str:
        content = message.get("content")
        if isinstance(content, str):
            return content
        if isinstance(content, list):
            parts: list[str] = []
            for item in content:
                if isinstance(item, dict) and isinstance(item.get("text"), str):
                    parts.append(item["text"])
            return "\n".join(parts)
        return ""

    @staticmethod
    def sort_key(session: dict[str, Any]) -> tuple[int, int, str]:
        urgency_rank = int(session.get("urgency_rank", 99) or 99)
        activity_timestamp = int(session.get("activity_timestamp", 0) or 0)
        return (urgency_rank, -activity_timestamp, str(session.get("session_id", "")))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Orbitbar local bridge daemon")
    parser.add_argument("--socket-path", required=True)
    parser.add_argument("--state-path", required=True)
    return parser.parse_args()


async def main() -> None:
    args = parse_args()
    bridge = OrbitbarBridge(
        socket_path=Path(args.socket_path),
        state_path=Path(args.state_path),
    )

    stop_event = asyncio.Event()

    def request_stop() -> None:
        stop_event.set()

    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, request_stop)

    await bridge.start()

    try:
        await stop_event.wait()
    finally:
        await bridge.stop()


if __name__ == "__main__":
    asyncio.run(main())
