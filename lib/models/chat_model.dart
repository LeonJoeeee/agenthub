/// 聊天消息模型
library;

/// 单条消息
class ChatMessage {
  String id;
  String sessionId;
  String agentId;
  String role; // 'user' | 'assistant' | 'system' | 'tool'
  String content;
  DateTime timestamp;
  bool streaming; // 是否正在流式输出
  String? toolName;
  String? toolInput;
  String? toolOutput;
  bool needsApproval;
  bool? approved;

  ChatMessage({
    required this.id,
    required this.sessionId,
    required this.agentId,
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.streaming = false,
    this.toolName,
    this.toolInput,
    this.toolOutput,
    this.needsApproval = false,
    this.approved,
  }) : timestamp = timestamp ?? DateTime.now();

  ChatMessage copyWith({
    String? content,
    bool? streaming,
    String? toolOutput,
    bool? approved,
  }) {
    return ChatMessage(
      id: id,
      sessionId: sessionId,
      agentId: agentId,
      role: role,
      content: content ?? this.content,
      timestamp: timestamp,
      streaming: streaming ?? this.streaming,
      toolName: toolName,
      toolInput: toolInput,
      toolOutput: toolOutput ?? this.toolOutput,
      needsApproval: needsApproval,
      approved: approved ?? this.approved,
    );
  }
}

/// Session（对话）
class ChatSession {
  String id;
  String agentId;
  String? key; // Agent端的session key
  String? label;
  String? model;
  DateTime createdAt;
  DateTime updatedAt;
  int messageCount;
  String? lastMessage;
  int unreadCount;

  ChatSession({
    required this.id,
    required this.agentId,
    this.key,
    this.label,
    this.model,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.messageCount = 0,
    this.lastMessage,
    this.unreadCount = 0,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  ChatSession copyWith({
    String? label,
    String? model,
    DateTime? updatedAt,
    int? messageCount,
    String? lastMessage,
    int? unreadCount,
  }) {
    return ChatSession(
      id: id,
      agentId: agentId,
      key: key,
      label: label ?? this.label,
      model: model ?? this.model,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messageCount: messageCount ?? this.messageCount,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}
