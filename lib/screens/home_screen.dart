/// 主界面 — Agent列表 + Session列表
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/agent_model.dart';
import '../models/chat_model.dart';
import '../services/agent_store.dart';
import '../services/agent_connection.dart';
import '../protocol/hub_protocol.dart';
import 'add_agent_screen.dart';
import 'session_screen.dart';
import 'chat_screen.dart' show ChatScreenWrapper;

/// Agent列表Provider
final agentsProvider = ChangeNotifierProvider<AgentStore>((ref) => AgentStore());

/// 连接池Provider — 保存所有活跃的AgentConnection
final connectionsProvider = StateProvider<Map<String, AgentConnection>>((ref) => {});

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(agentsProvider).loadAgents();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          _AgentListTab(),
          _SessionListTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.smart_toy_outlined),
            selectedIcon: Icon(Icons.smart_toy),
            label: 'Agents',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Sessions',
          ),
        ],
      ),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton(
              onPressed: _navigateToAddAgent,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  void _navigateToAddAgent() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddAgentScreen()),
    );
    if (result != null && result is AgentInstance) {
      ref.read(agentsProvider).addAgent(result);
    }
  }
}

/// Agent列表Tab
class _AgentListTab extends ConsumerWidget {
  const _AgentListTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(agentsProvider);
    final agents = store.agents;

    if (agents.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.smart_toy_outlined, size: 80, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text('No agents yet', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.grey)),
            const SizedBox(height: 8),
            Text('Tap + to add your first agent', style: TextStyle(color: Colors.grey[500])),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: agents.length,
      itemBuilder: (context, index) {
        final agent = agents[index];
        return _AgentCard(agent: agent);
      },
    );
  }
}

/// Agent卡片
class _AgentCard extends ConsumerWidget {
  final AgentInstance agent;
  
  const _AgentCard({required this.agent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _openAgentSessions(context, ref),
        onLongPress: () => _showAgentOptions(context, ref),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: agent.connected ? Colors.green : Colors.grey,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(agent.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _platformColor(agent.platform).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            agent.platform.toUpperCase(),
                            style: TextStyle(fontSize: 10, color: _platformColor(agent.platform), fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(agent.displayUrl, style: TextStyle(fontSize: 12, color: Colors.grey[400])),
                    if (agent.model != null) ...[
                      const SizedBox(height: 2),
                      Text('Model: ${agent.model}', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                    ],
                  ],
                ),
              ),
              if (agent.unreadCount > 0)
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  child: Text('${agent.unreadCount}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Color _platformColor(String platform) {
    switch (platform) {
      case 'openclaw': return Colors.orange;
      case 'dify': return Colors.blue;
      default: return Colors.purple;
    }
  }

  void _openAgentSessions(BuildContext context, WidgetRef ref) async {
    // Get or create connection
    var connections = ref.read(connectionsProvider);
    var conn = connections[agent.id];
    
    if (conn == null) {
      conn = AgentConnection(agent: agent);
      connections = {...connections, agent.id: conn};
      ref.read(connectionsProvider.notifier).state = connections;
    }
    
    if (!conn.isConnected) {
      await conn.connect();
    }
    
    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => SessionScreen(agent: agent, connection: conn!)),
      );
    }
  }

  void _showAgentOptions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Remove Agent'),
              onTap: () {
                Navigator.pop(context);
                ref.read(agentsProvider).removeAgent(agent.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// Session列表Tab
class _SessionListTab extends ConsumerWidget {
  const _SessionListTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(agentsProvider);
    final agents = store.agents;
    
    if (agents.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 80, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text('No sessions', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.grey)),
            const SizedBox(height: 8),
            Text('Add an agent to start chatting', style: TextStyle(color: Colors.grey[500])),
          ],
        ),
      );
    }
    
    return FutureBuilder(
      future: _fetchAllSessions(ref, agents),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        
        final sessions = snapshot.data as List<Map<String, dynamic>>;
        if (sessions.isEmpty) {
          return Center(
            child: Text('No sessions yet', style: TextStyle(color: Colors.grey[400])),
          );
        }
        
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: sessions.length,
          itemBuilder: (context, index) {
            final s = sessions[index];
            final agent = s['agent'] as AgentInstance;
            final session = s['session'] as HubSession;
            return _SessionCard(agent: agent, session: session);
          },
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _fetchAllSessions(WidgetRef ref, List<AgentInstance> agents) async {
    final result = <Map<String, dynamic>>[];
    final connections = ref.read(connectionsProvider);
    
    for (final agent in agents) {
      var conn = connections[agent.id];
      if (conn == null) {
        conn = AgentConnection(agent: agent);
      }
      if (!conn.isConnected) {
        await conn.connect().catchError((_) => null);
      }
      if (conn.isConnected) {
        final sessions = await conn.fetchSessions();
        for (final s in sessions) {
          result.add({'agent': agent, 'session': s});
        }
      }
    }
    
    return result;
  }
}

class _SessionCard extends ConsumerWidget {
  final AgentInstance agent;
  final HubSession session;
  
  const _SessionCard({required this.agent, required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.orange.withValues(alpha: 0.2),
          child: const Icon(Icons.smart_toy, size: 20),
        ),
        title: Text(session.label ?? session.id, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(agent.name, style: TextStyle(fontSize: 12, color: Colors.grey[400])),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          // Navigate to chat
          var conn = ref.read(connectionsProvider)[agent.id];
          if (conn == null) {
            conn = AgentConnection(agent: agent);
          }
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ChatScreenWrapper(
              agent: agent,
              session: ChatSession(
                id: session.id,
                agentId: agent.id,
                key: session.key,
                label: session.label,
                model: session.model,
              ),
              connection: conn!,
            )),
          );
        },
      ),
    );
  }
}
