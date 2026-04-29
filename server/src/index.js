/**
 * AgentHub Server v0.2.0 — Multi-platform Agent Bridge
 * 
 * Architecture:
 *   App (Flutter) <---WS/HTTP---> AgentHub Server <---Adapter---> Any Agent
 * 
 * Supported platforms:
 *   - OpenClaw (via CLI)
 *   - Dify (via REST API)
 *   - OpenAI Compatible (Ollama, FastGPT, vLLM, LM Studio, LocalAI, etc.)
 *   - Any platform with /v1/chat/completions
 */

import express from 'express';
import { WebSocketServer } from 'ws';
import { v4 as uuid } from 'uuid';
import cors from 'cors';
import { createHmac, randomBytes } from 'crypto';
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { createAdapter, listPlatforms } from './adapters/index.js';

const __dirname = dirname(fileURLToPath(import.meta.url));

// ============ Config ============
const PORT = parseInt(process.env.AGENTHUB_PORT || '18790');
const PAIR_SECRET = process.env.AGENTHUB_PAIR_SECRET || randomBytes(32).toString('hex');
const DATA_DIR = join(__dirname, '..', 'data');
const DEVICES_FILE = join(DATA_DIR, 'devices.json');
const AGENTS_FILE = join(DATA_DIR, 'agents.json');

// ============ State ============
const pairedDevices = new Map();
const activeWs = new Map();

// Agent registry — stores configured agents and their adapters
const agentRegistry = new Map(); // agentId -> { config, adapter }
const agentAdapters = new Map(); // agentId -> adapter instance

// Load persisted data
function loadData() {
  if (existsSync(DEVICES_FILE)) {
    try {
      const data = JSON.parse(readFileSync(DEVICES_FILE, 'utf8'));
      for (const [k, v] of Object.entries(data)) pairedDevices.set(k, v);
      console.log(`[AgentHub] Loaded ${pairedDevices.size} paired devices`);
    } catch (e) { console.error('[AgentHub] Failed to load devices:', e.message); }
  }
  if (existsSync(AGENTS_FILE)) {
    try {
      const data = JSON.parse(readFileSync(AGENTS_FILE, 'utf8'));
      for (const [id, config] of Object.entries(data)) {
        agentRegistry.set(id, config);
        agentAdapters.set(id, createAdapter(config));
      }
      console.log(`[AgentHub] Loaded ${agentRegistry.size} agents`);
    } catch (e) { console.error('[AgentHub] Failed to load agents:', e.message); }
  }
}

function saveDevices() {
  if (!existsSync(DATA_DIR)) mkdirSync(DATA_DIR, { recursive: true });
  writeFileSync(DEVICES_FILE, JSON.stringify(Object.fromEntries(pairedDevices), null, 2));
}

function saveAgents() {
  if (!existsSync(DATA_DIR)) mkdirSync(DATA_DIR, { recursive: true });
  writeFileSync(AGENTS_FILE, JSON.stringify(Object.fromEntries(agentRegistry), null, 2));
}

loadData();

// ============ Default Agent (OpenClaw on this server) ============
if (agentRegistry.size === 0) {
  const defaultConfig = {
    platform: 'openclaw',
    name: 'Local OpenClaw',
    openclawBin: process.env.OPENCLAW_BIN || 'openclaw',
  };
  const defaultId = 'default-openclaw';
  agentRegistry.set(defaultId, defaultConfig);
  agentAdapters.set(defaultId, createAdapter(defaultConfig));
  saveAgents();
  console.log(`[AgentHub] Created default agent: ${defaultId}`);
}

// ============ Auth Middleware ============
function authDevice(req, res, next) {
  const token = req.headers['authorization']?.replace('Bearer ', '');
  if (!token) return res.status(401).json({ error: 'No token' });
  let found = null;
  for (const [id, dev] of pairedDevices) {
    if (dev.token === token) { found = { id, ...dev }; break; }
  }
  if (!found) return res.status(403).json({ error: 'Invalid token' });
  req.device = found;
  next();
}

// ============ REST API ============
const app = express();
app.use(cors());
app.use(express.json());

// --- Platform info ---
app.get('/hub/platforms', (req, res) => {
  res.json(listPlatforms());
});

// --- Agent registry ---
app.get('/hub/agents', authDevice, async (req, res) => {
  const agents = [];
  for (const [id, config] of agentRegistry) {
    const adapter = agentAdapters.get(id);
    let status = { online: false };
    try { status = await adapter.getStatus(); } catch {}
    agents.push({
      id,
      name: config.name || id,
      platform: config.platform,
      baseUrl: config.baseUrl || null,
      model: status.model || config.model || null,
      online: status.online,
    });
  }
  res.json(agents);
});

