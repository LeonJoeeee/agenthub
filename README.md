# AgentHub — Mobile Client for Self-Hosted Agents

> "Plex for AI agents." Run an agent on your home/server box, scan a QR
> with your phone, chat with it from anywhere.

**Status:** v0.4 — pure Flutter client + Hermes plugin. Single-platform
(Hermes only), single-machine, single-user. Earlier 9-adapter Node bridge
has been deleted.

## Architecture

```
+------------------+      direct HTTP/WS over LAN       +------------------+
|  Flutter App     | <-------------------------------> |  Hermes process   |
|  (Android/iOS)   |    Bearer-token auth, /v1/* API   |  + agenthub plugin |
|                  |                                    |  (port 18790)     |
+------------------+                                    +------------------+
```

* **No middle server.** The App talks directly to the agent process.
* **No cloud account.** Token + host/port are stored on the phone in
  `shared_preferences`.
* **Pull model.** App fetches latest sessions/messages on open. v0.4 has
  no realtime push — that comes in v0.5 via FCM/APNs.
* **Plugin-installed gateway.** The agent side gets one tiny Python
  plugin (`plugin/agenthub/`). No core Hermes patches.

## Repository layout

```
agenthub/
├── lib/                    Flutter client
│   ├── clients/            HermesClient (HTTP)
│   ├── models/             AgentInstance, ChatMessage, ChatSession
│   ├── protocol/           AgentEndpoint + pair-URI parser
│   ├── screens/            home, add_agent, session, chat
│   └── services/           AgentStore (shared_preferences)
├── plugin/agenthub/        Hermes plugin (Python)
│   ├── plugin.yaml         Plugin manifest
│   ├── __init__.py         register() + daemon-thread bootstrap
│   ├── server.py           aiohttp routes
│   └── auth.py             token + QR helpers
├── android/, ios/          Flutter platform shells
└── pubspec.yaml
```

## Plugin install (one-time, on the agent host)

```bash
# clone the repo somewhere (or use hermes plugins install)
git clone https://github.com/LeonJoeeee/agenthub
ln -s $(pwd)/agenthub/plugin/agenthub ~/.hermes/plugins/agenthub
hermes plugins enable agenthub
```

The plugin starts inside any long-running Hermes process (`hermes gateway run`,
`hermes acp`, `hermes chat`). On first start it generates a token, persists
it to `~/.hermes/agenthub.json`, and prints a QR code to stderr like:

```
+--------------------------------------------------------------+
|  AgentHub mobile pairing                                     |
+--------------------------------------------------------------+
█▀▀▀▀▀█ ... QR ...
  URL:   agenthub://pair?host=192.168.x.x&port=18790&token=...
  HTTP:  http://192.168.x.x:18790
```

**Environment knobs**:
* `AGENTHUB_PORT` — port to bind (default 18790)
* `AGENTHUB_HOST` — bind interface (default 0.0.0.0)
* `AGENTHUB_DISPLAY_HOST` — host shown in QR (default = LAN IP auto-detect)
* `AGENTHUB_FORCE_START=1` — start the server even from short-lived commands

## Mobile App

```bash
cd agenthub
flutter pub get
flutter run                # connected device or emulator
flutter build apk --release
```

Open the App, tap "Scan to add", point camera at the QR — done.

## Plugin API

All endpoints require `Authorization: Bearer <token>` except `/health`.

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/health` | liveness, public |
| GET | `/v1/sessions?limit=N` | list recent sessions |
| GET | `/v1/sessions/{id}` | session metadata |
| GET | `/v1/sessions/{id}/messages?limit=N` | message history |
| POST | `/v1/chat` | send a message; body `{content, session_id?}` |
| GET | `/v1/capabilities` | model + provider info |

`POST /v1/chat` currently spawns `hermes -z`, so each call starts a fresh
turn — full session resumption is a v0.5 task (will switch to in-process
delivery via Hermes's api_server gateway).

## Roadmap

| Version | Item | Status |
|---------|------|--------|
| v0.4 | Flutter pure-client + plugin scaffold | ✓ |
| v0.4 | Sessions list, message history, basic send | ✓ |
| v0.4 | QR pairing | ✓ |
| v0.5 | True session resumption (api_server delegation) | — |
| v0.5 | FCM/APNs push so agents can ping the phone | — |
| v0.5 | Settings UI (model switch, skill toggle) | — |
| v0.5 | Tool-approval round-trip via WS | — |
| v0.6 | iOS release + App Store | — |
| v0.6 | Multi-platform: Claude Code, Aider, Codex CLI | — |

## Why this shape

Earlier attempts wrapped each agent platform behind a Node.js bridge
server (9 adapters: openclaw / dify / claude / openai / coze / flowise /
maxkb / n8n). That layer translated N protocols into a custom one — pure
maintenance tax with no independent value. The current design **borrows
the agent's existing API surface** (Hermes already exposes everything
needed via its plugin lifecycle + state.db), so the App's job shrinks to
"render that surface nicely on a phone".

## License

TBD.
