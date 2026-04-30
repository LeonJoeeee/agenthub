#!/usr/bin/env python3
"""Dev runner: load the agenthub plugin outside Hermes for local testing.

Usage:
    python plugin/run_dev.py

Prints the QR + URL banner and keeps serving until Ctrl+C. The plugin
binds 0.0.0.0:18790 by default (override with AGENTHUB_PORT). Token is
read/created at ~/.hermes/agenthub.json.

This is the script the Flutter integration test
(test/hermes_client_smoke_test.dart) expects to be running.
"""

from __future__ import annotations

import os
import sys
import time
from pathlib import Path

# Pretend we're inside a long-running Hermes process so the plugin's
# auto-skip gate lets us start the server.
os.environ.setdefault("AGENTHUB_FORCE_START", "1")
sys.argv = ["hermes-dev", "gateway", "run"]

# Plugin imports
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

# Hermes core needs to be importable for hermes_constants.get_hermes_home()
HERMES_REPO = Path.home() / ".hermes" / "hermes-agent"
if HERMES_REPO.exists():
    sys.path.insert(0, str(HERMES_REPO))

import agenthub  # type: ignore  # noqa: E402


class _StubCtx:
    """Minimal PluginContext stand-in so register() can be invoked."""
    class _Manifest:
        name = "agenthub"

    manifest = _Manifest()


def main() -> int:
    agenthub.register(_StubCtx())
    print("[run_dev] plugin registered. Ctrl+C to stop.", flush=True)
    try:
        while True:
            time.sleep(60)
    except KeyboardInterrupt:
        print("[run_dev] bye", flush=True)
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
