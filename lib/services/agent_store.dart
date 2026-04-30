/// Local persistence for the user's bound agents.
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/agent_model.dart';

class AgentStore extends ChangeNotifier {
  final List<AgentInstance> _agents = [];
  List<AgentInstance> get agents => List.unmodifiable(_agents);

  static const _key = 'agenthub_agents_v2';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    _agents.clear();
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        for (final e in list) {
          _agents.add(AgentInstance.fromJson(e as Map<String, dynamic>));
        }
      } catch (_) {
        // corrupt — drop and start fresh
      }
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(_agents.map((a) => a.toJson()).toList()),
    );
  }

  Future<void> add(AgentInstance agent) async {
    _agents.add(agent);
    await _persist();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _agents.removeWhere((a) => a.id == id);
    await _persist();
    notifyListeners();
  }

  Future<void> update(AgentInstance agent) async {
    final i = _agents.indexWhere((a) => a.id == agent.id);
    if (i < 0) return;
    _agents[i] = agent;
    await _persist();
    notifyListeners();
  }

  AgentInstance? byId(String id) {
    for (final a in _agents) {
      if (a.id == id) return a;
    }
    return null;
  }
}
