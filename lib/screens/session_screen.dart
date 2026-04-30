/// Session list — for one configured agent.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../clients/hermes_client.dart';
import '../models/agent_model.dart';
import '../models/chat_model.dart';
import 'chat_screen.dart';

class SessionScreen extends StatefulWidget {
  final AgentInstance agent;
  const SessionScreen({super.key, required this.agent});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  late final HermesClient _client;
  Future<List<ChatSession>>? _future;

  @override
  void initState() {
    super.initState();
    _client = HermesClient(widget.agent);
    _refresh();
  }

  void _refresh() {
    setState(() {
      _future = _client.listSessions(limit: 50);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.agent.name, style: const TextStyle(fontSize: 16)),
            Text(
              widget.agent.endpoint.baseUrl,
              style: TextStyle(fontSize: 11, color: Colors.grey[400]),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: FutureBuilder<List<ChatSession>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _ErrorView(
              message: snap.error.toString(),
              onRetry: _refresh,
            );
          }
          final sessions = snap.data ?? const [];
          if (sessions.isEmpty) {
            return Center(
              child: Text('No sessions',
                  style: TextStyle(color: Colors.grey[400])),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: sessions.length,
              itemBuilder: (_, i) =>
                  _SessionTile(agent: widget.agent, session: sessions[i]),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newChat,
        icon: const Icon(Icons.chat),
        label: const Text('New chat'),
      ),
    );
  }

  void _newChat() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ChatScreen(agent: widget.agent, sessionId: null),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final AgentInstance agent;
  final ChatSession session;
  const _SessionTile({required this.agent, required this.session});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
          child: const Icon(Icons.chat_bubble_outline, size: 20),
        ),
        title: Text(
          session.displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${session.source ?? "?"} · ${session.messageCount} msgs · '
          '${DateFormat('MM/dd HH:mm').format(session.startedAt)}',
          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChatScreen(
                agent: agent,
                sessionId: session.id,
                sessionTitle: session.displayTitle,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[400]),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
