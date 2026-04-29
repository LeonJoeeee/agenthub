/// AgentHub Protocol — App与Agent之间的通信协议
/// 
/// App只和Agent通信，不直接接触LLM API。
/// 协议核心：App发人话给Agent，Agent自己处理LLM/工具/上下文，再把结果返回App。

library agenthub_protocol;

// Protocol version
const String kProtocolVersion = '1.0.0';

// WebSocket message types
class HubMessageType {
  static const String chatMessage = 'chat.message';
  static const String chatStream = 'chat.stream';
  static const String chatStreamEnd = 'chat.stream_end';
  static const String sessionUpdate = 'session.update';
  static const String sessionList = 'session.list';
  static const String agentNotification = 'agent.notification';
  static const String agentApproval = 'agent.approval';
  static const String approvalResponse = 'approval.response';
  static const String error = 'error';
  static const String ping = 'ping';
  static const String pong = 'pong';
}

// REST API paths
class HubApiPaths {
  static const String pair = '/hub/pair';
  static const String auth = '/hub/auth';
  static const String revoke = '/hub/revoke';
  static const String sessions = '/hub/sessions';
  static const String status = '/hub/status';
  static const String pushRegister = '/hub/push/register';
  static const String pushUnregister = '/hub/push/unregister';
}

/// WebSocket消息封装
class HubMessage {
  final String type;
  final Map<String, dynamic> payload;
  final String? sessionId;
  final int timestamp;

  HubMessage({
    required this.type,
    required this.payload,
    this.sessionId,
    int? timestamp,
  }) : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  factory HubMessage.fromJson(Map<String, dynamic> json) {
    return HubMessage(
      type: json['type'] as String,
      payload: json['payload'] as Map<String, dynamic>? ?? {},
      sessionId: json['session_id'] as String?,
      timestamp: json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'payload': payload,
      if (sessionId != null) 'session_id': sessionId,
      'timestamp': timestamp,
    };
  }

  /// 创建聊天消息
  factory HubMessage.chatMessage({
    required String content,
    String? sessionId,
  }) {
    return HubMessage(
      type: HubMessageType.chatMessage,
      payload: {'content': content, 'role': 'user'},
      sessionId: sessionId,
    );
  }

  /// 创建流式chunk
  factory HubMessage.chatStream({
    required String delta,
    String? sessionId,
  }) {
    return HubMessage(
      type: HubMessageType.chatStream,
      payload: {'delta': delta},
      sessionId: sessionId,
    );
  }
}

/// Agent状态
class AgentStatus {
  final bool online;
  final String? model;
  final int? activeSessions;
  final String? version;

  AgentStatus({
    required this.online,
    this.model,
    this.activeSessions,
    this.version,
  });

  factory AgentStatus.fromJson(Map<String, dynamic> json) {
    return AgentStatus(
      online: json['online'] as bool? ?? false,
      model: json['model'] as String?,
      activeSessions: json['active_sessions'] as int?,
      version: json['version'] as String?,
    );
  }
}

/// Session信息
class HubSession {
  final String id;
  final String? key;
  final String? label;
  final String? model;
  final int? updatedAt;
  final int? inputTokens;
  final int? outputTokens;
  final String? lastMessage;

  HubSession({
    required this.id,
    this.key,
    this.label,
    this.model,
    this.updatedAt,
    this.inputTokens,
    this.outputTokens,
    this.lastMessage,
  });

  factory HubSession.fromJson(Map<String, dynamic> json) {
    return HubSession(
      id: json['id'] as String,
      key: json['key'] as String?,
      label: json['label'] as String?,
      model: json['model'] as String?,
      updatedAt: json['updated_at'] as int?,
      inputTokens: json['input_tokens'] as int?,
      outputTokens: json['output_tokens'] as int?,
      lastMessage: json['last_message'] as String?,
    );
  }
}

/// 配对请求
class PairRequest {
  final String devicePublicKey;
  final String deviceName;
  final String deviceType; // 'ios' | 'android'
  final String challenge;

  PairRequest({
    required this.devicePublicKey,
    required this.deviceName,
    required this.deviceType,
    required this.challenge,
  });

  Map<String, dynamic> toJson() => {
    'device_public_key': devicePublicKey,
    'device_name': deviceName,
    'device_type': deviceType,
    'challenge': challenge,
  };
}

/// 配对响应
class PairResponse {
  final bool success;
  final String? agentPublicKey;
  final String? token; // 后续认证用的token
  final String? error;

  PairResponse({
    required this.success,
    this.agentPublicKey,
    this.token,
    this.error,
  });

  factory PairResponse.fromJson(Map<String, dynamic> json) {
    return PairResponse(
      success: json['success'] as bool? ?? false,
      agentPublicKey: json['agent_public_key'] as String?,
      token: json['token'] as String?,
      error: json['error'] as String?,
    );
  }
}
