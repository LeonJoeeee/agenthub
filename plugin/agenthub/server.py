"""AgentHub plugin HTTP/WS server.

Endpoints (all require ``Authorization: Bearer <token>`` except /health):
  GET  /health                              — liveness, public
  GET  /v1/sessions                         — list recent sessions
  GET  /v1/sessions/{id}                    — session metadata
  GET  /v1/sessions/{id}/messages           — full message history
  POST /v1/chat                             — send a message; body {session_id?, content}
  GET  /v1/capabilities                     — agent metadata (model, skills sample)

Backed by:
  - state.db (SQLite, read-only) for sessions/messages
  - subprocess `hermes -z --resume <id>` for sending messages (zero-config path)
"""

from __future__ import annotations

import asyncio
import hmac
import json
import logging
import os
import sqlite3
import subprocess
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

from aiohttp import web

logger = logging.getLogger(__name__)

# How many sessions to return by default.
DEFAULT_SESSION_LIMIT = 50
# Max messages per fetch.
MAX_MESSAGES = 2000
# Max body size for POST /v1/chat.
MAX_CHAT_BODY = 64 * 1024
# Timeout for synchronous hermes -z spawn.
HERMES_TIMEOUT_SECS = 180


# ---------------------------------------------------------------------------
# State.db helpers (read-only)
# ---------------------------------------------------------------------------


def _db_path() -> Path:
    from hermes_constants import get_hermes_home
    return Path(get_hermes_home()) / "state.db"


def _open_db() -> sqlite3.Connection:
    """Open a fresh read-only connection per request to dodge thread issues."""
    uri = f"file:{_db_path()}?mode=ro"
    conn = sqlite3.connect(uri, uri=True, timeout=2.0)
    conn.row_factory = sqlite3.Row
    return conn


def list_sessions(limit: int = DEFAULT_SESSION_LIMIT, offset: int = 0) -> List[Dict[str, Any]]:
    sql = (
        "SELECT id, source, model, system_prompt, started_at, ended_at, "
        "       message_count, tool_call_count, title, "
        "       input_tokens, output_tokens, estimated_cost_usd "
        "FROM sessions ORDER BY started_at DESC LIMIT ? OFFSET ?"
    )
    with _open_db() as conn:
        rows = conn.execute(sql, (limit, offset)).fetchall()
    out: List[Dict[str, Any]] = []
    for r in rows:
        out.append({
            "id": r["id"],
            "source": r["source"],
            "model": r["model"],
            "title": r["title"],
            "started_at": r["started_at"],
            "ended_at": r["ended_at"],
            "message_count": r["message_count"] or 0,
            "tool_call_count": r["tool_call_count"] or 0,
            "input_tokens": r["input_tokens"] or 0,
            "output_tokens": r["output_tokens"] or 0,
            "cost_usd": r["estimated_cost_usd"],
        })
    return out


def get_session(session_id: str) -> Optional[Dict[str, Any]]:
    with _open_db() as conn:
        r = conn.execute(
            "SELECT id, source, model, system_prompt, started_at, ended_at, "
            "       message_count, tool_call_count, title "
            "FROM sessions WHERE id = ?",
            (session_id,),
        ).fetchone()
    if not r:
        return None
    return {
        "id": r["id"],
        "source": r["source"],
        "model": r["model"],
        "system_prompt": r["system_prompt"],
        "title": r["title"],
        "started_at": r["started_at"],
        "ended_at": r["ended_at"],
        "message_count": r["message_count"] or 0,
        "tool_call_count": r["tool_call_count"] or 0,
    }


def get_messages(session_id: str, limit: int = MAX_MESSAGES) -> List[Dict[str, Any]]:
    sql = (
        "SELECT id, role, content, tool_call_id, tool_calls, tool_name, "
        "       timestamp, finish_reason "
        "FROM messages WHERE session_id = ? "
        "ORDER BY timestamp ASC, id ASC LIMIT ?"
    )
    with _open_db() as conn:
        rows = conn.execute(sql, (session_id, limit)).fetchall()
    out: List[Dict[str, Any]] = []
    for r in rows:
        out.append({
            "id": r["id"],
            "role": r["role"],
            "content": r["content"],
            "tool_call_id": r["tool_call_id"],
            "tool_calls": _maybe_json(r["tool_calls"]),
            "tool_name": r["tool_name"],
            "timestamp": r["timestamp"],
            "finish_reason": r["finish_reason"],
        })
    return out


def _maybe_json(s: Optional[str]) -> Any:
    if not s:
        return None
    try:
        return json.loads(s)
    except Exception:
        return s


# ---------------------------------------------------------------------------
# Send message via subprocess `hermes -z --resume`
# ---------------------------------------------------------------------------


