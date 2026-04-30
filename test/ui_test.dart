/// Widget-level UI tests for AgentHub.
///
/// All tests here are pure (no network) — they pump screens with mocked
/// SharedPreferences to verify rendering, validation, and navigation flow.
/// The data layer (HermesClient ↔ live plugin) is covered by
/// hermes_client_smoke_test.dart.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agenthub/models/agent_model.dart';
import 'package:agenthub/protocol/hub_protocol.dart';
import 'package:agenthub/screens/add_agent_screen.dart';
import 'package:agenthub/screens/home_screen.dart';
import 'package:agenthub/services/agent_store.dart';

Widget _wrap(Widget child) => ProviderScope(
      child: MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: child,
      ),
    );

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('HomeScreen renders empty state with "Scan to add" CTA',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_wrap(const HomeScreen()));
    await tester.pump(); // load() postFrameCallback
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('No agents yet'), findsOneWidget);
    expect(find.text('Scan to add'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('HomeScreen renders an agent card when store has one',
      (tester) async {
    final agent = AgentInstance(
      id: 'a1',
      name: 'Test Hermes',
      endpoint: const AgentEndpoint(
          host: '10.0.0.1', port: 18790, token: 'tok'),
      model: 'mimo-v2.5-pro',
    );
    SharedPreferences.setMockInitialValues({
      'agenthub_agents_v2': jsonEncode([agent.toJson()]),
    });

    await tester.pumpWidget(_wrap(const HomeScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Test Hermes'), findsOneWidget);
    expect(find.text('10.0.0.1:18790'), findsOneWidget);
    expect(find.text('Model: mimo-v2.5-pro'), findsOneWidget);
  });

  testWidgets('AddAgentScreen form validates required fields',
      (tester) async {
    await tester.pumpWidget(_wrap(const AddAgentScreen()));
    await tester.pump();
    // toggle to manual entry (camera not available in widget tests anyway)
    await tester.tap(find.byTooltip('Manual entry'));
    await tester.pump();

    final btn = find.text('Verify & Add');
    expect(btn, findsOneWidget);
    await tester.tap(btn);
    await tester.pump();
    expect(find.text('Required'), findsWidgets);
  });

  testWidgets('AgentEndpoint pair URI parser is exercised correctly',
      (_) async {
    final ok = AgentEndpoint.tryParsePairUri(
        'agenthub://pair?host=1.2.3.4&port=18790&token=abc');
    expect(ok, isNotNull);
    expect(ok!.host, '1.2.3.4');
    expect(ok.port, 18790);
    expect(ok.token, 'abc');

    expect(AgentEndpoint.tryParsePairUri('http://nope'), isNull);
    expect(AgentEndpoint.tryParsePairUri('agenthub://other'), isNull);
  });

  testWidgets('AgentStore add/remove round-trip', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AgentStore();
    await store.load();
    expect(store.agents, isEmpty);

    final a = AgentInstance(
      id: 'x',
      name: 'X',
      endpoint:
          const AgentEndpoint(host: 'h', port: 1, token: 't'),
    );
    await store.add(a);
    expect(store.agents, hasLength(1));
    expect(store.byId('x'), isNotNull);

    final store2 = AgentStore();
    await store2.load();
    expect(store2.agents, hasLength(1),
        reason: 'persisted across instances via SharedPreferences');

    await store.remove('x');
    expect(store.agents, isEmpty);
  });
}
