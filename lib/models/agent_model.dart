/// Configured agent — one entry per host the App is bound to.
library;

import '../protocol/hub_protocol.dart';

class AgentInstance {
  final String id;
  String name;
  AgentEndpoint endpoint;
  /// Last known model string (cached from /v1/capabilities).
  String? model;
  bool online;
  DateTime lastSeen;
  DateTime createdAt;

  AgentInstance({
    required this.id,
    required this.name,
    required this.endpoint,
    this.model,
    this.online = false,
    DateTime? lastSeen,
    DateTime? createdAt,
  })  : lastSeen = lastSeen ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();

  /// Friendly host string for the UI (no scheme, no port).
  String get displayHost => endpoint.host;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'endpoint': endpoint.toJson(),
        'model': model,
        'online': online,
        'lastSeen': lastSeen.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory AgentInstance.fromJson(Map<String, dynamic> json) {
    final endpoint = AgentEndpoint.fromJson(
      json['endpoint'] as Map<String, dynamic>,
    );
    return AgentInstance(
      id: json['id'] as String,
      name: json['name'] as String,
      endpoint: endpoint,
      model: json['model'] as String?,
      online: json['online'] as bool? ?? false,
      lastSeen: json['lastSeen'] != null
          ? DateTime.parse(json['lastSeen'] as String)
          : null,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
    );
  }

  AgentInstance copyWith({
    String? name,
    AgentEndpoint? endpoint,
    String? model,
    bool? online,
    DateTime? lastSeen,
  }) =>
      AgentInstance(
        id: id,
        name: name ?? this.name,
        endpoint: endpoint ?? this.endpoint,
        model: model ?? this.model,
        online: online ?? this.online,
        lastSeen: lastSeen ?? this.lastSeen,
        createdAt: createdAt,
      );
}
