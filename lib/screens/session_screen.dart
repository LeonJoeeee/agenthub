/// Session列表界面 — 显示某个Agent的所有Session
library;

import 'package:flutter/material.dart';
import '../models/agent_model.dart';
import '../models/chat_model.dart';
import '../services/agent_connection.dart';
import '../protocol/hub_protocol.dart';
import 'chat_screen.dart';

class SessionScreen extends StatefulWidget {
  final AgentInstance agent;
  final AgentConnection connection;

  const SessionScreen({super.key, required this.agent, required this.connection});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  List<HubSession> _sessions = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() { _loading = true; _error = null; });
    
    if (!widget.connection.isConnected) {
      await widget.connection.connect();
    }
    
    final sessions = await widget.connection.fetchSessions();
    if (mounted) {
      setState(() {
        _sessions = sessions;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.agent.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSessions,
          ),
        ],
      ),
      body: _loading 
        ? const Center(child: CircularProgressIndicator())
        : _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
          : _sessions.isEmpty
            ? Center(child: Text('No sessions', style: TextStyle(color: Colors.grey[400])))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _sessions.length,
                itemBuilder: (context, index) => _buildSessionCard(_sessions[index]),
              ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createNewSession,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildSessionCard(HubSession session) {
    final updatedAt = session.updatedAt != null 
      ? DateTime.fromMillisecondsSinceEpoch(session.updatedAt!)
      : null;
    final timeStr = updatedAt != null 
      ? '${updatedAt.month}/${updatedAt.day} ${updatedAt.hour}:${updatedAt.minute.toString().padLeft(2, '0')}'
      : '';
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
          child: const Icon(Icons.chat_bubble_outline, size: 20),
        ),
        title: Text(
          session.label ?? session.id,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            if (session.model != null) ...[
              Text(session.model!, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              const SizedBox(width: 8),
            ],
            Text(timeStr, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _openChat(session),
      ),
    );
  }

  void _openChat(HubSession session) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatScreenWrapper(
        agent: widget.agent,
        session: ChatSession(
          id: session.id,
          agentId: widget.agent.id,
          key: session.key,
          label: session.label,
          model: session.model,
        ),
        connection: widget.connection,
      )),
    );
  }

  Future<void> _createNewSession() async {
    final session = await widget.connection.createSession(
      label: 'New Chat ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
    );
    if (session != null && mounted) {
      _openChat(session);
    }
  }
}
