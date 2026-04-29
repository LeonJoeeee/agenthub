/**
 * Agent Platform Adapter — Dify专用适配器
 * 
 * Dify有自己的API格式：/v1/chat-messages, /v1/conversations
 * 支持SSE流式输出和conversation管理
 */

export class DifyAdapter {
  constructor(config) {
    this.baseUrl = config.baseUrl;          // e.g. https://api.dify.ai/v1
    this.apiKey = config.apiKey;            // Dify App API Key (required)
    this.user = config.user || 'agenthub-user';
    this.platform = 'dify';
    this.name = config.name || 'Dify Agent';
    this.responseMode = config.responseMode || 'streaming'; // blocking | streaming
  }

  async getStatus() {
    try {
      // Dify doesn't have a status endpoint, try to list conversations
      const resp = await fetch(`${this.baseUrl}/conversations?user=${this.user}`, {
        headers: this._headers(),
        signal: AbortSignal.timeout(5000),
      });
      if (!resp.ok) return { online: false, error: `HTTP ${resp.status}` };
      const data = await resp.json();
      return {
        online: true,
        platform: 'dify',
        model: 'dify-app',
        activeConversations: data.data?.length || 0,
      };
    } catch (e) {
      return { online: false, error: e.message };
    }
  }

  async listSessions(auth) {
    try {
      const resp = await fetch(`${this.baseUrl}/conversations?user=${this.user}`, {
        headers: this._headers(),
        signal: AbortSignal.timeout(10000),
      });
      if (!resp.ok) return [];
      const data = await resp.json();
      return (data.data || []).map(c => ({
        id: c.id,
        key: `dify:${c.id}`,
        label: c.name || c.id,
        model: 'dify-app',
        updatedAt: c.updated_at ? new Date(c.updated_at).getTime() : null,
        inputTokens: c.metadata?.usage?.prompt_tokens,
        outputTokens: c.metadata?.usage?.completion_tokens,
      }));
    } catch {
      return [];
    }
  }

  async createSession(auth, opts = {}) {
    // Dify creates conversations implicitly on first message
    return {
      id: `dify-new-${Date.now()}`,
      key: null,
      label: opts.label || 'New Dify Chat',
      model: 'dify-app',
    };
  }

  async chat(sessionKey, message, auth, opts = {}) {
    try {
      const body = {
        inputs: opts.inputs || {},
        query: message,
        user: this.user,
        response_mode: 'blocking',
      };
      if (sessionKey && !sessionKey.startsWith('dify-new-')) {
        body.conversation_id = sessionKey.replace('dify:', '');
      }

      const resp = await fetch(`${this.baseUrl}/chat-messages`, {
        method: 'POST',
        headers: this._headers(),
        body: JSON.stringify(body),
        signal: AbortSignal.timeout((opts.timeout || 120) * 1000),
      });

      if (!resp.ok) {
        const err = await resp.text();
        return { ok: false, error: `HTTP ${resp.status}: ${err.substring(0, 200)}` };
      }

      const data = await resp.json();
      return {
        ok: true,
        reply: data.answer || '',
        conversationId: data.conversation_id,
        messageId: data.message_id,
        usage: data.metadata?.usage,
      };
    } catch (e) {
      return { ok: false, error: e.message };
    }
  }

  async *chatStream(sessionKey, message, auth, opts = {}) {
    try {
      const body = {
        inputs: opts.inputs || {},
        query: message,
        user: this.user,
        response_mode: 'streaming',
      };
      if (sessionKey && !sessionKey.startsWith('dify-new-')) {
        body.conversation_id = sessionKey.replace('dify:', '');
      }

      const resp = await fetch(`${this.baseUrl}/chat-messages`, {
        method: 'POST',
        headers: this._headers(),
        body: JSON.stringify(body),
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
          if (!line.startsWith('data: ')) continue;
          try {
            const data = JSON.parse(line.slice(6));
            if (data.event === 'message' || data.event === 'agent_message') {
              yield { type: 'delta', content: data.answer || '' };
            } else if (data.event === 'message_end') {
              yield { type: 'done', conversationId: data.conversation_id, messageId: data.message_id };
            } else if (data.event === 'error') {
              yield { type: 'error', error: data.message || 'Dify error' };
            }
          } catch {}
        }
      }

      yield { type: 'done' };
    } catch (e) {
      yield { type: 'error', error: e.message };
    }
  }

  _headers() {
    return {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${this.apiKey}`,
    };
  }
}
