/**
 * Agent Platform Adapter — MaxKB 适配器
 * 
 * MaxKB是飞致智慧开源的知识库问答平台（15k+ stars）
 * API: /api/application/{app_id}/chat (SSE streaming)
 * 认证: API Key
 */

export class MaxKBAdapter {
  constructor(config) {
    this.baseUrl = config.baseUrl;          // e.g. http://localhost:8080
    this.apiKey = config.apiKey;            // MaxKB API Key
    this.appId = config.appId;             // Application ID
    this.platform = 'maxkb';
    this.name = config.name || 'MaxKB App';
  }

  async getStatus() {
    if (!this.appId || !this.apiKey) return { online: false, error: 'Missing appId or apiKey' };
    try {
      const resp = await fetch(`${this.baseUrl}/api/application/${this.appId}/profile`, {
        headers: this._headers(),
        signal: AbortSignal.timeout(5000),
      });
      if (!resp.ok) return { online: false, error: `HTTP ${resp.status}` };
      const data = await resp.json();
      return { online: true, platform: 'maxkb', model: data.data?.model?.name || 'maxkb-app', appId: this.appId };
    } catch (e) {
      return { online: false, error: e.message };
    }
  }

  async listSessions(auth) {
    try {
      const resp = await fetch(
        `${this.baseUrl}/api/application/${this.appId}/chat/client?page_size=20`,
        { headers: this._headers(), signal: AbortSignal.timeout(10000) }
      );
      if (!resp.ok) return [];
      const data = await resp.json();
      return (data.data || []).map(c => ({
        id: c.id,
        key: `maxkb:${c.id}`,
        label: c.title || c.id,
        model: 'maxkb-app',
        updatedAt: c.update_time ? new Date(c.update_time).getTime() : null,
      }));
    } catch { return []; }
  }

  async createSession(auth, opts = {}) {
    try {
      const resp = await fetch(`${this.baseUrl}/api/application/${this.appId}/chat/open`, {
        method: 'POST',
        headers: this._headers(),
        body: JSON.stringify({}),
        signal: AbortSignal.timeout(10000),
      });
      if (!resp.ok) return { id: `maxkb-new-${Date.now()}`, key: null, label: opts.label || 'New Chat', model: 'maxkb-app' };
      const data = await resp.json();
      return { id: data.data?.id || `maxkb-${Date.now()}`, key: `maxkb:${data.data?.id}`, label: opts.label || 'New Chat', model: 'maxkb-app' };
    } catch {
      return { id: `maxkb-new-${Date.now()}`, key: null, label: 'New Chat', model: 'maxkb-app' };
    }
  }

  async chat(sessionKey, message, auth, opts = {}) {
    const chatId = sessionKey?.replace('maxkb:', '') || undefined;
    try {
      const body = { message, re_chat: false };
      if (chatId) body.chat_id = chatId;

      const resp = await fetch(`${this.baseUrl}/api/application/${this.appId}/chat`, {
        method: 'POST',
        headers: this._headers(),
        body: JSON.stringify(body),
        signal: AbortSignal.timeout((opts.timeout || 120) * 1000),
      });

      if (!resp.ok) {
        const err = await resp.text();
        return { ok: false, error: `HTTP ${resp.status}: ${err.substring(0, 200)}` };
      }

      // MaxKB returns SSE even in non-streaming mode sometimes
      const text = await resp.text();
      let reply = '';
      for (const line of text.split('\n')) {
        if (line.startsWith('data:')) {
          try {
            const d = JSON.parse(line.slice(5).trim());
            if (d.content) reply += d.content;
          } catch {}
        }
      }
      if (!reply) {
        try { reply = JSON.parse(text).data?.content || text; } catch { reply = text; }
      }
      return { ok: true, reply };
    } catch (e) {
      return { ok: false, error: e.message };
    }
  }

  async *chatStream(sessionKey, message, auth, opts = {}) {
    const chatId = sessionKey?.replace('maxkb:', '') || undefined;
    try {
      const body = { message, re_chat: false, stream: true };
      if (chatId) body.chat_id = chatId;

      const resp = await fetch(`${this.baseUrl}/api/application/${this.appId}/chat`, {
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
          if (!line.startsWith('data:')) continue;
          try {
            const d = JSON.parse(line.slice(5).trim());
            if (d.content) yield { type: 'delta', content: d.content };
            if (d.is_end) yield { type: 'done' };
          } catch {}
        }
      }
      yield { type: 'done' };
    } catch (e) {
      yield { type: 'error', error: e.message };
    }
  }

  _headers() {
    return { 'Content-Type': 'application/json', 'Authorization': `Bearer ${this.apiKey}` };
  }
}
