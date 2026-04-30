/**
 * Adapter Factory — creates the right adapter based on platform config
 * 
 * Supported platforms (by market usage, high to low):
 * 1. OpenAI Compatible — covers ChatGPT API, Ollama, vLLM, LM Studio, etc.
 * 2. Dify — most popular open-source agent platform
 * 3. Coze (扣子) — ByteDance's AI platform, massive China user base
 * 4. n8n — workflow automation with AI
 * 5. Flowise — visual LLM builder
 * 6. Langflow — visual LLM builder
 * 7. Ollama — popular local LLM runner
 * 8. FastGPT — popular in China
 * 9. MaxKB — knowledge base Q&A platform
 * 10. Claude/Anthropic — growing fast
 * 11. OpenClaw — our native platform
 */

import { OpenClawAdapter } from './openclaw-adapter.js';
import { OpenAIAdapter } from './openai-adapter.js';
import { DifyAdapter } from './dify-adapter.js';
import { CozeAdapter } from './coze-adapter.js';
import { N8nAdapter } from './n8n-adapter.js';
import { FlowiseAdapter } from './flowise-adapter.js';
import { MaxKBAdapter } from './maxkb-adapter.js';
import { ClaudeAdapter } from './claude-adapter.js';

const ADAPTERS = {
  openclaw: OpenClawAdapter,
  dify: DifyAdapter,
  coze: CozeAdapter,
  n8n: N8nAdapter,
  flowise: FlowiseAdapter,
  langflow: FlowiseAdapter,  // Same adapter, different config
  'openai-compatible': OpenAIAdapter,
  ollama: OpenAIAdapter,
  fastgpt: OpenAIAdapter,
  vllm: OpenAIAdapter,
  lmstudio: OpenAIAdapter,
  localai: OpenAIAdapter,
  jan: OpenAIAdapter,
  gpt4all: OpenAIAdapter,
  maxkb: MaxKBAdapter,
  claude: ClaudeAdapter,
};

export function createAdapter(config) {
  const platform = (config.platform || 'openclaw').toLowerCase();
  const AdapterClass = ADAPTERS[platform] || OpenAIAdapter;
  
  // Platform-specific defaults
  if (platform === 'ollama') {
    config.baseUrl = config.baseUrl || 'http://localhost:11434/v1';
    config.model = config.model || 'llama3';
  } else if (platform === 'lmstudio') {
    config.baseUrl = config.baseUrl || 'http://localhost:1234/v1';
    config.model = config.model || 'default';
  } else if (platform === 'dify') {
    config.baseUrl = config.baseUrl || 'https://api.dify.ai/v1';
  } else if (platform === 'coze') {
    config.baseUrl = config.baseUrl || 'https://api.coze.cn';
  } else if (platform === 'n8n') {
    config.baseUrl = config.baseUrl || 'http://localhost:5678';
  } else if (platform === 'flowise') {
    config.baseUrl = config.baseUrl || 'http://localhost:3000';
  } else if (platform === 'langflow') {
    config.baseUrl = config.baseUrl || 'http://localhost:7860';
    config.platform = 'langflow';
  } else if (platform === 'maxkb') {
    config.baseUrl = config.baseUrl || 'http://localhost:8080';
  }

  return new AdapterClass(config);
}

export function listPlatforms() {
  return [
    { id: 'openclaw', name: 'OpenClaw', category: 'agent', description: 'OpenClaw Agent (CLI)' },
    { id: 'openai-compatible', name: 'OpenAI Compatible', category: 'api', description: 'Any /v1/chat/completions API' },
    { id: 'claude', name: 'Anthropic Claude', category: 'api', description: 'Claude API direct' },
    { id: 'dify', name: 'Dify', category: 'platform', description: 'Open-source agent platform' },
    { id: 'coze', name: 'Coze (扣子)', category: 'platform', description: 'ByteDance AI platform' },
    { id: 'ollama', name: 'Ollama', category: 'local', description: 'Local LLM runner' },
    { id: 'n8n', name: 'n8n', category: 'automation', description: 'Workflow automation + AI' },
    { id: 'flowise', name: 'Flowise', category: 'builder', description: 'Visual LLM builder' },
    { id: 'langflow', name: 'Langflow', category: 'builder', description: 'Visual LLM builder' },
    { id: 'fastgpt', name: 'FastGPT', category: 'platform', description: 'Open-source AI platform' },
    { id: 'maxkb', name: 'MaxKB', category: 'platform', description: 'Knowledge base Q&A' },
    { id: 'vllm', name: 'vLLM', category: 'local', description: 'High-performance LLM serving' },
    { id: 'lmstudio', name: 'LM Studio', category: 'local', description: 'Local LLM desktop app' },
    { id: 'localai', name: 'LocalAI', category: 'local', description: 'Self-hosted AI' },
    { id: 'jan', name: 'Jan', category: 'local', description: 'Local AI assistant' },
    { id: 'gpt4all', name: 'GPT4All', category: 'local', description: 'Local LLM runner' },
  ];
}
