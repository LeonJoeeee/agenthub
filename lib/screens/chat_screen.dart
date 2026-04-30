/// Chat screen — fetch history on load, send via POST /v1/chat.
library;

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../clients/hermes_client.dart';
import '../models/agent_model.dart';
import '../models/chat_model.dart';

class ChatScreen extends StatefulWidget {
  final AgentInstance agent;
  /// Existing session to attach to. null = start a fresh chat (no session_id sent).
  final String? sessionId;
  final String? sessionTitle;

  const ChatScreen({
    super.key,
    required this.agent,
    required this.sessionId,
    this.sessionTitle,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final HermesClient _client;
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  final List<ChatMessage> _messages = [];
  String? _activeSessionId;
  bool _loading = false;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _client = HermesClient(widget.agent);
    _activeSessionId = widget.sessionId;
    if (widget.sessionId != null) _loadHistory();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final msgs = await _client.getMessages(_activeSessionId!);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(msgs);
      });
      _scrollToEnd();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _messages.add(ChatMessage.local(role: 'user', content: text));
      _inputCtrl.clear();
    });
    _scrollToEnd();
    try {
      final reply = await _client.sendChat(
        content: text,
        sessionId: _activeSessionId,
      );
      if (!mounted) return;
      setState(() => _messages.add(reply));
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
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
              widget.sessionTitle ??
                  (_activeSessionId == null
                      ? 'New chat'
                      : _activeSessionId!),
              style: TextStyle(fontSize: 11, color: Colors.grey[400]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _body()),
          _inputBar(),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent)),
        ),
      );
    }
    if (_messages.isEmpty) {
      return Center(
        child: Text(
          _activeSessionId == null
              ? 'Send a message to start a new conversation'
              : 'No messages in this session',
          style: TextStyle(color: Colors.grey[500]),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.all(12),
      itemCount: _messages.length + (_sending ? 1 : 0),
      itemBuilder: (_, i) {
        if (_sending && i == _messages.length) {
          return const _ThinkingBubble();
        }
        return _MessageBubble(message: _messages[i]);
      },
    );
  }

  Widget _inputBar() {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(color: Colors.grey.withValues(alpha: 0.18)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputCtrl,
              minLines: 1,
              maxLines: 5,
              enabled: !_sending,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: _sending
                    ? 'Waiting for ${widget.agent.name}…'
                    : 'Message ${widget.agent.name}',
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide:
                      BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _sending ? null : _send,
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final isTool = message.role == 'tool';
    final body = message.content?.trim() ?? '';
    if (body.isEmpty && message.toolCalls == null) {
      return const SizedBox.shrink();
    }
    final bg = isUser
        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.18)
        : isTool
            ? Colors.amber.withValues(alpha: 0.10)
            : Theme.of(context).cardColor;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: isUser ? const Radius.circular(14) : Radius.zero,
            bottomRight: isUser ? Radius.zero : const Radius.circular(14),
          ),
          border: isUser
              ? null
              : Border.all(color: Colors.grey.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isTool && message.toolName != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '🛠 ${message.toolName!}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.amber[200],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (body.isNotEmpty) MarkdownBody(data: body),
          ],
        ),
      ),
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(width: 10),
            Text('Thinking…',
                style: TextStyle(
                    color: Colors.grey[400], fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }
}
