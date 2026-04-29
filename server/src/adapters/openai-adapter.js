/**
 * Agent Platform Adapter — 通用OpenAI兼容适配器
 * 
 * 适用于：Dify, FastGPT, Ollama, vLLM, LocalAI, LM Studio, 
 *         任何暴露 /v1/chat/completions 的平台
 */

import { createHmac } from 'crypto';

export class OpenAIAdapter {
  constructor(config) {
    this.baseUrl = config.baseUrl;          // e.g. http://localhost:11434/v1
    this.apiKey = config.apiKey || '';       // API key (optional for local)
    this.model = config.model || 'default';  // Model name
    this.platform = config.platform || 'openai-compatible';
    this.name = config.name || 'OpenAI Agent';
  }

  /// Check if the agent is reachable
  async getStatus() {
    try {
      const resp = await fetch(`${this.baseUrl}/models`, {
        headers: this._headers(),
        signal: AbortSignal.timeout(5000),
      });
      if (!resp.ok) return { online: false, error: `HTTP ${resp.status}` };
      const data = await resp.json();
      const models = data.data || data;
      return {
        online: true,
        model: this.model,
        platform: this.platform,
        availableModels: Array.isArray(models) ? models.map(m => m.id || m.name || m) : [],
      };
    } catch (e) {
      return { online: false, error: e.message };
    }
  }

  /// List conversations (not all platforms support this)
  async listSessions(auth) {
    // OpenAI-compatible APIs typically don't have session management
    // Return empty — sessions are managed client-side
    return [];
  }

  /// Create a new conversation
  async createSession(auth, opts = {}) {
    return {
      id: crypto.randomUUID(),
      key: `openai:${this.platform}:${Date.now()}`,
      label: opts.label || 'New Chat',
      model: this.model,
    };
  }

  /// Send a message (non-streaming)
  async chat(sessionKey, message, auth, opts = {}) {
    try {
      const resp = await fetch(`${this.baseUrl}/chat/completions`, {
        method: 'POST',
        headers: this._headers(),
        body: JSON.stringify({
          model: this.model,
          messages: [
            ...(opts.systemPrompt ? [{ role: 'system', content: opts.systemPrompt }] : []),
            ...(opts.history || []),
            { role: 'user', content: message },
          ],
          temperature: opts.temperature ?? 0.7,
          max_tokens: opts.maxTokens ?? 4096,
        }),
        signal: AbortSignal.timeout((opts.timeout || 120) * 1000),
      });

      if (!resp.ok) {
        const err = await resp.text();
        return { ok: false, error: `HTTP ${resp.status}: ${err.substring(0, 200)}` };
      }

      const data = await resp.json();
      const reply = data.choices?.[0]?.message?.content || '';
      return { ok: true, reply, usage: data.usage };
    } catch (e) {
      return { ok: false, error: e.message };
    }
  }

  /// Send a message with SSE streaming — yields chunks
  async *chatStream(sessionKey, message, auth, opts = {}) {
    try {
      const resp = await fetch(`${this.baseUrl}/chat/completions`, {
        method: 'POST',
        headers: this._headers(),
        body: JSON.stringify({
          model: this.model,
          messages: [
            ...(opts.systemPrompt ? [{ role: 'system', content: opts.systemPrompt }] : []),
            ...(opts.history || []),
            { role: 'user', content: message },
          ],
          temperature: opts.temperature ?? 0.7,
          max_tokens: opts.maxTokens ?? 4096,
          stream: true,
        }),
        signal: AbortSignal.timeout((opts.timeout || 120) * 1000),
      });

      if (!resp.ok) {
        const err = await resp.text();
        yield { type: 'error', error: `HTTP ${resp.status}: ${err.substring(0, 200)}` };
        return;
      }

      const reader = resp.body.getReader();
      const decoder = new TextDecoder();
      let buffer = '';

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split('\n');
        buffer = lines.pop() || '';

        for (const line of lines) {
          if (!line.startsWith('data: ') || line === 'data: [DONE]') continue;
          try {
            const data = JSON.parse(line.slice(6));
            const delta = data.choices?.[0]?.delta?.content || '';
            if (delta) yield { type: 'delta', content: delta };
          } catch {}
        }
      }

      yield { type: 'done' };
    } catch (e) {
      yield { type: 'error', error: e.message };
    }
  }

  _headers() {
    const h = { 'Content-Type': 'application/json' };
    if (this.apiKey) h['Authorization'] = `Bearer ${this.apiKey}`;
    return h;
  }
}
