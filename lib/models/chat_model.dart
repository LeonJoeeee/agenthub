/// Chat message + session models — match the shapes returned by the
/// agenthub plugin's /v1 endpoints.
library;

class ChatMessage {
  final int id;
  final String role; // user | assistant | tool | system
  final String? content;
  final String? toolName;
  final dynamic toolCalls;
  final DateTime timestamp;
  final String? finishReason;

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.toolName,
    this.toolCalls,
    this.finishReason,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as int,
        role: json['role'] as String,
        content: json['content'] as String?,
        toolName: json['tool_name'] as String?,
        toolCalls: json['tool_calls'],
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          ((json['timestamp'] as num) * 1000).toInt(),
        ),
        finishReason: json['finish_reason'] as String?,
      );

  /// Lightweight client-only constructor for messages composed in the App
  /// before they're persisted to the server.
  factory ChatMessage.local({
    required String role,
    required String content,
  }) =>
      ChatMessage(
        id: -DateTime.now().microsecondsSinceEpoch,
        role: role,
        content: content,
        timestamp: DateTime.now(),
      );
}

class ChatSession {
  final String id;
  final String? source;
  final String? model;
  final String? title;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int messageCount;
  final int toolCallCount;
  final int inputTokens;
  final int outputTokens;
  final double? costUsd;

  ChatSession({
    required this.id,
    required this.startedAt,
    this.source,
    this.model,
    this.title,
    this.endedAt,
    this.messageCount = 0,
    this.toolCallCount = 0,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.costUsd,
  });

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
        id: json['id'] as String,
        source: json['source'] as String?,
        model: json['model'] as String?,
        title: json['title'] as String?,
        startedAt: DateTime.fromMillisecondsSinceEpoch(
          ((json['started_at'] as num) * 1000).toInt(),
        ),
        endedAt: json['ended_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(
                ((json['ended_at'] as num) * 1000).toInt(),
              )
            : null,
        messageCount: (json['message_count'] as int?) ?? 0,
        toolCallCount: (json['tool_call_count'] as int?) ?? 0,
        inputTokens: (json['input_tokens'] as int?) ?? 0,
        outputTokens: (json['output_tokens'] as int?) ?? 0,
        costUsd: (json['cost_usd'] as num?)?.toDouble(),
      );

  String get displayTitle {
    if (title != null && title!.trim().isNotEmpty) return title!;
    return id;
  }
}
