import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:dio/dio.dart';
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
  // TODO(jwt): re-enable auth — stored but unused until backend is up.
  // ignore: unused_field
  String? _jwt;
  bool _intentionalClose = false;
  int _reconnectAttempts = 0;

  final _messageController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();

  /// JSON messages from backend (frame_result, annotated_frame, …).
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  /// `true` when WS is open, `false` when closed/reconnecting.
  Stream<bool> get connectionState => _connectionController.stream;

  bool get isConnected => _channel != null;

  // ── Dio instance (reused) ──────────────────────────────────────────────────

  // URLs are overwritten by PairingNotifier before every session.
  String baseHttpUrl = AppConstants.defaultBackendHttp;
  String baseWsUrl   = AppConstants.defaultBackendWs;

  Dio get _dio => Dio(BaseOptions(
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
      // TODO(jwt): options: Options(headers: {'Authorization': 'Bearer $jwt'}),
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

  /// Fetches the final [SessionResult] from the REST endpoint.
  /// Call after [disconnect] once the backend has closed the session.
  Future<SessionResult> fetchResult({
    required String sessionId,
    required String jwt,
  }) async {
    final response = await _dio.get(
      '${AppConstants.poseSessionsEndpoint}/$sessionId',
      // TODO(jwt): options: Options(headers: {'Authorization': 'Bearer $jwt'}),
    );
    final data = response.data as Map<String, dynamic>;
    final inner = data['data'] as Map<String, dynamic>? ?? data;
    return SessionResult.fromJson(inner);
  }

  void sendRaw(String data) => _channel?.sink.add(data);

  /// Encodes [jpegBytes] as base64 and sends as a `frame` message.
  void sendFrame(Uint8List jpegBytes) {
    if (_channel == null) return;
    _channel!.sink.add(jsonEncode({
      'type': 'frame',
      'data': base64Encode(jpegBytes),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    }));
  }

  /// Intentionally closes the WebSocket; suppresses reconnect.
  Future<void> disconnect() async {
    _intentionalClose = true;
    await _channel?.sink.close();
    _channel = null;
    developer.log('[BackendWs] Disconnected');
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
    developer.log('[BackendWs] Connecting to $uri (attempt ${_reconnectAttempts + 1})');

    _channel = WebSocketChannel.connect(
      uri,
      // TODO(jwt): protocols: ['Authorization', 'Bearer $_jwt'],
    );

    _channel!.stream.listen(
      (data) {
        if (data is! String || data.trim().isEmpty) return;
        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          developer.log('[BackendWs] ← ${json['type'] ?? 'unknown'}');
          _messageController.add(json);
        } catch (_) {}
      },
      onDone: _onSocketClosed,
      onError: (e) {
        developer.log('[BackendWs] Error: $e');
        _onSocketClosed();
      },
      cancelOnError: false,
    );

    _reconnectAttempts = 0;
    _connectionController.add(true);
    developer.log('[BackendWs] Connected to session $_sessionId');
  }

  void _onSocketClosed() {
    _channel = null;
    _connectionController.add(false);

    if (_intentionalClose) return;

    if (_reconnectAttempts < maxReconnectAttempts) {
      _reconnectAttempts++;
      final delay = Duration(seconds: _reconnectAttempts * 2); // 2s, 4s, 6s
      developer.log(
          '[BackendWs] Unexpected close — reconnect #$_reconnectAttempts in ${delay.inSeconds}s');
      Future.delayed(delay, () {
        if (!_intentionalClose) _openSocket();
      });
    } else {
      developer.log('[BackendWs] Max reconnect attempts reached');
      // Emit a sentinel so the provider can react.
      _messageController.add({'type': 'connection_failed'});
    }
  }
}
