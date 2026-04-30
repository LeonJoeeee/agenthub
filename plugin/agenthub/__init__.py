"""agenthub — Hermes plugin that exposes a token-authed HTTP API for the
AgentHub Flutter App.

When loaded in a long-running Hermes process (gateway / acp / chat),
``register()`` spawns a daemon thread running aiohttp on a configurable
host:port. A bearer token is generated on first launch and persisted to
``~/.hermes/agenthub.json``; the same token is encoded into a QR printed
to stderr so the mobile App can scan & bind.

Short-lived commands (``hermes -z``, ``hermes status``) skip the server
to avoid port-fight noise.
"""

from __future__ import annotations

import asyncio
import logging
import os
import sys
import threading

from .auth import detect_lan_host, load_or_create_token, print_pair_banner
from .server import run_server

logger = logging.getLogger(__name__)

DEFAULT_PORT = 18790
_started = False


def _bind_host() -> str:
    forced = os.environ.get("AGENTHUB_HOST")
    if forced:
        return forced
    return "0.0.0.0"


def _display_host() -> str:
    forced = os.environ.get("AGENTHUB_DISPLAY_HOST")
    if forced:
        return forced
    return detect_lan_host()


def _bind_port() -> int:
    raw = os.environ.get("AGENTHUB_PORT")
    if raw:
        try:
            return int(raw)
        except ValueError:
            logger.warning("[agenthub] AGENTHUB_PORT=%r is not an int; using %d", raw, DEFAULT_PORT)
    return DEFAULT_PORT


def _is_long_running() -> bool:
    """Only start the server in contexts where Hermes itself runs persistently."""
    if os.environ.get("AGENTHUB_FORCE_START"):
        return True
    argv = " ".join(sys.argv)
    return any(kw in argv for kw in ("gateway", "dashboard", "acp", "chat", "--tui"))


def _serve(host: str, port: int, token: str) -> None:
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    try:
        loop.run_until_complete(run_server(host, port, token))
    except OSError as exc:
        logger.warning("[agenthub] could not bind %s:%d: %s", host, port, exc)
    except Exception:
        logger.exception("[agenthub] server crashed")


def register(ctx) -> None:
    global _started
    if _started:
        return
    if not _is_long_running():
        return
    _started = True

    host_bind = _bind_host()
    host_display = _display_host()
    port = _bind_port()
    token = load_or_create_token()

    t = threading.Thread(
        target=_serve, args=(host_bind, port, token),
        daemon=True, name="agenthub-server",
    )
    t.start()
    print_pair_banner(host_display, port, token)
    logger.info("[agenthub] plugin started; bind=%s:%d display=%s", host_bind, port, host_display)
