/// Smoke test: real HermesClient -> running agenthub plugin.
///
/// Requires:
///   * The plugin running on 127.0.0.1:18790. Easiest way to start it:
///       python plugin/run_dev.py
///   * ~/.hermes/agenthub.json present (auto-created by the plugin on
///     first run).
///
/// Skipped silently if neither condition is met.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:agenthub/clients/hermes_client.dart';
import 'package:agenthub/models/agent_model.dart';
import 'package:agenthub/protocol/hub_protocol.dart';

const _host = '127.0.0.1';
const _port = 18790;

Future<String?> _loadToken() async {
  final home = Platform.environment['HOME'] ?? '/home/leon';
  final f = File('$home/.hermes/agenthub.json');
  if (!await f.exists()) return null;
  final raw = await f.readAsString();
  try {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return m['token'] as String?;
  } catch (_) {
    return null;
  }
}

Future<bool> _serverUp(String token) async {
  try {
    final socket =
        await Socket.connect(_host, _port, timeout: const Duration(seconds: 1));
    socket.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  late HermesClient client;
  late AgentInstance agent;
  late String token;
  bool runnable = false;

  setUpAll(() async {
    final t = await _loadToken();
    if (t == null) {
      // ignore: avoid_print
      print('SKIP: no token at ~/.hermes/agenthub.json');
      return;
    }
    token = t;
    if (!await _serverUp(token)) {
      // ignore: avoid_print
      print('SKIP: no plugin server at $_host:$_port');
      return;
    }
    runnable = true;
    agent = AgentInstance(
      id: 'test',
      name: 'Hermes-test',
      endpoint: AgentEndpoint(host: _host, port: _port, token: token),
    );
    client = HermesClient(agent);
  });

  test('ping /health', () async {
    if (!runnable) return;
    expect(await client.ping(), isTrue);
  });

  test('listSessions returns at least one entry from state.db', () async {
    if (!runnable) return;
    final sessions = await client.listSessions(limit: 5);
    expect(sessions, isNotEmpty);
    expect(sessions.first.id, isNotEmpty);
    expect(sessions.first.startedAt, isA<DateTime>());
  });

  test('getMessages of newest session returns parsed messages', () async {
    if (!runnable) return;
    final sessions = await client.listSessions(limit: 1);
    final msgs = await client.getMessages(sessions.first.id, limit: 5);
    expect(msgs, isNotEmpty);
    final first = msgs.first;
    expect(first.role, isIn(const ['user', 'assistant', 'tool', 'system']));
    expect(first.timestamp, isA<DateTime>());
  });

  test('sendChat round-trips a short message', () async {
    if (!runnable) return;
    final reply = await client.sendChat(content: 'Reply with the literal string PONG only');
    expect(reply.role, equals('assistant'));
    expect(reply.content, isNotNull);
    expect(reply.content!.trim().isNotEmpty, isTrue);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('capabilities returns hermes_home', () async {
    if (!runnable) return;
    final caps = await client.capabilities();
    expect(caps['hermes_home'], isNotNull);
  });

  test('AgentEndpoint.tryParsePairUri parses a real pair URI', () {
    final uri = 'agenthub://pair?host=192.168.50.239&port=18790&token=abc123xyz';
    final ep = AgentEndpoint.tryParsePairUri(uri);
    expect(ep, isNotNull);
    expect(ep!.host, equals('192.168.50.239'));
    expect(ep.port, equals(18790));
    expect(ep.token, equals('abc123xyz'));
  });

  test('AgentEndpoint.tryParsePairUri rejects non-agenthub URIs', () {
    expect(AgentEndpoint.tryParsePairUri('http://example.com'), isNull);
    expect(AgentEndpoint.tryParsePairUri('agenthub://other?host=x'), isNull);
    expect(AgentEndpoint.tryParsePairUri('garbage'), isNull);
  });
}