// Add a new agent
app.post('/hub/agents', authDevice, async (req, res) => {
  const { platform, name, baseUrl, apiKey, model, openclawBin } = req.body;
  if (!platform) return res.status(400).json({ error: 'Missing platform' });

  const id = `agent-${uuid().slice(0, 8)}`;
  const config = { platform, name: name || platform, baseUrl, apiKey, model, openclawBin };
  
  const adapter = createAdapter(config);
  const status = await adapter.getStatus().catch(() => ({ online: false }));
  
  agentRegistry.set(id, config);
  agentAdapters.set(id, adapter);
  saveAgents();

  res.json({ id, name: config.name, platform, online: status.online, model: status.model });
});

// Delete an agent
app.delete('/hub/agents/:agentId', authDevice, (req, res) => {
  const { agentId } = req.params;
  if (!agentRegistry.has(agentId)) return res.status(404).json({ error: 'Agent not found' });
  agentRegistry.delete(agentId);
  agentAdapters.delete(agentId);
  saveAgents();
  res.json({ success: true });
});

// --- Agent-specific endpoints (via agentId query param) ---
// Default agent for backward compatibility
function getAdapter(agentId) {
  const id = agentId || agentRegistry.keys().next().value;
  return { adapter: agentAdapters.get(id), config: agentRegistry.get(id), id };
}

// Health check (default agent)
app.get('/hub/status', async (req, res) => {
  const { adapter, config } = getAdapter(req.query.agent);
  if (!adapter) return res.status(404).json({ error: 'Agent not found' });
  const status = await adapter.getStatus();
  res.json(status);
});

// Pair a new device
app.post('/hub/pair', async (req, res) => {
  const { device_public_key, device_name, device_type, challenge } = req.body;
  if (!device_public_key || !challenge) {
    return res.status(400).json({ error: 'Missing device_public_key or challenge' });
  }
  const deviceId = uuid();
  const token = createHmac('sha256', PAIR_SECRET)
    .update(`${deviceId}:${device_public_key}:${Date.now()}`)
    .digest('hex');
  pairedDevices.set(deviceId, {
    publicKey: device_public_key, name: device_name || 'Unknown Device',
    type: device_type || 'unknown', token, createdAt: Date.now(),
  });
  saveDevices();
  console.log(`[AgentHub] Device paired: ${device_name || deviceId}`);
  res.json({ success: true, agent_public_key: 'agenthub-server-' + PORT, token, device_id: deviceId });
});

// Revoke device
app.delete('/hub/pair/:deviceId', authDevice, (req, res) => {
  const { deviceId } = req.params;
  if (pairedDevices.has(deviceId)) {
    pairedDevices.delete(deviceId); saveDevices();
    const ws = activeWs.get(deviceId); if (ws) ws.close(); activeWs.delete(deviceId);
    res.json({ success: true });
  } else { res.status(404).json({ error: 'Device not found' }); }
});

// List sessions
app.get('/hub/sessions', authDevice, async (req, res) => {
  const { adapter } = getAdapter(req.query.agent);
  if (!adapter) return res.status(404).json({ error: 'Agent not found' });
  const sessions = await adapter.listSessions(req.device.token, req.query.agent);
  res.json(sessions);
});

// Create session
app.post('/hub/sessions', authDevice, async (req, res) => {
  const { adapter } = getAdapter(req.body.agent || req.query.agent);
  if (!adapter) return res.status(404).json({ error: 'Agent not found' });
  const session = await adapter.createSession(req.device.token, req.body);
  res.json(session);
});

// REST chat
app.post('/hub/chat', authDevice, async (req, res) => {
  const { message, session_key, agent, thinking, timeout } = req.body;
  if (!message) return res.status(400).json({ error: 'Missing message' });
  const { adapter } = getAdapter(agent);
  if (!adapter) return res.status(404).json({ error: 'Agent not found' });
  const result = await adapter.chat(session_key, message, req.device.token, { agent, thinking, timeout });
  res.json(result);
});

// Device list
app.get('/hub/devices', authDevice, (req, res) => {
  const devices = [];
  for (const [id, dev] of pairedDevices) {
    devices.push({ id, name: dev.name, type: dev.type, connected: activeWs.has(id), createdAt: dev.createdAt });
  }
  res.json(devices);
});

