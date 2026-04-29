/**
 * Adapter Factory — creates the right adapter based on platform config
 */

import { OpenClawAdapter } from './openclaw-adapter.js';
import { OpenAIAdapter } from './openai-adapter.js';
import { DifyAdapter } from './dify-adapter.js';

const ADAPTERS = {
  openclaw: OpenClawAdapter,
  dify: DifyAdapter,
  'openai-compatible': OpenAIAdapter,
  ollama: OpenAIAdapter,
  fastgpt: OpenAIAdapter,
  vllm: OpenAIAdapter,
  lmstudio: OpenAIAdapter,
  localai: OpenAIAdapter,
};

export function createAdapter(config) {
  const platform = (config.platform || 'openclaw').toLowerCase();
  const AdapterClass = ADAPTERS[platform] || OpenAIAdapter; // Default to OpenAI compatible
  
  // Special defaults for known platforms
  if (platform === 'ollama') {
    config.baseUrl = config.baseUrl || 'http://localhost:11434/v1';
    config.model = config.model || 'llama3';
  } else if (platform === 'lmstudio') {
    config.baseUrl = config.baseUrl || 'http://localhost:1234/v1';
    config.model = config.model || 'default';
  } else if (platform === 'dify') {
    config.baseUrl = config.baseUrl || 'https://api.dify.ai/v1';
  }

  return new AdapterClass(config);
}

export function listPlatforms() {
  return Object.entries(ADAPTERS).map(([id, cls]) => ({
    id,
    name: id === 'openclaw' ? 'OpenClaw' 
      : id === 'dify' ? 'Dify'
      : id === 'openai-compatible' ? 'OpenAI Compatible'
      : id === 'ollama' ? 'Ollama'
      : id === 'fastgpt' ? 'FastGPT'
      : id === 'vllm' ? 'vLLM'
      : id === 'lmstudio' ? 'LM Studio'
      : id === 'localai' ? 'LocalAI'
      : id,
  }));
}
