/// Agent本地存储管理（简化版，使用SharedPreferences + JSON）
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/agent_model.dart';

class AgentStore extends ChangeNotifier {
  List<AgentInstance> _agents = [];
  List<AgentInstance> get agents => _agents;

  static const _key = 'agenthub_agents';

  /// 从本地存储加载
  Future<void> loadAgents() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_key);
    if (data != null) {
      final list = jsonDecode(data) as List;
      _agents = list.map((e) => AgentInstance.fromJson(e as Map<String, dynamic>)).toList();
      notifyListeners();
    }
  }

  /// 保存到本地
  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(_agents.map((a) => a.toJson()).toList());
    await prefs.setString(_key, data);
  }

  /// 添加新agent
  Future<void> addAgent(AgentInstance agent) async {
    _agents.add(agent);
    await _save();
    notifyListeners();
  }

  /// 更新agent
  Future<void> updateAgent(AgentInstance agent) async {
    final idx = _agents.indexWhere((a) => a.id == agent.id);
    if (idx >= 0) _agents[idx] = agent;
    await _save();
    notifyListeners();
  }

  /// 删除agent
  Future<void> removeAgent(String agentId) async {
    _agents.removeWhere((a) => a.id == agentId);
    await _save();
    notifyListeners();
  }
}
