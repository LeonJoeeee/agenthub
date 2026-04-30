"""Token + QR helpers for the AgentHub plugin.

The plugin generates a single bearer token on first run and persists it to
``~/.hermes/agenthub.json``. Anyone who has the token can call the plugin's
HTTP/WS API. The token is bundled into a QR code printed at startup so the
mobile App can scan & bind in one shot.
"""

from __future__ import annotations

import io
import json
import logging
import secrets
from pathlib import Path
from typing import Tuple

logger = logging.getLogger(__name__)


def _state_path() -> Path:
    from hermes_constants import get_hermes_home
    return Path(get_hermes_home()) / "agenthub.json"


def load_or_create_token() -> str:
    """Load persisted token, or mint a fresh one and save it."""
    path = _state_path()
    if path.exists():
        try:
            data = json.loads(path.read_text())
            token = data.get("token")
            if isinstance(token, str) and len(token) >= 16:
                return token
        except Exception:
            logger.warning("[agenthub] could not read %s, regenerating", path)
    token = secrets.token_urlsafe(32)
    path.write_text(json.dumps({"token": token}, indent=2))
    try:
        path.chmod(0o600)
    except Exception:
        pass
    return token


def pair_uri(host: str, port: int, token: str) -> str:
    """Build the URI that App scans from the QR."""
    return f"agenthub://pair?host={host}&port={port}&token={token}"


def render_qr_terminal(text: str) -> str:
    """Render a QR code as Unicode block characters for the terminal.

    Uses the ``qrcode`` library if available, falls back to printing the URL
    if not. Returns the rendered string (may contain newlines).
    """
    try:
        import qrcode
    except ImportError:
        return f"(qrcode library not installed — install with: pip install qrcode)\n{text}\n"

    qr = qrcode.QRCode(border=1, error_correction=qrcode.constants.ERROR_CORRECT_M)
    qr.add_data(text)
    qr.make(fit=True)

    matrix = qr.modules
    out = io.StringIO()
    # Two rows per line using half-block characters
    for y in range(0, len(matrix), 2):
        for x in range(len(matrix[y])):
            top = matrix[y][x]
            bot = matrix[y + 1][x] if y + 1 < len(matrix) else False
            if top and bot:
                out.write("█")  # full block
            elif top and not bot:
                out.write("▀")  # upper half
            elif not top and bot:
                out.write("▄")  # lower half
            else:
                out.write(" ")
        out.write("\n")
    return out.getvalue()


def print_pair_banner(host: str, port: int, token: str) -> None:
    """Print the pairing banner with QR + URL to stderr."""
    import sys

    uri = pair_uri(host, port, token)
    qr = render_qr_terminal(uri)
    banner = (
        "\n"
        "+--------------------------------------------------------------+\n"
        "|  AgentHub mobile pairing                                     |\n"
        "|  Scan the QR with the AgentHub App, or open the URL.         |\n"
        "+--------------------------------------------------------------+\n"
        f"{qr}"
        f"  URL:   {uri}\n"
        f"  HTTP:  http://{host}:{port}\n"
        f"  Token: {token[:8]}...{token[-4:]} (full token in App after pair)\n"
        "\n"
    )
    sys.stderr.write(banner)
    sys.stderr.flush()


def detect_lan_host() -> str:
    """Best-effort guess of the LAN IP this machine is reachable at.

    Falls back to 127.0.0.1 if no usable interface is found. We do NOT
    actually open a connection — just use a UDP socket trick to find the
    interface that would route to the public internet.
    """
    import socket

    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.settimeout(0.2)
            s.connect(("8.8.8.8", 80))
            return s.getsockname()[0]
    except Exception:
        return "127.0.0.1"
