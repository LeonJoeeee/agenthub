/// 添加Agent界面
library;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:uuid/uuid.dart';
import 'package:dio/dio.dart';
import '../models/agent_model.dart';

class AddAgentScreen extends StatefulWidget {
  const AddAgentScreen({super.key});

  @override
  State<AddAgentScreen> createState() => _AddAgentScreenState();
}

class _AddAgentScreenState extends State<AddAgentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();
  
  String _platform = 'openclaw';
  bool _isScanning = false;
  bool _isConnecting = false;
  String _statusMessage = '';

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _tokenController.dispose();
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
            tooltip: 'Scan QR Code',
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

          TextFormField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'Agent URL',
              hintText: 'https://your-server.com',
              prefixIcon: Icon(Icons.link),
              border: OutlineInputBorder(),
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

          DropdownButtonFormField<String>(
            value: _platform,
            decoration: const InputDecoration(
              labelText: 'Platform',
              prefixIcon: Icon(Icons.category_outlined),
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'openclaw', child: Text('OpenClaw')),
              DropdownMenuItem(value: 'dify', child: Text('Dify')),
              DropdownMenuItem(value: 'other', child: Text('Other')),
            ],
            onChanged: (v) => setState(() => _platform = v ?? 'openclaw'),
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: _tokenController,
            decoration: const InputDecoration(
              labelText: 'Auth Token (optional)',
              hintText: 'Leave empty for auto pairing',
              prefixIcon: Icon(Icons.key),
              border: OutlineInputBorder(),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 24),

          // Status message
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
                : const Icon(Icons.add_link),
            label: Text(_isConnecting ? 'Connecting...' : 'Connect Agent'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          const SizedBox(height: 16),

          Text(
            'Tip: Enter the AgentHub Server URL. The app will auto-pair and get a token.',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() { 
      _isConnecting = true; 
      _statusMessage = '🔄 Checking server...';
    });
    
    final baseUrl = _urlController.text.trim().replaceAll(RegExp(r'/+$'), '');
    final dio = Dio(BaseOptions(
      baseUrl: '$baseUrl/hub',
      connectTimeout: const Duration(seconds: 10),
    ));
    
    try {
      // Step 1: Check server status
      final statusResp = await dio.get('/status');
      if (statusResp.statusCode != 200) {
        throw Exception('Server returned ${statusResp.statusCode}');
      }
      final status = statusResp.data;
      setState(() { _statusMessage = '✅ Server online (${status['model'] ?? 'unknown'}, ${status['activeSessions'] ?? 0} sessions)'; });

      // Step 2: If user provided a token, verify it works
      final userToken = _tokenController.text.trim();
      if (userToken.isNotEmpty) {
        // Verify token by fetching sessions
        try {
          await Dio(BaseOptions(
            baseUrl: '$baseUrl/hub',
            headers: {'Authorization': 'Bearer $userToken'},
          )).get('/sessions');
          setState(() { _statusMessage = '✅ Token verified!'; });
        } catch (e) {
          setState(() { _statusMessage = '❌ Token invalid, auto-pairing...'; });
          // Fall through to auto-pair
        }
        
        if (_statusMessage.startsWith('✅ Token verified')) {
          // Token works, create agent
          final agent = AgentInstance(
            id: const Uuid().v4(),
            name: _nameController.text.trim(),
            baseUrl: baseUrl,
            authToken: userToken,
            platform: _platform,
            connected: true,
            model: status['model'],
          );
          if (mounted) Navigator.pop(context, agent);
          return;
        }
      }

      // Step 3: Auto-pair with server
      setState(() { _statusMessage = '🔄 Pairing device...'; });
      
      final pairResp = await dio.post('/pair', data: {
        'device_public_key': 'app-${const Uuid().v4()}',
        'device_name': _nameController.text.trim(),
        'device_type': 'android',
        'challenge': const Uuid().v4().toString(),
      });
      
      final pairData = pairResp.data;
      if (pairData['success'] != true) {
        throw Exception('Pairing failed: ${pairData['error'] ?? 'unknown'}');
      }
      
      final token = pairData['token'] as String;
      setState(() { _statusMessage = '✅ Paired! Token: ${token.substring(0, 8)}...'; });

      // Step 4: Verify we can fetch sessions
      setState(() { _statusMessage = '🔄 Loading sessions...'; });
      
      final sessionsResp = await Dio(BaseOptions(
        baseUrl: '$baseUrl/hub',
        headers: {'Authorization': 'Bearer $token'},
      )).get('/sessions');
      
      final sessionCount = (sessionsResp.data as List).length;
      setState(() { _statusMessage = '✅ Connected! $sessionCount sessions found.'; });

      // Create the agent instance with the real token
      final agent = AgentInstance(
        id: const Uuid().v4(),
        name: _nameController.text.trim(),
        baseUrl: baseUrl,
        authToken: token,
        platform: _platform,
        connected: true,
        model: status['model'],
      );
      
      // Small delay to show success message
      await Future.delayed(const Duration(milliseconds: 500));
      
      if (mounted) {
        Navigator.pop(context, agent);
      }
      
    } catch (e) {
      setState(() { 
        _statusMessage = '❌ ${e.toString().replaceAll('Exception: ', '').substring(0, (e.toString().length > 100) ? 100 : e.toString().length)}';
        _isConnecting = false;
      });
    }
  }
}