// ============ WebSocket ============
function setupWebSocket(server) {
  const wss = new WebSocketServer({ server, path: '/hub/ws' });

  wss.on('connection', (ws, req) => {
    const params = new URL(req.url, `http://${req.headers.host}`).searchParams;
    const token = params.get('token');
    let deviceId = null, device = null;
    for (const [id, dev] of pairedDevices) {
      if (dev.token === token) { deviceId = id; device = dev; break; }
    }
    if (!deviceId) {
      ws.send(JSON.stringify({ type: 'error', payload: { message: 'Authentication failed' } }));
      ws.close(4001, 'Auth failed'); return;
    }
    console.log(`[AgentHub] WS connected: ${device.name} (${deviceId})`);
    activeWs.set(deviceId, ws);
    ws.send(JSON.stringify({ type: 'agent.notification', payload: { message: 'Connected to AgentHub', device: device.name } }));

    ws.on('message', async (raw) => {
      let msg;
      try { msg = JSON.parse(raw.toString()); } catch { return; }

      switch (msg.type) {
        case 'chat.message': {
          const { content, session_id, agent: agentId } = msg.payload || {};
          if (!content) break;
          
          const { adapter } = getAdapter(agentId);
          if (!adapter) {
            ws.send(JSON.stringify({ type: 'error', payload: { message: 'Agent not found' }, session_id }));
            break;
          }

          ws.send(JSON.stringify({ type: 'chat.stream', payload: { delta: '', status: 'thinking' }, session_id }));

          // Check if adapter supports true streaming
          if (adapter.chatStream && (adapter.platform === 'dify' || adapter.constructor.name === 'OpenAIAdapter')) {
            // True SSE streaming
            let fullContent = '';
            for await (const chunk of adapter.chatStream(session_id, content, device.token, { agent: agentId })) {
              if (chunk.type === 'delta') {
                fullContent += chunk.content;
                ws.send(JSON.stringify({ type: 'chat.stream', payload: { delta: chunk.content }, session_id }));
              } else if (chunk.type === 'done') {
                ws.send(JSON.stringify({ type: 'chat.stream_end', payload: { content: fullContent }, session_id }));
              } else if (chunk.type === 'error') {
                ws.send(JSON.stringify({ type: 'error', payload: { message: chunk.error }, session_id }));
              }
            }
          } else {
            // Fallback: wait for full reply then send
            const result = await adapter.chat(session_id, content, device.token, { agent: agentId, timeout: 180 });
            if (result.ok && result.reply) {
              ws.send(JSON.stringify({ type: 'chat.stream_end', payload: { content: result.reply }, session_id }));
            } else {
              ws.send(JSON.stringify({ type: 'error', payload: { message: result.error || 'Agent failed' }, session_id }));
            }
          }
          break;
        }
        case 'approval.response': {
          // TODO: implement approval flow
          break;
        }
        case 'ping':
          ws.send(JSON.stringify({ type: 'pong' }));
          break;
      }
    });

    ws.on('close', () => { console.log(`[AgentHub] WS disconnected: ${device.name}`); activeWs.delete(deviceId); });
    ws.on('error', (err) => { console.error(`[AgentHub] WS error:`, err.message); activeWs.delete(deviceId); });
  });
  return wss;
}

// ============ Start ============
const server = app.listen(PORT, '0.0.0.0', () => {
  console.log(`\n🦞 AgentHub Server v0.2.0`);
  console.log(`   REST API: http://0.0.0.0:${PORT}/hub/*`);
  console.log(`   WebSocket: ws://0.0.0.0:${PORT}/hub/ws`);
  console.log(`   Paired devices: ${pairedDevices.size}`);
  console.log(`   Registered agents: ${agentRegistry.size}`);
  console.log(`\n   Supported platforms:`);
  for (const p of listPlatforms()) {
    console.log(`   - ${p.name} (${p.id})`);
  }
  console.log(`\n   Endpoints:`);
  console.log(`   GET  /hub/platforms   — List supported platforms`);
  console.log(`   GET  /hub/agents      — List registered agents`);
  console.log(`   POST /hub/agents      — Add a new agent`);
  console.log(`   DEL  /hub/agents/:id  — Remove an agent`);
  console.log(`   GET  /hub/status      — Agent health check`);
  console.log(`   POST /hub/pair        — Pair a new device`);
  console.log(`   GET  /hub/sessions    — List chat sessions`);
  console.log(`   POST /hub/chat        — Send message (non-streaming)`);
  console.log(`   WS   /hub/ws          — Streaming chat + notifications`);
  console.log('');
});

setupWebSocket(server);
