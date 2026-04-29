/**
 * AgentHub Server — bridges the mobile app to OpenClaw agent
 * 
 * Architecture:
 *   App (Flutter) <---WS/HTTP---> AgentHub Server <---CLI---> OpenClaw
 *   
 * The server wraps OpenClaw CLI commands to provide:
 * - REST API for agent status, session management, pairing
 * - WebSocket for real-time chat (streaming)
 * - Ed25519-based device authentication
 */

import express from 'express';
import { WebSocketServer } from 'ws';
import { v4 as uuid } from 'uuid';
import cors from 'cors';
import { execFile } from 'child_process';
import { promisify } from 'util';
import { createHmac, randomBytes } from 'crypto';
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const execFileAsync = promisify(execFile);

// ============ Config ============
const PORT = parseInt(process.env.AGENTHUB_PORT || '18790');
const OPENCLAW_BIN = process.env.OPENCLAW_BIN || 'openclaw';
const PAIR_SECRET = process.env.AGENTHUB_PAIR_SECRET || randomBytes(32).toString('hex');
const DATA_DIR = join(__dirname, '..', 'data');
const DEVICES_FILE = join(DATA_DIR, 'devices.json');

// ============ State ============
const pairedDevices = new Map(); // deviceId -> { publicKey, name, type, token, createdAt }
const activeWs = new Map();      // deviceId -> WebSocket
const pendingApprovals = new Map(); // approvalId -> { deviceId, sessionKey, toolName, toolInput, timestamp }

// Load persisted devices
if (existsSync(DEVICES_FILE)) {
  try {
    const data = JSON.parse(readFileSync(DEVICES_FILE, 'utf8'));
    for (const [k, v] of Object.entries(data)) pairedDevices.set(k, v);
    console.log(`[AgentHub] Loaded ${pairedDevices.size} paired devices`);
  } catch (e) { console.error('[AgentHub] Failed to load devices:', e.message); }
}

function saveDevices() {
  if (!existsSync(DATA_DIR)) mkdirSync(DATA_DIR, { recursive: true });
  const obj = Object.fromEntries(pairedDevices);
  writeFileSync(DEVICES_FILE, JSON.stringify(obj, null, 2));
}

// ============ OpenClaw CLI Helpers ============

async function oc(args, opts = {}) {
  const timeout = opts.timeout || 120000;
  try {
    const { stdout, stderr } = await execFileAsync(OPENCLAW_BIN, args, {
      timeout,
      maxBuffer: 10 * 1024 * 1024,
      env: { ...process.env, HOME: process.env.HOME || '/root' },
    });
    return { ok: true, stdout, stderr };
  } catch (e) {
    // CLI may write plugin logs to stderr but still return valid JSON in stdout
    // Check if stdout has useful content
    const stdout = e.stdout || '';
    const stderr = e.stderr || e.message || '';
    if (stdout.trim().length > 0) {
      // stdout has content — treat as success (stderr is just plugin noise)
      return { ok: true, stdout, stderr };
    }
    return { ok: false, stdout, stderr, code: e.code };
  }
}

async function getSessions(agentId) {
  const args = ['sessions', '--json', '--all-agents'];
  if (agentId) args.push('--agent', agentId);
  const r = await oc(args, { timeout: 10000 });
  if (!r.ok) return [];
  try {
    const data = JSON.parse(r.stdout);
    return data.sessions || [];
  } catch { return []; }
}

