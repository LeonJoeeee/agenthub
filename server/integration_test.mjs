/**
 * AgentHub 端到端集成测试 — 模拟Flutter App的完整行为
 * 
 * 这个脚本精确复刻了Flutter App从add_agent_screen.dart到chat_screen.dart
 * 的每一步操作，验证Server的所有API和WS都能正常工作。
 */

import WebSocket from 'ws';
import { createHmac, randomBytes } from 'crypto';

const SERVER = process.env.SERVER_URL || 'http://localhost:18790';
const WS_SERVER = SERVER.replace('http', 'ws').replace('https', 'wss');

let passed = 0, failed = 0, errors = [];
function ok(name) { passed++; console.log(`  ✅ ${name}`); }
function fail(name, detail) { failed++; errors.push({name, detail}); console.log(`  ❌ ${name}: ${detail}`); }

async function api(method, path, body, token) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers['Authorization'] = `Bearer ${token}`;
  const opts = { method, headers };
  if (body) opts.body = JSON.stringify(body);
  const resp = await fetch(`${SERVER}${path}`, opts);
  const data = await resp.json().catch(() => null);
  return { status: resp.status, data };
}

async function wsChat(token, message, sessionId, timeout = 120000) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`${WS_SERVER}/hub/ws?token=${token}`);
    let result = { connected: false, messages: [], reply: null, error: null };
    const timer = setTimeout(() => { ws.close(); reject(new Error('WS timeout')); }, timeout);

    ws.on('open', () => {
      result.connected = true;
      ws.send(JSON.stringify({
        type: 'chat.message',
        payload: { content: message, role: 'user' },
        session_id: sessionId,
      }));
    });

    ws.on('message', (raw) => {
      const msg = JSON.parse(raw.toString());
      result.messages.push(msg);
      if (msg.type === 'chat.stream_end') {
        result.reply = msg.payload.content;
        clearTimeout(timer);
        ws.close();
      } else if (msg.type === 'error') {
        result.error = msg.payload.message;
        clearTimeout(timer);
        ws.close();
      }
    });

    ws.on('close', () => resolve(result));
    ws.on('error', (e) => { clearTimeout(timer); reject(e); });
  });
}

// ==================== TESTS ====================

async function testHealthCheck() {
  console.log('\n📋 1. Health Check (App: add_agent_screen step 1)');
  const { status, data } = await api('GET', '/hub/status');
  if (status === 200 && data?.online === true) {
    ok('Server is online');
    ok(`Model: ${data.model}`);
    ok(`Active sessions: ${data.activeSessions}`);
  } else {
    fail('Server health check', `status=${status}, data=${JSON.stringify(data)}`);
  }
}

async function testUnauthorizedAccess() {
  console.log('\n📋 2. Unauthorized Access (App: no token scenario)');
  const { status } = await api('GET', '/hub/sessions');
  if (status === 401 || status === 403) {
    ok('Blocked without token');
  } else {
    fail('Should block without token', `got status ${status}`);
  }
}

async function testPairing() {
  console.log('\n📋 3. Device Pairing (App: add_agent_screen _connect step 2)');
  const deviceKey = `app-test-${randomBytes(8).toString('hex')}`;
  const { status, data } = await api('POST', '/hub/pair', {
    device_public_key: deviceKey,
    device_name: 'Integration Test Phone',
    device_type: 'android',
    challenge: 'test-challenge-123',
  });
  
  if (data?.success === true && data?.token) {
    ok('Pairing successful');
    ok(`Token: ${data.token.substring(0, 12)}...`);
    ok(`Device ID: ${data.device_id}`);
    return data.token;
  } else {
    fail('Pairing failed', JSON.stringify(data));
    return null;
  }
}

async function testSessionsList(token) {
  console.log('\n📋 4. Session List (App: session_screen _loadSessions)');
  const { status, data } = await api('GET', '/hub/sessions', null, token);
  if (status === 200 && Array.isArray(data)) {
    ok(`Got ${data.length} sessions`);
    if (data.length > 0) {
      const s = data[0];
      ok(`First session: key=${s.key}, model=${s.model}`);
    }
    return data;
  } else {
    fail('Session list failed', `status=${status}`);
    return [];
  }
}

async function testCreateSession(token) {
  console.log('\n📋 5. Create Session (App: session_screen _createNewSession)');
  const { status, data } = await api('POST', '/hub/sessions', { label: 'test-chat' }, token);
  if (status === 200 && data?.key) {
    ok(`Session created: ${data.key}`);
    return data;
  } else {
    fail('Create session failed', JSON.stringify(data));
    return null;
  }
}

async function testRestChat(token) {
  console.log('\n📋 6. REST Chat (App: agent_connection.dart POST /hub/chat)');
  const { status, data } = await api('POST', '/hub/chat', {
    message: 'Say "integration test OK" and nothing else.',
    session_key: 'integration-test-session',
  }, token);
  
  if (status === 200 && data?.ok === true && data?.reply) {
    ok(`Got reply: "${data.reply.substring(0, 80)}"`);
    return true;
  } else {
    fail('REST chat failed', JSON.stringify(data)?.substring(0, 200));
    return false;
  }
}

async function testWebSocketChat(token) {
  console.log('\n📋 7. WebSocket Chat (App: chat_screen.dart full flow)');
  try {
    const result = await wsChat(token, 'Say "WS test OK" and nothing else.', 'ws-test-session');
    if (result.connected) ok('WS connected');
    else fail('WS connection failed');
    
    if (result.reply) ok(`Got WS reply: "${result.reply.substring(0, 80)}"`);
    else if (result.error) fail('WS chat error', result.error.substring(0, 100));
    else fail('WS no reply received');
    
    // Verify message types
    const types = result.messages.map(m => m.type);
    if (types.includes('chat.stream')) ok('Received thinking/stream indicator');
    if (types.includes('chat.stream_end')) ok('Received stream_end');
  } catch (e) {
    fail('WS chat exception', e.message);
  }
}

