# agenthub Hermes plugin

Hermes plugin that exposes a token-authed HTTP API on port 18790 (default)
so the AgentHub mobile App can list sessions, view message history, and
send chat messages.

## Install

```bash
# from a local clone:
ln -s $(pwd)/agenthub/plugin/agenthub ~/.hermes/plugins/agenthub
hermes plugins enable agenthub

# or via hermes plugins install (when published to git):
hermes plugins install LeonJoeeee/agenthub#subdirectory=plugin/agenthub
```

## Lifecycle

Loaded by Hermes's plugin discovery on any **long-running** entrypoint
(`hermes gateway run`, `hermes acp`, `hermes chat`, `hermes dashboard --tui`).
Skipped for one-shot commands like `hermes -z`.

A daemon thread runs the aiohttp server. On first start it mints a bearer
token and persists it to `~/.hermes/agenthub.json`; on every start it
prints a QR-encoded `agenthub://pair?host=...&port=...&token=...` URL.

## Endpoints

See repo `README.md`.

## Sources of truth

* **Reads** — `~/.hermes/state.db` (SQLite, `sessions` + `messages` tables).
  Read-only, fresh connection per request.
* **Writes** — spawns `hermes -z <prompt>` as a subprocess. Each call is a
  fresh oneshot turn; no session resumption yet (v0.5 will switch to
  api_server delegation for in-process speed and proper context carry-over).

## Env vars

| Var | Default | Purpose |
|-----|---------|---------|
| `AGENTHUB_HOST` | `0.0.0.0` | bind interface |
| `AGENTHUB_PORT` | `18790` | bind port |
| `AGENTHUB_DISPLAY_HOST` | (auto-detected LAN IP) | host advertised in the QR |
| `AGENTHUB_FORCE_START` | unset | force server start even in short-lived commands |
| `HERMES_BIN` | `hermes` | binary to spawn for `/v1/chat` |
