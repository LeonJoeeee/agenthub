/// Home — list of bound agents.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_model.dart';
import '../services/agent_store.dart';
import 'add_agent_screen.dart';
import 'session_screen.dart';

final agentsProvider = ChangeNotifierProvider<AgentStore>((_) => AgentStore());

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(agentsProvider).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(agentsProvider);
    final agents = store.agents;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AgentHub'),
        elevation: 0,
      ),
      body: agents.isEmpty
          ? _Empty(onAdd: _navigateToAdd)
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: agents.length,
              itemBuilder: (_, i) => _AgentCard(agent: agents[i]),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _navigateToAdd,
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
    );
  }

  Future<void> _navigateToAdd() async {
    final added = await Navigator.push<AgentInstance>(
      context,
      MaterialPageRoute(builder: (_) => const AddAgentScreen()),
    );
    if (added != null) {
      await ref.read(agentsProvider).add(added);
    }
  }
}

class _Empty extends StatelessWidget {
  final VoidCallback onAdd;
  const _Empty({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.smart_toy_outlined, size: 80, color: Colors.grey[600]),
          const SizedBox(height: 16),
          Text(
            'No agents yet',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 8),
          const Text(
            'Scan the QR shown by the\nagenthub plugin to bind one',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan to add'),
          ),
        ],
      ),
    );
  }
}

class _AgentCard extends ConsumerWidget {
  final AgentInstance agent;
  const _AgentCard({required this.agent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SessionScreen(agent: agent),
          ),
        ),
        onLongPress: () => _showOptions(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: agent.online ? Colors.green : Colors.grey,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      agent.name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${agent.endpoint.host}:${agent.endpoint.port}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                    ),
                    if (agent.model != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Model: ${agent.model}',
                        style:
                            TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  void _showOptions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Remove agent'),
              onTap: () async {
                Navigator.pop(context);
                await ref.read(agentsProvider).remove(agent.id);
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
