/**
 * Agent Platform Adapter — Coze (扣子) 适配器
 * 
 * 字节跳动旗下AI平台，国内用户量最大
 * API: https://api.coze.cn/v3/chat (国内) / https://api.coze.com/v3/chat (国际)
 * 支持对话流式输出、bot管理
 */

export class CozeAdapter {
  constructor(config) {
    this.baseUrl = config.baseUrl || 'https://api.coze.cn'; // 国内默认
    this.apiKey = config.apiKey;           // Coze Personal Access Token
    this.botId = config.botId;             // Bot ID (required)
    this.userId = config.userId || 'agenthub-user';
    this.platform = 'coze';
    this.name = config.name || 'Coze Bot';
  }

  async getStatus() {
    if (!this.botId || !this.apiKey) {
      return { online: false, error: 'Missing botId or apiKey' };
    }
    try {
      const resp = await fetch(`${this.baseUrl}/v1/bot/get_online_info?bot_id=${this.botId}`, {
        headers: this._headers(),
        signal: AbortSignal.timeout(5000),
      });
      if (!resp.ok) return { online: false, error: `HTTP ${resp.status}` };
      return { online: true, platform: 'coze', model: 'coze-bot', botId: this.botId };
    } catch (e) {
      return { online: false, error: e.message };
    }
  }

  async listSessions(auth) {
    // Coze manages conversations server-side
    try {
      const resp = await fetch(
        `${this.baseUrl}/v1/conversation/list?bot_id=${this.botId}&user_id=${this.userId}&page_size=20`,
        { headers: this._headers(), signal: AbortSignal.timeout(10000) }
      );
      if (!resp.ok) return [];
      const data = await resp.json();
      return (data.data || []).map(c => ({
        id: c.id,
        key: `coze:${c.id}`,
        label: c.title || c.id,
        model: 'coze-bot',
        updatedAt: c.updated_at ? new Date(c.updated_at * 1000).getTime() : null,
      }));
    } catch { return []; }
  }

  async createSession(auth, opts = {}) {
    try {
      const resp = await fetch(`${this.baseUrl}/v1/conversation/create`, {
        method: 'POST',
        headers: this._headers(),
        body: JSON.stringify({ bot_id: this.botId, user_id: this.userId }),
        signal: AbortSignal.timeout(10000),
      });
      if (!resp.ok) return { id: `coze-new-${Date.now()}`, key: null, label: opts.label || 'New Chat', model: 'coze-bot' };
      const data = await resp.json();
      return { id: data.data?.id || `coze-${Date.now()}`, key: `coze:${data.data?.id}`, label: opts.label || 'New Chat', model: 'coze-bot' };
    } catch {
      return { id: `coze-new-${Date.now()}`, key: null, label: 'New Chat', model: 'coze-bot' };
    }
  }

  async chat(sessionKey, message, auth, opts = {}) {
    const conversationId = sessionKey?.replace('coze:', '') || undefined;
    try {
      const body = {
        bot_id: this.botId,
        user_id: this.userId,
        stream: false,
        auto_save_history: true,
        additional_messages: [{ role: 'user', content: message, content_type: 'text' }],
      };
      if (conversationId) body.conversation_id = conversationId;

      const resp = await fetch(`${this.baseUrl}/v3/chat`, {
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
      const reply = data.data?.content || data.messages?.find(m => m.role === 'assistant')?.content || '';
      return { ok: true, reply, conversationId: data.data?.conversation_id, chatId: data.data?.id };
    } catch (e) {
      return { ok: false, error: e.message };
    }
  }

  async *chatStream(sessionKey, message, auth, opts = {}) {
    const conversationId = sessionKey?.replace('coze:', '') || undefined;
    try {
      const body = {
        bot_id: this.botId,
        user_id: this.userId,
        stream: true,
        auto_save_history: true,
        additional_messages: [{ role: 'user', content: message, content_type: 'text' }],
      };
      if (conversationId) body.conversation_id = conversationId;

      const resp = await fetch(`${this.baseUrl}/v3/chat`, {
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
          if (!line.startsWith('event:') && !line.startsWith('data:')) continue;
          if (line.startsWith('data:')) {
            try {
              const data = JSON.parse(line.slice(5).trim());
              if (data.type === 'answer' && data.content) {
                yield { type: 'delta', content: data.content };
              } else if (data.type === 'done' || data.event === 'done') {
                yield { type: 'done', conversationId: data.conversation_id };
              } else if (data.type === 'error') {
                yield { type: 'error', error: data.msg || data.message || 'Coze error' };
              }
            } catch {}
          }
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
