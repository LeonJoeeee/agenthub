/// 聊天界面 — 与Agent的对话
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/agent_model.dart';
import '../models/chat_model.dart';
import '../protocol/hub_protocol.dart';
import '../services/agent_connection.dart';

/// 当前聊天session的provider
final currentSessionMessagesProvider = StateProvider.family<List<ChatMessage>, String>((ref, sessionId) => []);

/// ChatScreen包装器 — 设置provider
class ChatScreenWrapper extends ConsumerWidget {
  final AgentInstance agent;
  final ChatSession session;
  final AgentConnection connection;

  const ChatScreenWrapper({
    super.key,
    required this.agent,
    required this.session,
    required this.connection,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ChatScreen(
      agent: agent,
      session: session,
      connection: connection,
    );
  }
}

class ChatScreen extends ConsumerStatefulWidget {
  final AgentInstance agent;
  final ChatSession session;
  final AgentConnection connection;

  const ChatScreen({
    super.key,
    required this.agent,
    required this.session,
    required this.connection,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  StreamSubscription? _messageSubscription;
  StreamSubscription? _statusSubscription;
  String _streamingContent = '';
  bool _isStreaming = false;
  bool _isThinking = false;

  @override
  void initState() {
    super.initState();
    _listenToMessages();
    _listenToStatus();
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _statusSubscription?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _listenToMessages() {
    _messageSubscription = widget.connection.messageStream.listen((msg) {
      if (msg.sessionId != null && msg.sessionId != widget.session.key) return;
      
      switch (msg.type) {
        case HubMessageType.chatStream:
          setState(() {
            _isStreaming = true;
            _isThinking = msg.payload['status'] == 'thinking';
            if (msg.payload.containsKey('delta')) {
              _streamingContent += msg.payload['delta'] ?? '';
            }
          });
          _scrollToBottom();
          break;
          
        case HubMessageType.chatStreamEnd:
          setState(() {
            _isStreaming = false;
            _isThinking = false;
            // stream_end payload contains the full content
            final fullContent = msg.payload['content'] as String? ?? _streamingContent;
            if (fullContent.isNotEmpty) {
              final messages = ref.read(currentSessionMessagesProvider(widget.session.id));
              ref.read(currentSessionMessagesProvider(widget.session.id).notifier).state = [
                ...messages,
                ChatMessage(
                  id: '${DateTime.now().millisecondsSinceEpoch}',
                  sessionId: widget.session.id,
                  agentId: widget.agent.id,
                  role: 'assistant',
                  content: fullContent,
                ),
              ];
            }
            _streamingContent = '';
          });
          _scrollToBottom();
          break;
          
        case HubMessageType.chatMessage:
          if (msg.payload['role'] == 'assistant') {
            final messages = ref.read(currentSessionMessagesProvider(widget.session.id));
            ref.read(currentSessionMessagesProvider(widget.session.id).notifier).state = [
              ...messages,
              ChatMessage(
                id: '${DateTime.now().millisecondsSinceEpoch}',
                sessionId: widget.session.id,
                agentId: widget.agent.id,
                role: 'assistant',
                content: msg.payload['content'] ?? '',
              ),
            ];
            _scrollToBottom();
          }
          break;
          
        case HubMessageType.error:
          setState(() {
            _isStreaming = false;
            _isThinking = false;
            _streamingContent = '';
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: ${msg.payload['message'] ?? 'Unknown'}'), backgroundColor: Colors.red),
            );
          }
          break;
      }
    });
  }

  void _listenToStatus() {
    _statusSubscription = widget.connection.statusStream.listen((status) {
      if (status == ConnectionStatus.disconnected || status == ConnectionStatus.error) {
        if (mounted) {
          setState(() {
            _isStreaming = false;
            _isThinking = false;
          });
        }
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isStreaming) return;

    // 添加用户消息到列表
    final messages = ref.read(currentSessionMessagesProvider(widget.session.id));
    ref.read(currentSessionMessagesProvider(widget.session.id).notifier).state = [
      ...messages,
      ChatMessage(
        id: '${DateTime.now().millisecondsSinceEpoch}',
        sessionId: widget.session.id,
        agentId: widget.agent.id,
        role: 'user',
        content: text,
      ),
    ];

    // 发送给Agent
    widget.connection.sendChatMessage(
      content: text,
      sessionId: widget.session.key,
    );

    _inputController.clear();
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(currentSessionMessagesProvider(widget.session.id));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.agent.name, style: const TextStyle(fontSize: 16)),
            Text(
              widget.session.label ?? 'Session',
              style: TextStyle(fontSize: 12, color: Colors.grey[400]),
            ),
          ],
        ),
        actions: [
          StreamBuilder<ConnectionStatus>(
            stream: widget.connection.statusStream,
            initialData: widget.connection.status,
            builder: (context, snapshot) {
              final status = snapshot.data ?? ConnectionStatus.disconnected;
              return IconButton(
                icon: Icon(
                  status == ConnectionStatus.connected ? Icons.cloud_done : Icons.cloud_off,
                  color: status == ConnectionStatus.connected ? Colors.green : Colors.grey,
                ),
                onPressed: null,
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 消息列表
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: messages.length + (_isStreaming || _isThinking ? 1 : 0),
              itemBuilder: (context, index) {
                if ((_isStreaming || _isThinking) && index == messages.length) {
                  return _buildMessageBubble(
                    role: 'assistant',
                    content: _streamingContent,
                    isStreaming: true,
                    isThinking: _isThinking,
                  );
                }
                
                final msg = messages[index];
                return _buildMessageBubble(
                  role: msg.role,
                  content: msg.content,
                  needsApproval: msg.needsApproval,
                );
              },
            ),
          ),
          
          // 输入区域
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble({
    required String role,
    required String content,
    bool isStreaming = false,
    bool isThinking = false,
    bool needsApproval = false,
  }) {
    final isUser = role == 'user';
    
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser 
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
            : Theme.of(context).cardColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isUser ? const Radius.circular(16) : Radius.zero,
            bottomRight: isUser ? Radius.zero : const Radius.circular(16),
          ),
          border: isUser ? null : Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isThinking && content.isEmpty)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey[400])),
                  const SizedBox(width: 8),
                  Text('Thinking...', style: TextStyle(color: Colors.grey[400], fontStyle: FontStyle.italic)),
                ],
              )
            else if (isStreaming && content.isNotEmpty)
              MarkdownBody(data: '$content▌')
            else if (content.isNotEmpty)
              MarkdownBody(data: content),
            
            if (needsApproval)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.tonal(
                      onPressed: () {/* TODO: approve */},
                      child: const Text('Approve'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () {/* TODO: reject */},
                      child: const Text('Reject'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: Colors.grey.withValues(alpha: 0.2))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              decoration: InputDecoration(
                hintText: _isStreaming ? 'Waiting for response...' : 'Message ${widget.agent.name}...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              maxLines: 4,
              minLines: 1,
              textInputAction: TextInputAction.send,
              enabled: !_isStreaming,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _isStreaming ? null : _sendMessage,
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}
