/// 添加Agent界面 — 支持16个平台
library;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:uuid/uuid.dart';
import 'package:dio/dio.dart';
import '../models/agent_model.dart';
import '../models/platforms.dart';

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
  final _botIdController = TextEditingController();
  final _flowIdController = TextEditingController();
  final _appIdController = TextEditingController();
  
  PlatformInfo _platform = PLATFORMS.first; // Default: OpenAI Compatible
  bool _isScanning = false;
  bool _isConnecting = false;
  String _statusMessage = '';
  String _selectedCategory = 'All';

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _botIdController.dispose();
    _flowIdController.dispose();
    _appIdController.dispose();
    super.dispose();
  }

  List<PlatformInfo> get _filteredPlatforms {
    if (_selectedCategory == 'All') return PLATFORMS;
    return PLATFORMS.where((p) => p.category == _selectedCategory).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Agent')),
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
              final pid = uri.queryParameters['platform'];
              if (pid != null) {
                final match = PLATFORMS.where((p) => p.id == pid);
                if (match.isNotEmpty) setState(() { _platform = match.first; _applyDefaults(); });
              }
              _apiKeyController.text = uri.queryParameters['apiKey'] ?? '';
              _modelController.text = uri.queryParameters['model'] ?? '';
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
          // Category filter
          Text('Category', style: TextStyle(fontSize: 12, color: Colors.grey[400])),
          const SizedBox(height: 6),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: ['All', 'API', 'Platform', 'Local', 'Builder', 'Automation', 'Agent'].map((c) =>
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(c, style: const TextStyle(fontSize: 12)),
                    selected: _selectedCategory == c,
                    onSelected: (_) => setState(() => _selectedCategory = c),
                  ),
                ),
              ).toList(),
            ),
          ),
          const SizedBox(height: 12),

          // Platform selector
          Text('Platform', style: TextStyle(fontSize: 12, color: Colors.grey[400])),
          const SizedBox(height: 6),
          SizedBox(
            height: 160,
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4, mainAxisSpacing: 6, crossAxisSpacing: 6, childAspectRatio: 2.2,
              ),
              itemCount: _filteredPlatforms.length,
              itemBuilder: (_, i) {
                final p = _filteredPlatforms[i];
                return ChoiceChip(
                  avatar: Icon(p.icon, size: 14),
                  label: Text(p.name, style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis),
                  selected: _platform.id == p.id,
                  onSelected: (_) => setState(() { _platform = p; _applyDefaults(); }),
                );
              },
            ),
          ),
          Text(_platform.description, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          const SizedBox(height: 16),

          // Name
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Name', hintText: 'e.g. My Ollama, Work Dify',
              prefixIcon: Icon(Icons.label_outline), border: OutlineInputBorder(),
            ),
            validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
          ),
          const SizedBox(height: 12),

          // URL
          TextFormField(
            controller: _urlController,
            decoration: InputDecoration(
              labelText: _platform.id == 'openclaw' ? 'AgentHub Server URL' : 'API Base URL',
              hintText: _platform.defaultUrl ?? 'https://...',
              prefixIcon: const Icon(Icons.link), border: const OutlineInputBorder(),
            ),
            validator: (v) {
              if (v?.trim().isEmpty == true) return 'Required';
              if (!v!.startsWith('http://') && !v.startsWith('https://')) return 'Must start with http(s)://';
              return null;
            },
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),

          // API Key
          if (_platform.needsApiKey)
            TextFormField(
              controller: _apiKeyController,
              decoration: InputDecoration(
                labelText: 'API Key',
                hintText: _platform.id == 'dify' ? 'app-xxx' : _platform.id == 'coze' ? 'pat-xxx' : 'sk-xxx',
                prefixIcon: const Icon(Icons.key), border: const OutlineInputBorder(),
              ),
              obscureText: true,
            ),
          if (_platform.needsApiKey) const SizedBox(height: 12),

          // Bot ID (Coze)
          if (_platform.needsBotId)
            TextFormField(
              controller: _botIdController,
              decoration: const InputDecoration(
                labelText: 'Bot ID', hintText: 'Your Coze Bot ID',
                prefixIcon: Icon(Icons.smart_toy), border: OutlineInputBorder(),
              ),
            ),
          if (_platform.needsBotId) const SizedBox(height: 12),

          // Flow ID (Flowise/Langflow)
          if (_platform.needsFlowId)
            TextFormField(
              controller: _flowIdController,
              decoration: InputDecoration(
                labelText: 'Flow/Chatflow ID',
                hintText: _platform.id == 'langflow' ? 'Langflow Flow ID' : 'Flowise Chatflow ID',
                prefixIcon: const Icon(Icons.account_tree), border: const OutlineInputBorder(),
              ),
            ),
          if (_platform.needsFlowId) const SizedBox(height: 12),

          // App ID (MaxKB)
          if (_platform.needsAppId)
            TextFormField(
              controller: _appIdController,
              decoration: const InputDecoration(
                labelText: 'Application ID', hintText: 'MaxKB App ID',
                prefixIcon: Icon(Icons.apps), border: OutlineInputBorder(),
              ),
            ),
          if (_platform.needsAppId) const SizedBox(height: 12),

          // Model
          if (_platform.id != 'openclaw')
            TextFormField(
              controller: _modelController,
              decoration: InputDecoration(
                labelText: 'Model', hintText: _platform.defaultModel ?? 'model-name',
                prefixIcon: const Icon(Icons.psychology), border: const OutlineInputBorder(),
              ),
            ),
          if (_platform.id != 'openclaw') const SizedBox(height: 16),

          // Status
          if (_statusMessage.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: _statusMessage.startsWith('❌') ? Colors.red.withValues(alpha: 0.1) : Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_statusMessage, style: const TextStyle(fontSize: 13)),
            ),

          FilledButton.icon(
            onPressed: _isConnecting ? null : _connect,
            icon: _isConnecting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Icon(_platform.icon),
            label: Text(_isConnecting ? 'Connecting...' : 'Connect'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
        ],
      ),
    );
  }

  void _applyDefaults() {
    if (_platform.defaultUrl != null) _urlController.text = _platform.defaultUrl!;
    if (_platform.defaultModel != null) _modelController.text = _platform.defaultModel!;
    if (_nameController.text.isEmpty) _nameController.text = _platform.name;
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isConnecting = true; _statusMessage = '🔄 Connecting...'; });

    final baseUrl = _urlController.text.trim().replaceAll(RegExp(r'/+$'), '');
    
    try {
      if (_platform.id == 'openclaw') {
        // OpenClaw: through AgentHub Server
        final dio = Dio(BaseOptions(baseUrl: '$baseUrl/hub', connectTimeout: const Duration(seconds: 10)));
        final statusResp = await dio.get('/status');
        setState(() { _statusMessage = '✅ Server online'; });

        final pairResp = await dio.post('/pair', data: {
          'device_public_key': 'app-${const Uuid().v4()}',
          'device_name': _nameController.text.trim(),
          'device_type': 'android',
          'challenge': const Uuid().v4().toString(),
        });
        if (pairResp.data['success'] != true) throw Exception('Pairing failed');
        final token = pairResp.data['token'] as String;

        setState(() { _statusMessage = '✅ Connected!'; });
        await Future.delayed(const Duration(milliseconds: 300));

        final agent = AgentInstance(
          id: const Uuid().v4(), name: _nameController.text.trim(),
          baseUrl: baseUrl, authToken: token, platform: _platform.id, connected: true,
          model: statusResp.data['model'],
        );
        if (mounted) Navigator.pop(context, agent);
      } else {
        // Other platforms: register on AgentHub Server
        final dio = Dio(BaseOptions(baseUrl: '$baseUrl/hub', connectTimeout: const Duration(seconds: 10)));
        
        final pairResp = await dio.post('/pair', data: {
          'device_public_key': 'app-${const Uuid().v4()}',
          'device_name': _nameController.text.trim(),
          'device_type': 'android',
          'challenge': const Uuid().v4().toString(),
        });
        if (pairResp.data['success'] != true) throw Exception('Pairing failed');
        final token = pairResp.data['token'] as String;

        final agentData = {
          'platform': _platform.id,
          'name': _nameController.text.trim(),
          'baseUrl': baseUrl,
          if (_apiKeyController.text.trim().isNotEmpty) 'apiKey': _apiKeyController.text.trim(),
          if (_modelController.text.trim().isNotEmpty) 'model': _modelController.text.trim(),
          if (_botIdController.text.trim().isNotEmpty) 'botId': _botIdController.text.trim(),
          if (_flowIdController.text.trim().isNotEmpty) 'flowId': _flowIdController.text.trim(),
          if (_appIdController.text.trim().isNotEmpty) 'appId': _appIdController.text.trim(),
        };

        final registerResp = await Dio(BaseOptions(
          baseUrl: '$baseUrl/hub',
          headers: {'Authorization': 'Bearer $token'},
        )).post('/agents', data: agentData);

        final r = registerResp.data;
        setState(() { _statusMessage = '✅ ${_platform.name} registered!'; });
        await Future.delayed(const Duration(milliseconds: 300));

        final agent = AgentInstance(
          id: const Uuid().v4(), name: _nameController.text.trim(),
          baseUrl: baseUrl, authToken: token, platform: _platform.id,
          connected: r['online'] ?? false, model: _modelController.text.trim().isNotEmpty ? _modelController.text.trim() : r['model'],
        );
        if (mounted) Navigator.pop(context, agent);
      }
    } catch (e) {
      setState(() { _statusMessage = '❌ ${e.toString().replaceAll('Exception: ', '')}'; _isConnecting = false; });
    }
  }
}