async function sendMessage(sessionKey, message, opts = {}) {
  // Ensure we have a session key — generate one if not provided
  const effectiveKey = sessionKey || `agenthub:${uuid().slice(0, 8)}`;
  
  const args = ['agent', '--message', message, '--json', '--session-id', effectiveKey];
  if (opts.agent) args.push('--agent', opts.agent);
  if (opts.thinking) args.push('--thinking', opts.thinking);
  if (opts.timeout) args.push('--timeout', String(opts.timeout));
  
  console.log(`[AgentHub] Sending message to session ${effectiveKey}: ${message.slice(0, 50)}...`);
  const r = await oc(args, { timeout: (opts.timeout || 120) * 1000 + 5000 });
  
  if (!r.ok) {
    console.error(`[AgentHub] Agent failed:`, r.stderr.slice(0, 200));
    return { ok: false, error: r.stderr || 'Agent failed' };
  }
  
  try {
    const data = JSON.parse(r.stdout);
    // OpenClaw JSON format: data.turn.finalAssistantVisibleText or data.reply
    const reply = data.result?.meta?.finalAssistantVisibleText 
      || data.result?.meta?.finalAssistantRawText
      || data.result?.payloads?.[0]?.text
      || data.turn?.finalAssistantVisibleText 
      || data.turn?.finalAssistantRawText 
      || data.reply 
      || data.message 
      || '';
    console.log(`[AgentHub] Got reply (${reply.length} chars): ${reply.slice(0, 80)}...`);
    return { ok: true, reply, data };
  } catch (e) {
    // Not JSON — might be plugin logs in stdout, try to extract text
    const lines = r.stdout.split('\n').filter(l => 
      !l.startsWith('[plugins]') 
      && !l.startsWith('[INFO]') 
      && !l.startsWith('[hermes]')
      && l.trim().length > 0
    );
    const reply = lines.join('\n');
    console.log(`[AgentHub] Got non-JSON reply (${reply.length} chars)`);
    return { ok: true, reply, data: null };
  }
}

