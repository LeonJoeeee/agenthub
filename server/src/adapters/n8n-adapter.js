/**
 * Agent Platform Adapter — n8n 适配器
 * 
 * n8n是流行的workflow自动化平台，支持AI Agent节点
 * 通过Webhook触发n8n workflow，实现与Agent的交互
 */

export class N8nAdapter {
  constructor(config) {
    this.baseUrl = config.baseUrl;          // e.g. http://localhost:5678
    this.apiKey = config.apiKey;            // n8n API key
    this.webhookPath = config.webhookPath;  // Webhook path e.g. /webhook/agent-chat
    this.workflowId = config.workflowId;    // Optional: specific workflow
    this.platform = 'n8n';
    this.name = config.name || 'n8n Workflow';
  }

  async getStatus() {
    try {
      const resp = await fetch(`${this.baseUrl}/api/v1/workflows`, {
        headers: this._headers(),
        signal: AbortSignal.timeout(5000),
      });
      if (!resp.ok) return { online: false, error: `HTTP ${resp.status}` };
      const data = await resp.json();
      return { online: true, platform: 'n8n', model: 'n8n-workflow', workflowCount: data.data?.length || 0 };
    } catch (e) {
      // Try webhook endpoint as fallback
      if (this.webhookPath) {
        return { online: true, platform: 'n8n', model: 'n8n-webhook' };
      }
      return { online: false, error: e.message };
    }
  }

  async listSessions(auth) {
    // n8n doesn't have native session management — sessions managed client-side
    return [];
  }

  async createSession(auth, opts = {}) {
    return {
      id: `n8n-${Date.now()}`,
      key: `n8n:${Date.now()}`,
      label: opts.label || 'New Workflow Run',
      model: 'n8n-workflow',
    };
  }

  async chat(sessionKey, message, auth, opts = {}) {
    const webhookUrl = this.webhookPath
      ? `${this.baseUrl}${this.webhookPath}`
      : `${this.baseUrl}/webhook/${this.workflowId || 'agent-chat'}`;

    try {
      const resp = await fetch(webhookUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', ...this._webhookHeaders() },
        body: JSON.stringify({
          message,
          session_id: sessionKey,
          user_id: auth || 'agenthub-user',
          ...opts.extraData,
        }),
        signal: AbortSignal.timeout((opts.timeout || 120) * 1000),
      });

      if (!resp.ok) {
        const err = await resp.text();
        return { ok: false, error: `HTTP ${resp.status}: ${err.substring(0, 200)}` };
      }

      const data = await resp.json();
      const reply = data.reply || data.message || data.output || data.response || 
        (typeof data === 'string' ? data : JSON.stringify(data));
      return { ok: true, reply, data };
    } catch (e) {
      return { ok: false, error: e.message };
    }
  }

  /// n8n webhooks don't support SSE streaming natively
  async *chatStream(sessionKey, message, auth, opts = {}) {
    const result = await this.chat(sessionKey, message, auth, opts);
    if (result.ok && result.reply) {
      yield { type: 'delta', content: result.reply };
      yield { type: 'done' };
    } else {
      yield { type: 'error', error: result.error || 'Workflow failed' };
    }
  }

  _headers() {
    const h = { 'Content-Type': 'application/json' };
    if (this.apiKey) h['X-N8N-API-KEY'] = this.apiKey;
    return h;
  }

  _webhookHeaders() {
    // Webhooks may use different auth
    const h = {};
    if (this.apiKey) h['Authorization'] = `Bearer ${this.apiKey}`;
    return h;
  }
}
