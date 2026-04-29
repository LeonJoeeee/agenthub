/// Agent实例数据模型
library;

class AgentInstance {
  String id;
  String name;
  String baseUrl; // e.g. https://myserver.com or http://192.168.1.100:18789
  String? authToken; // 认证token（配对后获得）
  String? agentPublicKey; // Agent的Ed25519公钥
  String platform; // 'openclaw' | 'dify' | 'other'
  bool connected;
  DateTime lastConnected;
  int unreadCount;
  String? model; // Agent当前使用的模型
  int permissionLevel; // 0-5, 见安全架构
  DateTime createdAt;

  AgentInstance({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.authToken,
    this.agentPublicKey,
    this.platform = 'openclaw',
    this.connected = false,
    DateTime? lastConnected,
    this.unreadCount = 0,
    this.model,
    this.permissionLevel = 1,
    DateTime? createdAt,
  })  : lastConnected = lastConnected ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();

  /// 显示用的地址（隐藏协议和端口）
  String get displayUrl {
    var url = baseUrl
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceFirst(RegExp(r':\d+$'), '');
    return url;
  }

  /// WebSocket URL
  String get wsUrl {
    var url = baseUrl;
    if (url.startsWith('https://')) {
      url = 'wss://${url.substring(8)}';
    } else if (url.startsWith('http://')) {
      url = 'ws://${url.substring(7)}';
    }
    return '$url/hub/ws';
  }

  /// API base URL
  String get apiUrl => '$baseUrl/hub';

  /// 是否已配对
  bool get isPaired => authToken != null && agentPublicKey != null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'authToken': authToken,
    'agentPublicKey': agentPublicKey,
    'platform': platform,
    'connected': connected,
    'lastConnected': lastConnected.toIso8601String(),
    'unreadCount': unreadCount,
    'model': model,
    'permissionLevel': permissionLevel,
    'createdAt': createdAt.toIso8601String(),
  };

  factory AgentInstance.fromJson(Map<String, dynamic> json) => AgentInstance(
    id: json['id'] as String,
    name: json['name'] as String,
    baseUrl: json['baseUrl'] as String,
    authToken: json['authToken'] as String?,
    agentPublicKey: json['agentPublicKey'] as String?,
    platform: json['platform'] as String? ?? 'openclaw',
    connected: json['connected'] as bool? ?? false,
    lastConnected: json['lastConnected'] != null ? DateTime.parse(json['lastConnected'] as String) : null,
    unreadCount: json['unreadCount'] as int? ?? 0,
    model: json['model'] as String?,
    permissionLevel: json['permissionLevel'] as int? ?? 1,
    createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt'] as String) : null,
  );

  AgentInstance copyWith({
    String? name,
    String? baseUrl,
    String? authToken,
    String? agentPublicKey,
    String? platform,
    bool? connected,
    DateTime? lastConnected,
    int? unreadCount,
    String? model,
    int? permissionLevel,
  }) {
    return AgentInstance(
      id: id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      authToken: authToken ?? this.authToken,
      agentPublicKey: agentPublicKey ?? this.agentPublicKey,
      platform: platform ?? this.platform,
      connected: connected ?? this.connected,
      lastConnected: lastConnected ?? this.lastConnected,
      unreadCount: unreadCount ?? this.unreadCount,
      model: model ?? this.model,
      permissionLevel: permissionLevel ?? this.permissionLevel,
    );
  }
}