async def send_message(content: str, session_id: Optional[str] = None) -> Dict[str, Any]:
    """Spawn `hermes -z` to deliver one user message; return the assistant reply.

    For MVP this is the simplest possible path:
      - works with any Hermes install (no api_server config needed)
      - process boot adds ~1-2s latency per message; acceptable for v0.4
    Later we can switch to api_server delegation for in-process speed.
    """
    hermes_bin = os.environ.get("HERMES_BIN") or "hermes"
    argv: List[str] = [hermes_bin, "-z", content, "--ignore-rules"]
    if session_id:
        argv.extend(["--resume", session_id, "--pass-session-id"])

    started = time.time()
    try:
        proc = await asyncio.create_subprocess_exec(
            *argv,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        try:
            stdout_b, stderr_b = await asyncio.wait_for(
                proc.communicate(), timeout=HERMES_TIMEOUT_SECS
            )
        except asyncio.TimeoutError:
            proc.kill()
            await proc.wait()
            return {
                "ok": False,
                "error": f"hermes -z timed out after {HERMES_TIMEOUT_SECS}s",
            }
    except FileNotFoundError:
        return {"ok": False, "error": f"hermes binary not found at {hermes_bin!r}"}

    elapsed = round(time.time() - started, 2)
    reply = (stdout_b or b"").decode("utf-8", errors="replace").strip()
    err = (stderr_b or b"").decode("utf-8", errors="replace").strip()

    if proc.returncode != 0 and not reply:
        return {
            "ok": False,
            "error": f"hermes exited {proc.returncode}: {err[:500]}",
            "elapsed_secs": elapsed,
        }
    return {"ok": True, "reply": reply, "elapsed_secs": elapsed, "session_id": session_id}


# ---------------------------------------------------------------------------
# aiohttp app + auth
# ---------------------------------------------------------------------------


@web.middleware
async def auth_middleware(request: web.Request, handler):
    if request.path == "/health" or request.method == "OPTIONS":
        return await handler(request)
    expected = request.app["agenthub_token"]
    auth = request.headers.get("Authorization", "")
    if not auth.startswith("Bearer "):
        return web.json_response({"error": "missing bearer token"}, status=401)
    presented = auth[len("Bearer ") :].strip()
    if not hmac.compare_digest(presented.encode(), expected.encode()):
        return web.json_response({"error": "invalid token"}, status=403)
    return await handler(request)


@web.middleware
async def cors_middleware(request: web.Request, handler):
    if request.method == "OPTIONS":
        return web.Response(headers=_cors_headers())
    resp: web.StreamResponse = await handler(request)
    for k, v in _cors_headers().items():
        resp.headers[k] = v
    return resp


def _cors_headers() -> Dict[str, str]:
    return {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
        "Access-Control-Allow-Headers": "Authorization, Content-Type",
    }


async def _h_health(request: web.Request) -> web.Response:
    return web.json_response({
        "ok": True,
        "service": "agenthub",
        "version": "0.4.0",
    })


async def _h_sessions(request: web.Request) -> web.Response:
    try:
        limit = min(int(request.query.get("limit", DEFAULT_SESSION_LIMIT)), 500)
        offset = max(int(request.query.get("offset", 0)), 0)
    except ValueError:
        return web.json_response({"error": "bad limit/offset"}, status=400)
    sessions = await asyncio.to_thread(list_sessions, limit, offset)
    return web.json_response({"sessions": sessions})


async def _h_session_meta(request: web.Request) -> web.Response:
    sid = request.match_info["session_id"]
    meta = await asyncio.to_thread(get_session, sid)
    if not meta:
        return web.json_response({"error": "session not found"}, status=404)
    return web.json_response(meta)


async def _h_session_messages(request: web.Request) -> web.Response:
    sid = request.match_info["session_id"]
    try:
        limit = min(int(request.query.get("limit", MAX_MESSAGES)), MAX_MESSAGES)
    except ValueError:
        return web.json_response({"error": "bad limit"}, status=400)
    msgs = await asyncio.to_thread(get_messages, sid, limit)
    return web.json_response({"session_id": sid, "messages": msgs})


async def _h_chat(request: web.Request) -> web.Response:
    if request.content_length and request.content_length > MAX_CHAT_BODY:
        return web.json_response({"error": "body too large"}, status=413)
    try:
        body = await request.json()
    except Exception:
        return web.json_response({"error": "invalid JSON"}, status=400)
    content = (body.get("content") or "").strip()
    session_id = body.get("session_id") or None
    if not content:
        return web.json_response({"error": "content required"}, status=400)
    result = await send_message(content, session_id)
    status = 200 if result.get("ok") else 502
    return web.json_response(result, status=status)


async def _h_capabilities(request: web.Request) -> web.Response:
    """Return basic metadata about this Hermes instance."""
    info: Dict[str, Any] = {"hermes_home": None}
    try:
        from hermes_constants import get_hermes_home
        info["hermes_home"] = str(get_hermes_home())
    except Exception:
        pass
    try:
        from hermes_cli.config import load_config
        cfg = load_config()
        info["model"] = cfg.get("model")
        info["provider"] = cfg.get("provider")
    except Exception:
        info["model"] = None
        info["provider"] = None
    return web.json_response(info)


def build_app(token: str) -> web.Application:
    app = web.Application(middlewares=[cors_middleware, auth_middleware])
    app["agenthub_token"] = token
    app.router.add_get("/health", _h_health)
    app.router.add_get("/v1/sessions", _h_sessions)
    app.router.add_get("/v1/sessions/{session_id}", _h_session_meta)
    app.router.add_get("/v1/sessions/{session_id}/messages", _h_session_messages)
    app.router.add_post("/v1/chat", _h_chat)
    app.router.add_get("/v1/capabilities", _h_capabilities)
    return app


async def run_server(host: str, port: int, token: str) -> None:
    app = build_app(token)
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, host, port, reuse_address=True)
    await site.start()
    logger.info("[agenthub] listening on %s:%d", host, port)
    while True:
        await asyncio.sleep(3600)
