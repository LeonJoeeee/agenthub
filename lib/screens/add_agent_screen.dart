/// Add agent — scan QR or paste pairing URL.
library;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:uuid/uuid.dart';

import '../clients/hermes_client.dart';
import '../models/agent_model.dart';
import '../protocol/hub_protocol.dart';

class AddAgentScreen extends StatefulWidget {
  const AddAgentScreen({super.key});

  @override
  State<AddAgentScreen> createState() => _AddAgentScreenState();
}

class _AddAgentScreenState extends State<AddAgentScreen> {
  final _scanner = MobileScannerController();
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController(text: 'Hermes');
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '18790');
  final _tokenCtrl = TextEditingController();

  bool _scanning = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _scanner.dispose();
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (!_scanning) return;
    final code = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
    if (code == null) return;
    final endpoint = AgentEndpoint.tryParsePairUri(code);
    if (endpoint == null) {
      setState(() => _error = 'Not an AgentHub QR — got: ${_truncate(code)}');
      return;
    }
    setState(() {
      _scanning = false;
      _error = null;
      _hostCtrl.text = endpoint.host;
      _portCtrl.text = endpoint.port.toString();
      _tokenCtrl.text = endpoint.token;
    });
    _scanner.stop();
  }

  String _truncate(String s) =>
      s.length <= 60 ? s : '${s.substring(0, 60)}…';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add agent'),
        actions: [
          IconButton(
            icon: Icon(_scanning ? Icons.edit : Icons.qr_code_scanner),
            tooltip: _scanning ? 'Manual entry' : 'Scan again',
            onPressed: () {
              setState(() => _scanning = !_scanning);
              if (_scanning) {
                _scanner.start();
              } else {
                _scanner.stop();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_scanning)
            SizedBox(
              height: 280,
              child: Stack(
                children: [
                  MobileScanner(controller: _scanner, onDetect: _onDetect),
                  Center(
                    child: Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.greenAccent, width: 2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(child: _buildForm()),
        ],
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
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Name',
              prefixIcon: Icon(Icons.label_outline),
              border: OutlineInputBorder(),
            ),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _hostCtrl,
            decoration: const InputDecoration(
              labelText: 'Host (LAN IP or domain)',
              hintText: '192.168.1.10',
              prefixIcon: Icon(Icons.dns_outlined),
              border: OutlineInputBorder(),
            ),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _portCtrl,
            decoration: const InputDecoration(
              labelText: 'Port',
              hintText: '18790',
              prefixIcon: Icon(Icons.numbers),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            validator: (v) {
              final n = int.tryParse((v ?? '').trim());
              return (n == null || n <= 0 || n > 65535) ? 'Invalid port' : null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _tokenCtrl,
            decoration: const InputDecoration(
              labelText: 'Token',
              hintText: 'From the QR or ~/.hermes/agenthub.json',
              prefixIcon: Icon(Icons.key),
              border: OutlineInputBorder(),
            ),
            obscureText: true,
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Required' : null,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _connect,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.link),
            label: Text(_busy ? 'Verifying…' : 'Verify & Add'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _connect() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final endpoint = AgentEndpoint(
      host: _hostCtrl.text.trim(),
      port: int.parse(_portCtrl.text.trim()),
      token: _tokenCtrl.text.trim(),
    );
    final agent = AgentInstance(
      id: const Uuid().v4(),
      name: _nameCtrl.text.trim(),
      endpoint: endpoint,
    );
    final client = HermesClient(agent);
    try {
      final ok = await client.ping();
      if (!ok) {
        throw HermesApiException('Plugin not reachable at ${endpoint.baseUrl}');
      }
      // Best-effort capabilities fetch to populate the model field
      try {
        final caps = await client.capabilities();
        final model = caps['model'];
        if (model is Map && model['default'] is String) {
          agent.model = model['default'] as String;
        } else if (model is String) {
          agent.model = model;
        }
      } catch (_) {}
      agent.online = true;
      if (mounted) Navigator.pop(context, agent);
    } on HermesApiException catch (e) {
      setState(() => _error = e.toString());
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