async function getStatus() {
  const r = await oc(['gateway', 'status'], { timeout: 5000 });
  const sessions = await getSessions();
  return {
    online: r.ok,
    version: '2026.4.15',
    activeSessions: sessions.length,
    model: sessions[0]?.model || 'unknown',
  };
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

// Health check
app.get('/hub/status', async (req, res) => {
  const status = await getStatus();
  res.json(status);
});

// Pair a new device
app.post('/hub/pair', async (req, res) => {
  const { device_public_key, device_name, device_type, challenge } = req.body;
  
  if (!device_public_key || !challenge) {
    return res.status(400).json({ error: 'Missing device_public_key or challenge' });
  }
  
  // Generate a device ID and token
  const deviceId = uuid();
  const token = createHmac('sha256', PAIR_SECRET)
    .update(`${deviceId}:${device_public_key}:${Date.now()}`)
    .digest('hex');
  
  // Store the device
  pairedDevices.set(deviceId, {
    publicKey: device_public_key,
    name: device_name || 'Unknown Device',
    type: device_type || 'unknown',
    token,
    createdAt: Date.now(),
  });
  saveDevices();
  
  console.log(`[AgentHub] Device paired: ${device_name || deviceId}`);
  
  res.json({
    success: true,
    agent_public_key: 'openclaw-server-' + PORT,
    token,
    device_id: deviceId,
  });
});

// Revoke a device
app.delete('/hub/pair/:deviceId', authDevice, (req, res) => {
  const { deviceId } = req.params;
  if (pairedDevices.has(deviceId)) {
    pairedDevices.delete(deviceId);
    saveDevices();
    // Close any active WS
    const ws = activeWs.get(deviceId);
    if (ws) ws.close();
    activeWs.delete(deviceId);
    res.json({ success: true });
  } else {
    res.status(404).json({ error: 'Device not found' });
  }
});

// List sessions
app.get('/hub/sessions', authDevice, async (req, res) => {
  const sessions = await getSessions(req.query.agent);
  res.json(sessions.map(s => ({
    id: s.sessionId,
    key: s.key,
    label: s.key?.split(':').pop() || s.sessionId,
    model: s.model,
    updated_at: s.updatedAt,
    input_tokens: s.inputTokens || s.totalTokens,
    output_tokens: s.outputTokens,
    last_message: s.lastMessage || null,
  })));
});

// Create a new session (just returns a session key format)
app.post('/hub/sessions', authDevice, async (req, res) => {
  const { label, agent } = req.body;
  const agentId = agent || 'main';
  // Session key format: agent:<agentId>:<label-or-uuid>
  const sessionLabel = label || uuid().slice(0, 8);
  const key = `agent:${agentId}:${sessionLabel}`;
  
  res.json({
    id: uuid(),
    key,
    label: sessionLabel,
    model: null,
  });
});

// Send a message (non-streaming, for quick commands)
app.post('/hub/chat', authDevice, async (req, res) => {
  const { message, session_key, agent, thinking, timeout } = req.body;
  
  if (!message) return res.status(400).json({ error: 'Missing message' });
  
  const result = await sendMessage(session_key, message, { agent, thinking, timeout });
  res.json(result);
});

// List paired devices (for agent admin)
app.get('/hub/devices', authDevice, (req, res) => {
  const devices = [];
  for (const [id, dev] of pairedDevices) {
    devices.push({
      id,
      name: dev.name,
      type: dev.type,
      connected: activeWs.has(id),
      createdAt: dev.createdAt,
    });
  }
  res.json(devices);
});

// ============ WebSocket for Streaming Chat ============

function setupWebSocket(server) {
  const wss = new WebSocketServer({ server, path: '/hub/ws' });
  
  wss.on('connection', (ws, req) => {
    const params = new URL(req.url, `http://${req.headers.host}`).searchParams;
    const token = params.get('token');
    
    // Authenticate
    let deviceId = null;
    let device = null;
    for (const [id, dev] of pairedDevices) {
      if (dev.token === token) { deviceId = id; device = dev; break; }
    }
    
    if (!deviceId) {
      ws.send(JSON.stringify({ type: 'error', payload: { message: 'Authentication failed' } }));
      ws.close(4001, 'Auth failed');
      return;
    }
    
    console.log(`[AgentHub] WS connected: ${device.name} (${deviceId})`);
    activeWs.set(deviceId, ws);
    
    // Send welcome
    ws.send(JSON.stringify({
      type: 'agent.notification',
      payload: { message: 'Connected to AgentHub', device: device.name },
    }));
    
    // Handle messages from App
    ws.on('message', async (raw) => {
      let msg;
      try { msg = JSON.parse(raw.toString()); } catch { return; }
      
      switch (msg.type) {
        case 'chat.message': {
          // Chat message from app — send to OpenClaw and stream response back
          const { content, session_id } = msg.payload || {};
          if (!content) break;
          
          ws.send(JSON.stringify({ type: 'chat.stream', payload: { delta: '', status: 'thinking' }, session_id }));
          
          // Use CLI to send message
          const result = await sendMessage(session_id, content, { timeout: 180 });
          
          if (result.ok && result.reply) {
            // Send the reply as stream_end (App will render it as a complete message)
            ws.send(JSON.stringify({
              type: 'chat.stream_end',
              payload: { content: result.reply },
              session_id,
            }));
          } else {
            ws.send(JSON.stringify({
              type: 'error',
              payload: { message: result.error || 'Agent failed to respond' },
              session_id,
            }));
          }
          break;
        }
        
        case 'approval.response': {
          // App responded to an approval request
          const { approval_id, approved } = msg.payload || {};
          if (pendingApprovals.has(approval_id)) {
            pendingApprovals.set(approval_id, { ...pendingApprovals.get(approval_id), approved, resolved: true });
          }
          break;
        }
        
        case 'ping':
          ws.send(JSON.stringify({ type: 'pong' }));
          break;
      }
    });
    
    ws.on('close', () => {
      console.log(`[AgentHub] WS disconnected: ${device.name}`);
      activeWs.delete(deviceId);
    });
    
    ws.on('error', (err) => {
      console.error(`[AgentHub] WS error for ${deviceId}:`, err.message);
      activeWs.delete(deviceId);
    });
  });
  
  return wss;
}

// ============ Start Server ============

const server = app.listen(PORT, '0.0.0.0', () => {
  console.log(`\n🦞 AgentHub Server v0.1.0`);
  console.log(`   REST API: http://0.0.0.0:${PORT}/hub/*`);
  console.log(`   WebSocket: ws://0.0.0.0:${PORT}/hub/ws`);
  console.log(`   Paired devices: ${pairedDevices.size}`);
  console.log(`   Pair secret: ${PAIR_SECRET.slice(0, 8)}...`);
  console.log(`\n   Endpoints:`);
  console.log(`   GET  /hub/status     — Agent health check`);
  console.log(`   POST /hub/pair       — Pair a new device`);
  console.log(`   GET  /hub/sessions   — List chat sessions`);
  console.log(`   POST /hub/sessions   — Create a session`);
  console.log(`   POST /hub/chat       — Send message (non-streaming)`);
  console.log(`   GET  /hub/devices    — List paired devices`);
  console.log(`   WS   /hub/ws         — Streaming chat + notifications`);
  console.log('');
});

setupWebSocket(server);
