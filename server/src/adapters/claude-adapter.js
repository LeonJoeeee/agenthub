/**
 * Agent Platform Adapter — Anthropic Claude API 适配器
 * 
 * 直连Anthropic Messages API
 * API: https://api.anthropic.com/v1/messages
 * 认证: x-api-key header
 */

export class ClaudeAdapter {
  constructor(config) {
    this.apiKey = config.apiKey;            // Anthropic API Key
    this.model = config.model || 'claude-sonnet-4-20250514';
    this.baseUrl = config.baseUrl || 'https://api.anthropic.com';
    this.platform = 'claude';
    this.name = config.name || 'Claude';
  }

  async getStatus() {
    if (!this.apiKey) return { online: false, error: 'Missing apiKey' };
    // Anthropic has no status endpoint — just return configured
    return { online: true, platform: 'claude', model: this.model };
  }

  async listSessions(auth) {
    // Claude API is stateless — no session management
    return [];
  }

  async createSession(auth, opts = {}) {
    return {
      id: `claude-${Date.now()}`,
      key: `claude:${Date.now()}`,
      label: opts.label || 'New Chat',
      model: this.model,
    };
  }

  async chat(sessionKey, message, auth, opts = {}) {
    try {
      const resp = await fetch(`${this.baseUrl}/v1/messages`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': this.apiKey,
          'anthropic-version': '2023-06-01',
          'anthropic-dangerous-direct-browser-access': 'true',
        },
        body: JSON.stringify({
          model: this.model,
          max_tokens: opts.maxTokens || 4096,
          system: opts.systemPrompt || 'You are a helpful assistant.',
          messages: [
            ...(opts.history || []),
            { role: 'user', content: message },
          ],
        }),
        signal: AbortSignal.timeout((opts.timeout || 120) * 1000),
      });

      if (!resp.ok) {
        const err = await resp.text();
        return { ok: false, error: `HTTP ${resp.status}: ${err.substring(0, 200)}` };
      }

      const data = await resp.json();
      const reply = data.content?.[0]?.text || '';
      return { ok: true, reply, usage: data.usage };
    } catch (e) {
      return { ok: false, error: e.message };
    }
  }

  async *chatStream(sessionKey, message, auth, opts = {}) {
    try {
      const resp = await fetch(`${this.baseUrl}/v1/messages`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': this.apiKey,
          'anthropic-version': '2023-06-01',
          'anthropic-dangerous-direct-browser-access': 'true',
        },
        body: JSON.stringify({
          model: this.model,
          max_tokens: opts.maxTokens || 4096,
          stream: true,
          system: opts.systemPrompt || 'You are a helpful assistant.',
          messages: [
            ...(opts.history || []),
            { role: 'user', content: message },
          ],
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
          if (!line.startsWith('data:')) continue;
          try {
            const data = JSON.parse(line.slice(5).trim());
            if (data.type === 'content_block_delta' && data.delta?.text) {
              yield { type: 'delta', content: data.delta.text };
            } else if (data.type === 'message_stop') {
              yield { type: 'done' };
            }
          } catch {}
        }
      }
      yield { type: 'done' };
    } catch (e) {
      yield { type: 'error', error: e.message };
    }
  }
}
