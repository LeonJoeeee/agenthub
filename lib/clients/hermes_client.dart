/// HTTP client for the agenthub Hermes plugin.
library;

import 'package:dio/dio.dart';

import '../models/agent_model.dart';
import '../models/chat_model.dart';

class HermesApiException implements Exception {
  final int? statusCode;
  final String message;
  HermesApiException(this.message, {this.statusCode});

  @override
  String toString() =>
      statusCode == null ? message : 'HTTP $statusCode: $message';
}

class HermesClient {
  final AgentInstance agent;
  final Dio _dio;

  HermesClient(this.agent)
      : _dio = Dio(BaseOptions(
          baseUrl: agent.endpoint.baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 200),
          headers: agent.endpoint.authHeaders,
        ));

  Future<bool> ping() async {
    try {
      final r = await _dio.get('/health',
          options: Options(headers: const {})); // public endpoint
      return r.statusCode == 200 && (r.data as Map)['ok'] == true;
    } on DioException {
      return false;
    }
  }

  Future<List<ChatSession>> listSessions({int limit = 50, int offset = 0}) async {
    try {
      final r = await _dio.get('/v1/sessions', queryParameters: {
        'limit': limit,
        'offset': offset,
      });
      final list = (r.data['sessions'] as List)
          .map((e) => ChatSession.fromJson(e as Map<String, dynamic>))
          .toList();
      return list;
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  Future<List<ChatMessage>> getMessages(String sessionId,
      {int limit = 1000}) async {
    try {
      final r = await _dio.get('/v1/sessions/$sessionId/messages',
          queryParameters: {'limit': limit});
      return (r.data['messages'] as List)
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  Future<ChatMessage> sendChat({
    required String content,
    String? sessionId,
  }) async {
    try {
      final r = await _dio.post('/v1/chat', data: {
        'content': content,
        if (sessionId != null) 'session_id': sessionId,
      });
      final data = r.data as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw HermesApiException(
            (data['error'] as String?) ?? 'unknown agent error');
      }
      return ChatMessage.local(
          role: 'assistant', content: data['reply'] as String? ?? '');
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  Future<Map<String, dynamic>> capabilities() async {
    try {
      final r = await _dio.get('/v1/capabilities');
      return Map<String, dynamic>.from(r.data as Map);
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  HermesApiException _wrap(DioException e) {
    final code = e.response?.statusCode;
    final body = e.response?.data;
    final msg = (body is Map && body['error'] != null)
        ? body['error'].toString()
        : (e.message ?? 'request failed');
    return HermesApiException(msg, statusCode: code);
  }
}
