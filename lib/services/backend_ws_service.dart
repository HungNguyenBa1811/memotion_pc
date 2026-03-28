import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/constants.dart';
import '../models/session_models.dart';

/// Manages the connection from PC to the backend pose detection service.
///
/// Flow:
/// 1. [createSession]  — POST /api/pose/sessions → session_id
/// 2. [connect]        — open WS; auto-reconnects up to [maxReconnectAttempts]
/// 3. [messages]       — broadcast stream of decoded JSON from backend
/// 4. [sendFrame]      — push JPEG bytes as base64 frame message
/// 5. [fetchResult]    — GET /api/pose/sessions/{id} → [SessionResult]
/// 6. [disconnect]     — intentional close; stops reconnect loop
class BackendWsService {
  static const int maxReconnectAttempts = 3;

  WebSocketChannel? _channel;

  // Stored after connect() for reconnect and fetchResult.
  String? _sessionId;
  String? _jwt;
  bool _intentionalClose = false;
  int _reconnectAttempts = 0;

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();

  /// JSON messages from backend (frame_result, annotated_frame, …).
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  /// `true` when WS is open, `false` when closed/reconnecting.
  Stream<bool> get connectionState => _connectionController.stream;

  bool get isConnected => _channel != null;

  // ── Dio instance (reused) ──────────────────────────────────────────────────

  // URLs are overwritten by PairingNotifier before every session.
  String baseHttpUrl = AppConstants.defaultBackendHttp;
  String baseWsUrl = AppConstants.defaultBackendWs;

  /// Inject a pre-configured [Dio] in tests to avoid real HTTP calls.
  @visibleForTesting
  Dio? dioOverride;

  Dio get _dio =>
      dioOverride ??
      Dio(BaseOptions(
        baseUrl: baseHttpUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ));

  // ── Public API ─────────────────────────────────────────────────────────────

  /// POSTs to backend to create a new pose session. Returns session_id.
  Future<String> createSession({
    required String jwt,
    required String workoutId,
    required String exerciseType,
  }) async {
    final response = await _dio.post(
      AppConstants.poseSessionsEndpoint,
      data: {'workout_id': workoutId, 'exercise_type': exerciseType},
      options: Options(headers: {'Authorization': 'Bearer $jwt'}),
    );
    final data = response.data as Map<String, dynamic>;
    final inner = data['data'] as Map<String, dynamic>? ?? data;
    return inner['session_id'] as String;
  }

  /// Opens the WebSocket for [sessionId]. Retries on unexpected drops.
  Future<void> connect({
    required String sessionId,
    required String jwt,
  }) async {
    _sessionId = sessionId;
    _jwt = jwt;
    _intentionalClose = false;
    _reconnectAttempts = 0;
    await _openSocket();
  }

  /// Ends the session and fetches the final [SessionResult].
  /// DELETE /api/pose/sessions/{id} — backend closes session and returns results.
  Future<SessionResult> fetchResult({
    required String sessionId,
    required String jwt,
  }) async {
    final response = await _dio.delete(
      '${AppConstants.poseSessionsEndpoint}/$sessionId',
      options: Options(headers: {'Authorization': 'Bearer $jwt'}),
    );
    final data = response.data as Map<String, dynamic>;
    final inner = data['data'] as Map<String, dynamic>? ?? data;
    return SessionResult.fromJson(inner);
  }

  /// Marks the workout task as completed on the backend.
  /// PUT /api/tasks/{workoutId}/complete — must be called before sending session_complete to Android.
  Future<void> markTaskCompleted({
    required String workoutId,
    required String jwt,
  }) async {
    await _dio.put(
      '/api/tasks/$workoutId/complete',
      options: Options(headers: {'Authorization': 'Bearer $jwt'}),
    );
  }

  /// Fetches the video_path for a workout task.
  /// GET /api/tasks/{workoutId} → exercise_detail.video_path (relative, e.g. "/videos/arm_raise.mp4")
  /// Returns null if the field is missing or the request fails.
  Future<String?> fetchWorkoutVideoPath({
    required String workoutId,
    required String jwt,
  }) async {
    final response = await _dio.get(
      '/api/tasks/$workoutId',
      options: Options(headers: {'Authorization': 'Bearer $jwt'}),
    );
    final body = response.data as Map<String, dynamic>?;
    final data = body?['data'] as Map<String, dynamic>? ?? body ?? {};
    final exerciseDetail = data['exercise_detail'] as Map<String, dynamic>?;
    return (exerciseDetail?['video_path'] as String?) ??
        (data['video_path'] as String?);
  }

  void sendRaw(String data) => _channel?.sink.add(data);

  /// Encodes [jpegBytes] as base64 and sends as a `frame` message.
  void sendFrame(Uint8List jpegBytes) {
    if (_channel == null) return;
    _channel!.sink.add(jsonEncode({
      'type': 'frame',
      'frame_data': base64Encode(jpegBytes),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    }));
  }

  /// Intentionally closes the WebSocket; suppresses reconnect.
  Future<void> disconnect() async {
    _intentionalClose = true;
    await _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _connectionController.close();
  }

  // ── Private ────────────────────────────────────────────────────────────────

  Future<void> _openSocket() async {
    final uri = Uri.parse(
      '$baseWsUrl${AppConstants.poseSessionsEndpoint}/$_sessionId/ws',
    );

    _channel = WebSocketChannel.connect(
      uri,
      protocols: ['Authorization', 'Bearer $_jwt'],
    );

    _channel!.stream.listen(
      (data) {
        if (data is! String || data.trim().isEmpty) return;
        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          _messageController.add(json);
        } catch (_) {}
      },
      onDone: _onSocketClosed,
      onError: (e) {
        _onSocketClosed();
      },
      cancelOnError: false,
    );

    _reconnectAttempts = 0;
    _connectionController.add(true);
  }

  void _onSocketClosed() {
    _channel = null;
    _connectionController.add(false);

    if (_intentionalClose) return;

    if (_reconnectAttempts < maxReconnectAttempts) {
      _reconnectAttempts++;
      final delay = Duration(seconds: _reconnectAttempts * 2); // 2s, 4s, 6s
      Future.delayed(delay, () {
        if (!_intentionalClose) _openSocket();
      });
    } else {
      // Emit a sentinel so the provider can react.
      _messageController.add({'type': 'connection_failed'});
    }
  }
}