async function testDeviceList(token) {
  console.log('\n📋 8. Device List (App: home_screen device management)');
  const { status, data } = await api('GET', '/hub/devices', null, token);
  if (status === 200 && Array.isArray(data)) {
    ok(`Found ${data.length} paired device(s)`);
    for (const d of data) {
      ok(`  Device: ${d.name} (${d.type}), connected=${d.connected}`);
    }
  } else {
    fail('Device list failed', `status=${status}`);
  }
}

async function testPingPong(token) {
  console.log('\n📋 9. Ping/Pong Heartbeat (App: agent_connection.dart _startPing)');
  return new Promise((resolve) => {
    const ws = new WebSocket(`${WS_SERVER}/hub/ws?token=${token}`);
    const timer = setTimeout(() => { fail('Ping timeout'); ws.close(); resolve(); }, 10000);
    
    ws.on('open', () => {
      ws.send(JSON.stringify({ type: 'ping', payload: {} }));
    });
    
    ws.on('message', (raw) => {
      const msg = JSON.parse(raw.toString());
      if (msg.type === 'pong') {
        ok('Received pong');
        clearTimeout(timer);
        ws.close();
        resolve();
      }
    });
    
    ws.on('error', () => { clearTimeout(timer); fail('Ping WS error'); resolve(); });
  });
}

async function testDuplicatePairing() {
  console.log('\n📋 10. Duplicate Pairing (App: adding second device)');
  const { data } = await api('POST', '/hub/pair', {
    device_public_key: `app-test-2-${randomBytes(8).toString('hex')}`,
    device_name: 'Second Test Phone',
    device_type: 'ios',
    challenge: 'test-2',
  });
  if (data?.success === true) ok('Second device paired');
  else fail('Second pairing failed', JSON.stringify(data));
}

async function testErrorHandling() {
  console.log('\n📋 11. Error Handling');
  // Invalid path
  const { status: s1 } = await api('GET', '/hub/nonexistent');
  if (s1 === 404) ok('404 for invalid path');
  else fail('Should return 404', `got ${s1}`);
  
  // Invalid pairing (missing fields)
  const { data: d2 } = await api('POST', '/hub/pair', { name: 'no-key' });
  if (d2?.success === false || d2?.error) ok('Rejected invalid pairing');
  else fail('Should reject pairing without key', JSON.stringify(d2));
  
  // Invalid token
  const { status: s3 } = await api('GET', '/hub/sessions', null, 'invalid-token-123');
  if (s3 === 401 || s3 === 403) ok('Rejected invalid token');
  else fail('Should reject invalid token', `got ${s3}`);
}

async function testPublicTunnel() {
  console.log('\n📋 12. Public Tunnel Test (real phone would use this)');
  const pubUrl = 'https://forgotten-contractors-combines-move.trycloudflare.com';
  try {
    const resp = await fetch(`${pubUrl}/hub/status`);
    const data = await resp.json();
    if (data?.online) ok('Public tunnel accessible');
    else fail('Public tunnel returned offline');
    
    // Pair via public URL
    const pairResp = await fetch(`${pubUrl}/hub/pair`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        device_public_key: `pub-test-${randomBytes(8).toString('hex')}`,
        device_name: 'Public Tunnel Phone',
        device_type: 'android',
        challenge: 'pub-test',
      }),
    });
    const pairData = await pairResp.json();
    if (pairData?.success) ok('Public pairing works');
    else fail('Public pairing failed', JSON.stringify(pairData));
  } catch (e) {
    fail('Public tunnel error', e.message);
  }
}

// ==================== RUN ====================

async function main() {
  console.log('🦞 AgentHub Integration Test Suite');
  console.log(`   Server: ${SERVER}`);
  console.log('='.repeat(50));

  await testHealthCheck();
  await testUnauthorizedAccess();
  const token = await testPairing();
  
  if (token) {
    await testSessionsList(token);
    await testCreateSession(token);
    await testRestChat(token);
    await testWebSocketChat(token);
    await testDeviceList(token);
    await testPingPong(token);
  }
  
  await testDuplicatePairing();
  await testErrorHandling();
  await testPublicTunnel();

  console.log('\n' + '='.repeat(50));
  console.log(`📊 Results: ${passed} passed, ${failed} failed`);
  if (errors.length > 0) {
    console.log('\n❌ Failures:');
    errors.forEach(e => console.log(`  - ${e.name}: ${e.detail}`));
  }
  
  // Save report
  const report = `# AgentHub Integration Test Report\n\nDate: ${new Date().toISOString()}\nServer: ${SERVER}\n\n## Summary\n- ✅ Passed: ${passed}\n- ❌ Failed: ${failed}\n\n${errors.length > 0 ? '## Failures\n' + errors.map(e => `- **${e.name}**: ${e.detail}`).join('\n') : 'All tests passed! 🎉'}\n`;
  const fs = await import('fs');
  fs.writeFileSync('/tmp/agenthub_test_report.md', report);
  console.log('\n📄 Report saved to /tmp/agenthub_test_report.md');
  
  process.exit(failed > 0 ? 1 : 0);
}

main().catch(e => { console.error('Fatal:', e); process.exit(1); });
