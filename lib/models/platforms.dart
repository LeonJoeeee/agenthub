/// 支持的平台列表
library;

import 'package:flutter/material.dart';

class PlatformInfo {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final String category;
  final String? defaultUrl;
  final String? defaultModel;
  final bool needsApiKey;
  final bool needsFlowId;
  final bool needsBotId;
  final bool needsAppId;

  const PlatformInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.category,
    this.defaultUrl,
    this.defaultModel,
    this.needsApiKey = false,
    this.needsFlowId = false,
    this.needsBotId = false,
    this.needsAppId = false,
  });
}

const PLATFORMS = <PlatformInfo>[
  // === API ===
  PlatformInfo(
    id: 'openai-compatible',
    name: 'OpenAI Compatible',
    description: 'Any /v1/chat/completions API',
    icon: Icons.api,
    category: 'API',
    defaultUrl: 'https://api.openai.com/v1',
    defaultModel: 'gpt-4',
    needsApiKey: true,
  ),
  PlatformInfo(
    id: 'claude',
    name: 'Anthropic Claude',
    description: 'Claude API direct',
    icon: Icons.auto_awesome,
    category: 'API',
    defaultModel: 'claude-sonnet-4-20250514',
    needsApiKey: true,
  ),

  // === Platform ===
  PlatformInfo(
    id: 'dify',
    name: 'Dify',
    description: 'Open-source agent platform (40k+ ⭐)',
    icon: Icons.cloud,
    category: 'Platform',
    defaultUrl: 'https://api.dify.ai/v1',
    defaultModel: 'dify-app',
    needsApiKey: true,
  ),
  PlatformInfo(
    id: 'coze',
    name: 'Coze (扣子)',
    description: 'ByteDance AI platform',
    icon: Icons.bolt,
    category: 'Platform',
    defaultUrl: 'https://api.coze.cn',
    needsApiKey: true,
    needsBotId: true,
  ),
  PlatformInfo(
    id: 'fastgpt',
    name: 'FastGPT',
    description: 'Open-source AI platform (20k+ ⭐)',
    icon: Icons.bolt,
    category: 'Platform',
    needsApiKey: true,
  ),
  PlatformInfo(
    id: 'maxkb',
    name: 'MaxKB',
    description: 'Knowledge base Q&A (15k+ ⭐)',
    icon: Icons.menu_book,
    category: 'Platform',
    defaultUrl: 'http://localhost:8080',
    needsApiKey: true,
    needsAppId: true,
  ),

  // === Local ===
  PlatformInfo(
    id: 'ollama',
    name: 'Ollama',
    description: 'Local LLM runner (130k+ ⭐)',
    icon: Icons.computer,
    category: 'Local',
    defaultUrl: 'http://localhost:11434/v1',
    defaultModel: 'llama3',
  ),
  PlatformInfo(
    id: 'vllm',
    name: 'vLLM',
    description: 'High-performance LLM serving',
    icon: Icons.speed,
    category: 'Local',
    defaultUrl: 'http://localhost:8000/v1',
    defaultModel: 'default',
  ),
  PlatformInfo(
    id: 'lmstudio',
    name: 'LM Studio',
    description: 'Local LLM desktop app',
    icon: Icons.laptop,
    category: 'Local',
    defaultUrl: 'http://localhost:1234/v1',
    defaultModel: 'default',
  ),
  PlatformInfo(
    id: 'localai',
    name: 'LocalAI',
    description: 'Self-hosted AI',
    icon: Icons.dns,
    category: 'Local',
    defaultUrl: 'http://localhost:8080/v1',
    defaultModel: 'default',
  ),
  PlatformInfo(
    id: 'jan',
    name: 'Jan',
    description: 'Local AI assistant',
    icon: Icons.home,
    category: 'Local',
    defaultUrl: 'http://localhost:1337/v1',
    defaultModel: 'default',
  ),
  PlatformInfo(
    id: 'gpt4all',
    name: 'GPT4All',
    description: 'Local LLM runner',
    icon: Icons.offline_bolt,
    category: 'Local',
    defaultUrl: 'http://localhost:4891/v1',
    defaultModel: 'default',
  ),

  // === Builder ===
  PlatformInfo(
    id: 'flowise',
    name: 'Flowise',
    description: 'Visual LLM builder (35k+ ⭐)',
    icon: Icons.account_tree,
    category: 'Builder',
    defaultUrl: 'http://localhost:3000',
    needsApiKey: true,
    needsFlowId: true,
  ),
  PlatformInfo(
    id: 'langflow',
    name: 'Langflow',
    description: 'Visual LLM builder (50k+ ⭐)',
    icon: Icons.hub,
    category: 'Builder',
    defaultUrl: 'http://localhost:7860',
    needsApiKey: true,
    needsFlowId: true,
  ),

  // === Automation ===
  PlatformInfo(
    id: 'n8n',
    name: 'n8n',
    description: 'Workflow automation + AI (50k+ ⭐)',
    icon: Icons.settings_suggest,
    category: 'Automation',
    defaultUrl: 'http://localhost:5678',
    needsApiKey: true,
  ),

  // === Agent ===
  PlatformInfo(
    id: 'openclaw',
    name: 'OpenClaw',
    description: 'OpenClaw Agent (CLI)',
    icon: Icons.smart_toy,
    category: 'Agent',
  ),
];
