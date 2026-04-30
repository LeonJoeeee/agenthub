/// Connection profile for an AgentHub-plugin-equipped agent server.
///
/// Plugin lives on the agent host (currently only Hermes). The mobile App
/// stores host/port/token in shared_preferences and talks directly to:
///   GET  /health
///   GET  /v1/sessions
///   GET  /v1/sessions/{id}
///   GET  /v1/sessions/{id}/messages
///   POST /v1/chat
///   GET  /v1/capabilities
library;

class AgentEndpoint {
  final String host;
  final int port;
  final String token;
  final bool secure;

  const AgentEndpoint({
    required this.host,
    required this.port,
    required this.token,
    this.secure = false,
  });

  String get baseUrl =>
      '${secure ? 'https' : 'http'}://$host:$port';

  Map<String, String> get authHeaders => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'token': token,
        'secure': secure,
      };

  factory AgentEndpoint.fromJson(Map<String, dynamic> json) => AgentEndpoint(
        host: json['host'] as String,
        port: json['port'] as int,
        token: json['token'] as String,
        secure: json['secure'] as bool? ?? false,
      );

  /// Parse the URI emitted by the plugin's pairing QR:
  ///   agenthub://pair?host=192.168.x.x&port=18790&token=...
  static AgentEndpoint? tryParsePairUri(String raw) {
    Uri? uri;
    try {
      uri = Uri.parse(raw.trim());
    } catch (_) {
      return null;
    }
    if (uri.scheme != 'agenthub' || uri.host != 'pair') return null;
    final qp = uri.queryParameters;
    final host = qp['host'];
    final portStr = qp['port'];
    final token = qp['token'];
    if (host == null || portStr == null || token == null) return null;
    final port = int.tryParse(portStr);
    if (port == null) return null;
    return AgentEndpoint(
      host: host,
      port: port,
      token: token,
      secure: qp['secure'] == 'true',
    );
  }
}
