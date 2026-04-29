/**
 * Agent Platform Adapter — OpenClaw适配器
 * 
 * 通过OpenClaw CLI与agent通信
 */

import { execFile } from 'child_process';
import { promisify } from 'util';

const execFileAsync = promisify(execFile);

export class OpenClawAdapter {
  constructor(config) {
    this.openclawBin = config.openclawBin || 'openclaw';
    this.platform = 'openclaw';
    this.name = config.name || 'OpenClaw Agent';
  }

  async getStatus() {
    try {
      const r = await this._oc(['gateway', 'status'], 5000);
      const sessions = await this.listSessions();
      return {
        online: r.ok,
        platform: 'openclaw',
        model: sessions[0]?.model || 'unknown',
        activeSessions: sessions.length,
        version: '2026.4.15',
      };
    } catch (e) {
      return { online: false, error: e.message };
    }
  }

  async listSessions(auth, agentId) {
    const args = ['sessions', '--json', '--all-agents'];
    if (agentId) args.push('--agent', agentId);
    const r = await this._oc(args, 10000);
    if (!r.ok) return [];
    try {
      const data = JSON.parse(r.stdout);
      return (data.sessions || []).map(s => ({
        id: s.sessionId,
        key: s.key,
        label: s.key?.split(':').pop() || s.sessionId,
        model: s.model,
        updatedAt: s.updatedAt,
        inputTokens: s.inputTokens || s.totalTokens,
        outputTokens: s.outputTokens,
      }));
    } catch { return []; }
  }

  async createSession(auth, opts = {}) {
    const agentId = opts.agent || 'main';
    const sessionLabel = opts.label || crypto.randomUUID().slice(0, 8);
    const key = `agent:${agentId}:${sessionLabel}`;
    return { id: crypto.randomUUID(), key, label: sessionLabel, model: null };
  }

  async chat(sessionKey, message, auth, opts = {}) {
    const effectiveKey = sessionKey || `agenthub:${crypto.randomUUID().slice(0, 8)}`;
    const args = ['agent', '--message', message, '--json', '--session-id', effectiveKey];
    if (opts.agent) args.push('--agent', opts.agent);
    if (opts.thinking) args.push('--thinking', opts.thinking);
    if (opts.timeout) args.push('--timeout', String(opts.timeout));

    const r = await this._oc(args, (opts.timeout || 120) * 1000 + 5000);
    if (!r.ok) return { ok: false, error: r.stderr || 'Agent failed' };

    try {
      const data = JSON.parse(r.stdout);
      const reply = data.result?.meta?.finalAssistantVisibleText
        || data.result?.meta?.finalAssistantRawText
        || data.result?.payloads?.[0]?.text
        || data.turn?.finalAssistantVisibleText
        || data.turn?.finalAssistantRawText
        || data.reply
        || data.message
        || '';
      return { ok: true, reply, data };
    } catch {
      const lines = r.stdout.split('\n').filter(l =>
        !l.startsWith('[plugins]') && !l.startsWith('[INFO]') && !l.startsWith('[hermes]') && l.trim().length > 0
      );
      return { ok: true, reply: lines.join('\n'), data: null };
    }
  }

  /// OpenClaw doesn't support true streaming via CLI, so we simulate it
  async *chatStream(sessionKey, message, auth, opts = {}) {
    const result = await this.chat(sessionKey, message, auth, opts);
    if (result.ok && result.reply) {
      yield { type: 'delta', content: result.reply };
      yield { type: 'done' };
    } else {
      yield { type: 'error', error: result.error || 'Agent failed' };
    }
  }

  async _oc(args, timeout = 120000) {
    try {
      const { stdout, stderr } = await execFileAsync(this.openclawBin, args, {
        timeout,
        maxBuffer: 10 * 1024 * 1024,
        env: { ...process.env, HOME: process.env.HOME || '/root' },
      });
      return { ok: true, stdout, stderr };
    } catch (e) {
      const stdout = e.stdout || '';
      const stderr = e.stderr || e.message || '';
      if (stdout.trim().length > 0) return { ok: true, stdout, stderr };
      return { ok: false, stdout, stderr, code: e.code };
    }
  }
}
