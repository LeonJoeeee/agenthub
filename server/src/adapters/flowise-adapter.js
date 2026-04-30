/**
 * Agent Platform Adapter — Flowise/Langflow 适配器
 * 
 * 两者都是可视化LLM流程构建器，都暴露类似的REST API
 * Flowise: POST /api/v1/chatflows/{id}, /api/v1/prediction/{id}
 * Langflow: POST /api/v1/run/{flow_id}
 * 
 * 统一用一个适配器覆盖两者
 */

export class FlowiseAdapter {
  constructor(config) {
    this.baseUrl = config.baseUrl;          // e.g. http://localhost:3000
    this.apiKey = config.apiKey;            // Optional API key
    this.flowId = config.flowId;            // Chatflow/Flow ID (required)
    this.platform = config.platform || 'flowise'; // 'flowise' or 'langflow'
    this.name = config.name || (this.platform === 'langflow' ? 'Langflow Flow' : 'Flowise Chatflow');
  }

  async getStatus() {
    if (!this.flowId) return { online: false, error: 'Missing flowId' };
    try {
      const url = this.platform === 'langflow'
        ? `${this.baseUrl}/api/v1/flows`
        : `${this.baseUrl}/api/v1/chatflows`;
      const resp = await fetch(url, {
        headers: this._headers(),
        signal: AbortSignal.timeout(5000),
      });
      if (!resp.ok) return { online: false, error: `HTTP ${resp.status}` };
      return { online: true, platform: this.platform, model: `${this.platform}-flow`, flowId: this.flowId };
    } catch (e) {
      return { online: false, error: e.message };
    }
  }

  async listSessions(auth) {
    // Flowise/Langflow don't have native session management
    return [];
  }

  async createSession(auth, opts = {}) {
    return {
      id: `${this.platform}-${Date.now()}`,
      key: `${this.platform}:${Date.now()}`,
      label: opts.label || 'New Chat',
      model: `${this.platform}-flow`,
    };
  }

  async chat(sessionKey, message, auth, opts = {}) {
    const url = this.platform === 'langflow'
      ? `${this.baseUrl}/api/v1/run/${this.flowId}`
      : `${this.baseUrl}/api/v1/prediction/${this.flowId}`;

    try {
      const body = this.platform === 'langflow'
        ? { inputs: { input_value: message }, session_id: sessionKey, response_type: 'text' }
        : { question: message, overrideConfig: { sessionId: sessionKey } };

      const resp = await fetch(url, {
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
      const reply = this.platform === 'langflow'
        ? (data.outputs?.[0]?.outputs?.[0]?.results?.message?.text || data.result || '')
        : (data.text || data.json?.text || '');
      return { ok: true, reply, data };
    } catch (e) {
      return { ok: false, error: e.message };
    }
  }

  async *chatStream(sessionKey, message, auth, opts = {}) {
    const url = this.platform === 'langflow'
      ? `${this.baseUrl}/api/v1/run/${this.flowId}?stream=true`
      : `${this.baseUrl}/api/v1/prediction/${this.flowId}`;

    try {
      const body = this.platform === 'langflow'
        ? { inputs: { input_value: message }, session_id: sessionKey, response_type: 'stream' }
        : { question: message, overrideConfig: { sessionId: sessionKey } };

      const resp = await fetch(url, {
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

      const contentType = resp.headers.get('content-type') || '';
      if (contentType.includes('text/event-stream')) {
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
            const content = line.slice(5).trim();
            if (content === '[DONE]') continue;
            try {
              const data = JSON.parse(content);
              const delta = data.token || data.text || data.content || '';
              if (delta) yield { type: 'delta', content: delta };
            } catch {
              if (content) yield { type: 'delta', content };
            }
          }
        }
      } else {
        // Non-streaming response
        const data = await resp.json();
        const reply = data.text || data.json?.text || '';
        if (reply) yield { type: 'delta', content: reply };
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
