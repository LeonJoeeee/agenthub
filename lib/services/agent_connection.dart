/// Agent连接服务 — 管理与AgentHub Server的WebSocket连接
library;

import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:dio/dio.dart';
import '../models/agent_model.dart';
import '../protocol/hub_protocol.dart';

/// 连接状态
enum ConnectionStatus { disconnected, connecting, connected, error }

/// Agent连接 — 封装与AgentHub Server的通信
class AgentConnection {
  final AgentInstance agent;
  WebSocketChannel? _channel;
  Dio? _dio;
  
  ConnectionStatus _status = ConnectionStatus.disconnected;
  String? _errorMessage;
  
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  final _messageController = StreamController<HubMessage>.broadcast();
  final _notificationController = StreamController<HubMessage>.broadcast();
  
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  int _reconnectAttempts = 0;
  
  static const int _maxReconnectAttempts = 5;
  static const Duration _pingInterval = Duration(seconds: 30);

  AgentConnection({required this.agent});

  // Streams
  Stream<ConnectionStatus> get statusStream => _statusController.stream;
  Stream<HubMessage> get messageStream => _messageController.stream;
  Stream<HubMessage> get notificationStream => _notificationController.stream;
  
  // Current state
  ConnectionStatus get status => _status;
  String? get errorMessage => _errorMessage;
  bool get isConnected => _status == ConnectionStatus.connected;

  /// 连接AgentHub Server
  Future<void> connect() async {
    if (_status == ConnectionStatus.connecting || _status == ConnectionStatus.connected) return;
    
    _setStatus(ConnectionStatus.connecting);
    _errorMessage = null;
    
    try {
      // 1. 先通过HTTP验证Agent可达性
      _dio ??= Dio(BaseOptions(
        baseUrl: agent.apiUrl,
        connectTimeout: const Duration(seconds: 10),
        headers: agent.authToken != null 
          ? {'Authorization': 'Bearer ${agent.authToken}'}
          : {},
      ));
      
      final statusResp = await _dio!.get(HubApiPaths.status);
      if (statusResp.statusCode != 200) {
        throw Exception('Agent status check failed: ${statusResp.statusCode}');
      }
      
      // 2. 建立WebSocket连接（带token认证）
      final wsUrl = agent.isPaired 
        ? '${agent.wsUrl}?token=${agent.authToken}'
        : agent.wsUrl;
      
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      
      // 3. 监听消息
      _channel!.stream.listen(
        _onData,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );
      
      // 4. 启动心跳
      _startPing();
      
      _setStatus(ConnectionStatus.connected);
      _reconnectAttempts = 0;
      
    } catch (e) {
      _errorMessage = e.toString();
      _setStatus(ConnectionStatus.error);
      _scheduleReconnect();
    }
  }

  /// 断开连接
  void disconnect() {
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _setStatus(ConnectionStatus.disconnected);
  }

  /// 发送聊天消息
  void sendChatMessage({
    required String content,
    String? sessionId,
  }) {
    if (!isConnected) return;
    
    final msg = HubMessage.chatMessage(
      content: content,
      sessionId: sessionId,
    );
    _send(msg);
  }

  /// 发送审批响应
  void sendApprovalResponse({
    required String approvalId,
    required bool approved,
    String? sessionId,
  }) {
    if (!isConnected) return;
    
    final msg = HubMessage(
      type: HubMessageType.approvalResponse,
      payload: {
        'approval_id': approvalId,
        'approved': approved,
      },
      sessionId: sessionId,
    );
    _send(msg);
  }

  /// 获取Session列表
  Future<List<HubSession>> fetchSessions() async {
    if (_dio == null) return [];
    
    try {
      final resp = await _dio!.get(HubApiPaths.sessions);
      final list = resp.data as List;
      return list.map((e) => HubSession.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      return [];
    }
  }

  /// 创建新Session
  Future<HubSession?> createSession({String? label}) async {
    if (_dio == null) return null;
    
    try {
      final resp = await _dio!.post(HubApiPaths.sessions, data: {
        if (label != null) 'label': label,
      });
      return HubSession.fromJson(resp.data);
    } catch (e) {
      return null;
    }
  }

  /// 配对新设备
  Future<PairResponse> pair(PairRequest request) async {
    try {
      final dio = Dio(BaseOptions(
        baseUrl: agent.apiUrl,
        connectTimeout: const Duration(seconds: 15),
      ));
      
      final resp = await dio.post(HubApiPaths.pair, data: request.toJson());
      return PairResponse.fromJson(resp.data);
    } catch (e) {
      return PairResponse(success: false, error: e.toString());
    }
  }

  // ============ Private ============

  void _send(HubMessage msg) {
    _channel?.sink.add(jsonEncode(msg.toJson()));
  }

  void _onData(dynamic data) {
    try {
      final json = jsonDecode(data as String) as Map<String, dynamic>;
      final msg = HubMessage.fromJson(json);
      
      switch (msg.type) {
        case HubMessageType.chatMessage:
        case HubMessageType.chatStream:
        case HubMessageType.chatStreamEnd:
          _messageController.add(msg);
          break;
        case HubMessageType.agentNotification:
        case HubMessageType.agentApproval:
          _notificationController.add(msg);
          break;
        case HubMessageType.pong:
          break;
        case HubMessageType.error:
          _errorMessage = msg.payload['message'] as String?;
          _messageController.add(msg); // Also forward errors to message stream
          break;
      }
    } catch (e) {
      // Parse error, ignore
    }
  }

  void _onError(dynamic error) {
    _errorMessage = error.toString();
    _setStatus(ConnectionStatus.error);
    _scheduleReconnect();
  }

  void _onDone() {
    _setStatus(ConnectionStatus.disconnected);
    _scheduleReconnect();
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_pingInterval, (_) {
      if (isConnected) {
        _send(HubMessage(type: HubMessageType.ping, payload: {}));
      }
    });
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) return;
    
    _reconnectAttempts++;
    final delay = Duration(seconds: _reconnectAttempts * 2);
    
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, connect);
  }

  void _setStatus(ConnectionStatus status) {
    _status = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  void dispose() {
    disconnect();
    _statusController.close();
    _messageController.close();
    _notificationController.close();
  }
}
