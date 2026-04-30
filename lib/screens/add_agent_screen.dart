/// 添加Agent界面 — 支持多平台
library;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:uuid/uuid.dart';
import 'package:dio/dio.dart';
import '../models/agent_model.dart';

/// 支持的平台列表
const PLATFORMS = {
  'openclaw': PlatformInfo('OpenClaw', 'OpenClaw Agent (CLI)', Icons.smart_toy),
  'dify': PlatformInfo('Dify', 'Dify Cloud/Self-hosted', Icons.cloud),
  'ollama': PlatformInfo('Ollama', 'Local LLM (localhost:11434)', Icons.computer),
  'openai-compatible': PlatformInfo('OpenAI Compatible', 'vLLM, LM Studio, LocalAI...', Icons.api),
  'fastgpt': PlatformInfo('FastGPT', 'FastGPT Platform', Icons.bolt),
};

class PlatformInfo {
  final String name;
  final String description;
  final IconData icon;
  const PlatformInfo(this.name, this.description, this.icon);
}

class AddAgentScreen extends StatefulWidget {
  const AddAgentScreen({super.key});

  @override
  State<AddAgentScreen> createState() => _AddAgentScreenState();
}

class _AddAgentScreenState extends State<AddAgentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();
  
  String _platform = 'openclaw';
  bool _isScanning = false;
  bool _isConnecting = false;
  String _statusMessage = '';

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Agent'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => setState(() => _isScanning = !_isScanning),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isScanning) _buildQRScanner(),
          Expanded(child: _buildForm()),
        ],
      ),
    );
  }

  Widget _buildQRScanner() {
    return SizedBox(
      height: 250,
      child: MobileScanner(
        onDetect: (capture) {
          final barcode = capture.barcodes.firstOrNull;
          if (barcode != null && barcode.rawValue != null) {
            final data = barcode.rawValue!;
            if (data.startsWith('agenthub://')) {
              final uri = Uri.parse(data);
              _nameController.text = uri.queryParameters['name'] ?? '';
              _urlController.text = uri.queryParameters['url'] ?? '';
              if (uri.queryParameters['platform'] != null) {
                _platform = uri.queryParameters['platform']!;
              }
              if (uri.queryParameters['apiKey'] != null) {
                _apiKeyController.text = uri.queryParameters['apiKey']!;
              }
              if (uri.queryParameters['model'] != null) {
                _modelController.text = uri.queryParameters['model']!;
              }
              setState(() => _isScanning = false);
            } else if (data.startsWith('http')) {
              _urlController.text = data;
              setState(() => _isScanning = false);
            }
          }
        },
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Platform selector
          Text('Platform', style: TextStyle(fontSize: 12, color: Colors.grey[400])),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: PLATFORMS.entries.map((e) => ChoiceChip(
              avatar: Icon(e.value.icon, size: 16),
              label: Text(e.value.name),
              selected: _platform == e.key,
              onSelected: (_) => setState(() {
                _platform = e.key;
                _applyDefaults();
              }),
            )).toList(),
          ),
          
          if (PLATFORMS[_platform] != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(PLATFORMS[_platform]!.description, 
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ),
          
          const SizedBox(height: 20),
          
          // Agent Name
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Agent Name',
              hintText: 'e.g. My OpenClaw, Work Dify',
              prefixIcon: Icon(Icons.label_outline),
              border: OutlineInputBorder(),
            ),
            validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
          ),
          const SizedBox(height: 16),

          // Server URL / Agent URL
          TextFormField(
            controller: _urlController,
            decoration: InputDecoration(
              labelText: _platform == 'openclaw' ? 'AgentHub Server URL' : 'API Base URL',
              hintText: _platform == 'openclaw' 
                ? 'https://your-server.com' 
                : _platform == 'dify'
                  ? 'https://api.dify.ai/v1'
                  : _platform == 'ollama'
                    ? 'http://localhost:11434/v1'
                    : 'https://api.example.com/v1',
              prefixIcon: const Icon(Icons.link),
              border: const OutlineInputBorder(),
            ),
            validator: (v) {
              if (v?.trim().isEmpty == true) return 'Required';
              if (!v!.startsWith('http://') && !v.startsWith('https://')) {
                return 'Must start with http:// or https://';
              }
              return null;
            },
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 16),

          // API Key (for Dify and OpenAI-compatible)
          if (_platform != 'openclaw')
            TextFormField(
              controller: _apiKeyController,
              decoration: InputDecoration(
                labelText: 'API Key',
                hintText: _platform == 'dify' ? 'app-xxxxxxxx' : 'sk-xxxxxxxx',
                prefixIcon: const Icon(Icons.key),
                border: const OutlineInputBorder(),
              ),
              obscureText: true,
            ),
          if (_platform != 'openclaw') const SizedBox(height: 16),

          // Model name (for non-OpenClaw)
          if (_platform != 'openclaw')
            TextFormField(
              controller: _modelController,
              decoration: InputDecoration(
                labelText: 'Model Name',
                hintText: _platform == 'ollama' ? 'llama3' : _platform == 'dify' ? 'dify-app' : 'gpt-4',
                prefixIcon: const Icon(Icons.psychology),
                border: const OutlineInputBorder(),
              ),
            ),
          if (_platform != 'openclaw') const SizedBox(height: 24),

          // Status
          if (_statusMessage.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: _statusMessage.startsWith('❌') 
                  ? Colors.red.withValues(alpha: 0.1) 
                  : Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_statusMessage, style: const TextStyle(fontSize: 13)),
            ),

          FilledButton.icon(
            onPressed: _isConnecting ? null : _connect,
            icon: _isConnecting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Icon(PLATFORMS[_platform]?.icon ?? Icons.add_link),
            label: Text(_isConnecting ? 'Connecting...' : 'Connect Agent'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          ),
        ],
      ),
    );
  }

  void _applyDefaults() {
    if (_platform == 'ollama') {
      _urlController.text = 'http://localhost:11434/v1';
      _modelController.text = 'llama3';
      _nameController.text = _nameController.text.isEmpty ? 'Local Ollama' : _nameController.text;
    } else if (_platform == 'lmstudio') {
      _urlController.text = 'http://localhost:1234/v1';
    } else if (_platform == 'dify') {
      _urlController.text = 'https://api.dify.ai/v1';
      _modelController.text = 'dify-app';
      _nameController.text = _nameController.text.isEmpty ? 'My Dify App' : _nameController.text;
    } else if (_platform == 'openclaw') {
      _apiKeyController.clear();
      _modelController.clear();
    }
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() { _isConnecting = true; _statusMessage = '🔄 Connecting...'; });
    
    final baseUrl = _urlController.text.trim().replaceAll(RegExp(r'/+$'), '');
    final dio = Dio(BaseOptions(
      baseUrl: '$baseUrl/hub',
      connectTimeout: const Duration(seconds: 10),
    ));
    
    try {
      if (_platform == 'openclaw') {
        // OpenClaw: connect through AgentHub Server
        final statusResp = await dio.get('/status');
        final status = statusResp.data;
        setState(() { _statusMessage = '✅ Server online (${status['model'] ?? '?'})'; });

        // Auto-pair
        setState(() { _statusMessage = '🔄 Pairing...'; });
        final pairResp = await dio.post('/pair', data: {
          'device_public_key': 'app-${const Uuid().v4()}',
          'device_name': _nameController.text.trim(),
          'device_type': 'android',
          'challenge': const Uuid().v4().toString(),
        });
        
        if (pairResp.data['success'] != true) throw Exception('Pairing failed');
        final token = pairResp.data['token'] as String;
        
        // Also register this agent on the server side
        // (The server already has a default OpenClaw agent)
        
        setState(() { _statusMessage = '✅ Paired & connected!'; });
        await Future.delayed(const Duration(milliseconds: 500));

        final agent = AgentInstance(
          id: const Uuid().v4(),
          name: _nameController.text.trim(),
          baseUrl: baseUrl,
          authToken: token,
          platform: _platform,
          connected: true,
          model: status['model'],
        );
        if (mounted) Navigator.pop(context, agent);
        
      } else {
        // Non-OpenClaw: register on AgentHub Server
        setState(() { _statusMessage = '🔄 Registering agent...'; });
        
        // First pair with the server
        final pairResp = await dio.post('/pair', data: {
          'device_public_key': 'app-${const Uuid().v4()}',
          'device_name': _nameController.text.trim(),
          'device_type': 'android',
          'challenge': const Uuid().v4().toString(),
        });
        if (pairResp.data['success'] != true) throw Exception('Pairing failed');
        final token = pairResp.data['token'] as String;
        
        // Register the agent
        final registerResp = await Dio(BaseOptions(
          baseUrl: '$baseUrl/hub',
          headers: {'Authorization': 'Bearer $token'},
        )).post('/agents', data: {
          'platform': _platform,
          'name': _nameController.text.trim(),
          'baseUrl': _platform == 'dify' ? _urlController.text.trim() : _urlController.text.trim(),
          'apiKey': _apiKeyController.text.trim().isNotEmpty ? _apiKeyController.text.trim() : null,
          'model': _modelController.text.trim().isNotEmpty ? _modelController.text.trim() : null,
        });
        
        final agentData = registerResp.data;
        setState(() { _statusMessage = '✅ Agent registered! Platform: ${agentData['platform']}'; });
        await Future.delayed(const Duration(milliseconds: 500));

        final agent = AgentInstance(
          id: const Uuid().v4(),
          name: _nameController.text.trim(),
          baseUrl: baseUrl,
          authToken: token,
          platform: _platform,
          connected: agentData['online'] ?? false,
          model: _modelController.text.trim().isNotEmpty ? _modelController.text.trim() : agentData['model'],
        );
        if (mounted) Navigator.pop(context, agent);
      }
    } catch (e) {
      setState(() { 
        _statusMessage = '❌ ${e.toString().replaceAll('Exception: ', '')}';
        _isConnecting = false;
      });
    }
  }
}
