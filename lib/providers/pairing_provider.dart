import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/pairing_models.dart';
import '../models/pose_result.dart';
import '../models/session_models.dart';
import '../providers/camera_provider.dart';
import '../providers/settings_provider.dart';
import '../services/backend_ws_service.dart';
import '../services/camera_service.dart';
import '../services/heartbeat_manager.dart';
import '../services/lan_service.dart';
import '../services/local_ws_server.dart';
import '../services/pairing_token_service.dart';

// ── State ────────────────────────────────────────────────────────────────────

enum PairingStatus {
  idle,
  starting,       // Starting local WS server
  awaitingPairing, // Server up, waiting for Android to connect and pair
  paired,         // pair_request validated, pair_confirmed sent
  sessionActive,  // Backend session started, forwarded session_id to Android
  sessionComplete,
  error,
  disconnected,
}

class PairingState {
  final PairingStatus status;
  final String? lanIp;
  final int? wsPort;
  final String? qrToken;
  final int? tokenExpiryMs;
  final SessionConfig? sessionConfig;
  final String? sessionId;
  final SessionResult? sessionResult;
  final String? errorMessage;
  final PoseResult? poseResult;   // latest real-time result from backend
  final bool cameraReady;         // camera successfully initialized

  const PairingState({
    this.status = PairingStatus.idle,
    this.lanIp,
    this.wsPort,
    this.qrToken,
    this.tokenExpiryMs,
    this.sessionConfig,
    this.sessionId,
    this.sessionResult,
    this.errorMessage,
    this.poseResult,
    this.cameraReady = false,
  });

  bool get isQrReady =>
      lanIp != null && wsPort != null && qrToken != null && tokenExpiryMs != null;

  bool get isTokenExpired =>
      tokenExpiryMs != null &&
      PairingTokenService.isExpired(tokenExpiryMs!);

  QrPayload? get qrPayload {
    if (!isQrReady) return null;
    return QrPayload(
      ip: lanIp!,
      port: wsPort!,
      token: qrToken!,
      expiresAt: tokenExpiryMs!,
    );
  }

  PairingState copyWith({
    PairingStatus? status,
    String? lanIp,
    int? wsPort,
    String? qrToken,
    int? tokenExpiryMs,
    SessionConfig? sessionConfig,
    String? sessionId,
    SessionResult? sessionResult,
    String? errorMessage,
    PoseResult? poseResult,
    bool? cameraReady,
    bool clearError = false,
    bool clearSession = false,
    bool clearPoseResult = false,
  }) {
    return PairingState(
      status: status ?? this.status,
      lanIp: lanIp ?? this.lanIp,
      wsPort: wsPort ?? this.wsPort,
      qrToken: qrToken ?? this.qrToken,
      tokenExpiryMs: tokenExpiryMs ?? this.tokenExpiryMs,
      sessionConfig: clearSession ? null : (sessionConfig ?? this.sessionConfig),
      sessionId: clearSession ? null : (sessionId ?? this.sessionId),
      sessionResult: clearSession ? null : (sessionResult ?? this.sessionResult),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      poseResult: clearPoseResult ? null : (poseResult ?? this.poseResult),
      cameraReady: cameraReady ?? this.cameraReady,
    );
  }
}

// ── Notifier ─────────────────────────────────────────────────────────────────

class PairingNotifier extends StateNotifier<PairingState> {
  final Ref _ref;
  final LocalWsServer _localServer = LocalWsServer();
  final BackendWsService _backendWs = BackendWsService();
  final CameraService _camera = CameraService();
  HeartbeatManager? _heartbeat;

  StreamSubscription<Map<String, dynamic>>? _messageSub;
  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<Map<String, dynamic>>? _backendMsgSub;
  StreamSubscription<Uint8List>? _previewSub; // feeds cameraPreviewProvider
  StreamSubscription<Uint8List>? _frameSub;   // feeds BackendWsService
  Timer? _tokenRefreshTimer;

  PairingNotifier(this._ref) : super(const PairingState());

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Starts the local WS server and generates the initial QR payload.
  /// Also initialises the webcam so it's ready when session starts.
  Future<void> startServer() async {
    if (state.status == PairingStatus.starting ||
        state.status == PairingStatus.awaitingPairing) {
      return;
    }

    state = state.copyWith(status: PairingStatus.starting);

    try {
      final ip = await LanService.getLocalIp();
      final port = await _localServer.start();
      _generateToken(ip: ip, port: port);
      _listenToServer();
      state = state.copyWith(
        status: PairingStatus.awaitingPairing,
        lanIp: ip,
        wsPort: port,
      );
      developer.log('[Pairing] Server ready at $ip:$port');

      // Initialise camera in background — non-blocking
      _initCamera();
    } catch (e) {
      state = state.copyWith(
        status: PairingStatus.error,
        errorMessage: 'Failed to start server: $e',
      );
    }
  }

  /// Refreshes the QR token without restarting the server.
  void refreshToken() {
    if (state.lanIp == null || state.wsPort == null) return;
    _generateToken(ip: state.lanIp!, port: state.wsPort!);
  }

  /// Ends the current session gracefully:
  /// stops frame pipe → fetches final result → notifies Android → updates state.
  /// [state.sessionResult] is populated so ResultScreen can display stats.
  Future<void> endSession() async {
    _frameSub?.cancel();
    _frameSub = null;
    _heartbeat?.stop();
    _heartbeat = null;

    // Capture before disconnect clears them.
    final sessionId = state.sessionId;
    final jwt = state.sessionConfig?.jwt;

    await _backendWs.disconnect();

    // Fetch final result — non-fatal if it fails.
    SessionResult? result;
    if (sessionId != null && jwt != null) {
      try {
        result = await _backendWs.fetchResult(
            sessionId: sessionId, jwt: jwt);
        developer.log(
            '[Pairing] Result: ${result.reps} reps, score ${result.score}');
      } catch (e) {
        developer.log('[Pairing] fetchResult failed (non-fatal): $e');
      }
    }

    _localServer.send(PcMessages.sessionComplete());
    _localServer.kickClient();

    // Keep sessionResult in state — ResultScreen reads it.
    // reset() will clear everything when the user starts a new session.
    state = state.copyWith(
      status: PairingStatus.sessionComplete,
      sessionResult: result,
      clearPoseResult: true,
    );
  }

  /// Full reset — stops server and goes back to idle.
  Future<void> reset() async {
    _tokenRefreshTimer?.cancel();
    _messageSub?.cancel();
    _connectionSub?.cancel();
    _backendMsgSub?.cancel();
    _previewSub?.cancel();
    _previewSub = null;
    _frameSub?.cancel();
    _frameSub = null;
    _heartbeat?.stop();
    _heartbeat = null;
    await _backendWs.disconnect();
    await _localServer.stop();
    _ref.read(cameraPreviewProvider.notifier).state = null;
    state = const PairingState();
  }

  @override
  void dispose() {
    reset();
    _camera.dispose();
    super.dispose();
  }

  // ── Private ─────────────────────────────────────────────────────────────────

  Future<void> _initCamera() async {
    if (_camera.isInitialized) {
      state = state.copyWith(cameraReady: true);
      return;
    }
    try {
      final cameraIndex = _ref.read(settingsProvider).cameraIndex;
      await _camera.init(cameraIndex: cameraIndex);
      // Feed preview frames continuously (even before session starts).
      _previewSub?.cancel();
      _previewSub = _camera.frameStream.listen((jpeg) {
        _ref.read(cameraPreviewProvider.notifier).state = jpeg;
      });
      state = state.copyWith(cameraReady: true);
      developer.log('[Camera] Ready');
    } catch (e) {
      developer.log('[Camera] Init failed: $e');
      state = state.copyWith(cameraReady: false, errorMessage: 'Camera: $e');
    }
  }

  void _generateToken({required String ip, required int port}) {
    _tokenRefreshTimer?.cancel();
    final token = PairingTokenService.generateToken();
    final expiry = PairingTokenService.generateExpiryMs();
    state = state.copyWith(
      qrToken: token,
      tokenExpiryMs: expiry,
      lanIp: ip,
      wsPort: port,
    );
    const refreshBuffer = Duration(seconds: 30);
    final refreshIn = Duration(
      milliseconds: expiry - DateTime.now().millisecondsSinceEpoch,
    ) - refreshBuffer;
    if (refreshIn > Duration.zero) {
      _tokenRefreshTimer = Timer(refreshIn, refreshToken);
    }
  }

  void _listenToServer() {
    _messageSub?.cancel();
    _connectionSub?.cancel();

    _messageSub = _localServer.messages.listen(_handleMessage);
    _connectionSub = _localServer.connectionState.listen((connected) {
      if (!connected && state.status == PairingStatus.sessionActive) {
        developer.log('[Pairing] Android disconnected mid-session');
        _onAndroidDisconnected();
      }
    });
  }

  void _handleMessage(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;
    developer.log('[Pairing] Handling message: $type');

    switch (type) {
      case AndroidMessageType.pairRequest:
        _handlePairRequest(msg);
      case AndroidMessageType.heartbeatPing:
        _localServer.send(PcMessages.heartbeatPong());
        _heartbeat?.receivedPong();
      case AndroidMessageType.disconnect:
        _onAndroidDisconnected();
    }
  }

  Future<void> _handlePairRequest(Map<String, dynamic> msg) async {
    if (state.isTokenExpired) {
      _localServer.send(PcMessages.sessionFailed('QR code expired. Please refresh.'));
      return;
    }

    final request = PairRequest.fromJson(msg);
    // TODO(jwt): re-enable when backend auth is live.
    // if (request.jwt.isEmpty) {
    //   _localServer.send(PcMessages.sessionFailed('Missing JWT.'));
    //   return;
    // }

    state = state.copyWith(
      status: PairingStatus.paired,
      sessionConfig: SessionConfig(
        jwt: request.jwt,
        workoutId: request.workoutId,
        exerciseType: request.exerciseType,
      ),
    );

    _localServer.send(PcMessages.pairConfirmed());
    developer.log('[Pairing] Paired with Android');

    _heartbeat = HeartbeatManager(
      onPingSend: () => _localServer.send(PcMessages.heartbeatPong()),
      onTimeout: _onAndroidDisconnected,
    );
    _heartbeat!.start();

    // Skip backend when using mock workout — backend may not be running.
    if (request.workoutId == 'mock-workout-id') {
      developer.log('[Pairing] Mock mode — skipping backend, sending session_started');
      state = state.copyWith(
        status: PairingStatus.sessionActive,
        sessionId: 'mock-session-id',
      );
      _localServer.send(PcMessages.sessionStarted('mock-session-id'));
      return;
    }

    await _connectToBackend(request);
  }

  Future<void> _connectToBackend(PairRequest request) async {
    // Apply latest settings before every session so URL changes take effect
    // without restarting the app.
    final settings = _ref.read(settingsProvider);
    _backendWs.baseHttpUrl = settings.backendBaseUrl;
    _backendWs.baseWsUrl   = settings.backendWsBase;

    try {
      developer.log('[Pairing] Creating backend session...');
      final sessionId = await _backendWs.createSession(
        jwt: request.jwt,
        workoutId: request.workoutId,
        exerciseType: request.exerciseType,
      );

      await _backendWs.connect(sessionId: sessionId, jwt: request.jwt);

      state = state.copyWith(
        status: PairingStatus.sessionActive,
        sessionId: sessionId,
      );

      _localServer.send(PcMessages.sessionStarted(sessionId));
      developer.log('[Pairing] Session active: $sessionId');

      // Start listening to backend results and piping frames
      _listenToBackend();
      _startFramePipe();
    } catch (e) {
      developer.log('[Pairing] Backend error: $e');
      _localServer.send(PcMessages.sessionFailed('Backend error: $e'));
      state = state.copyWith(
        status: PairingStatus.error,
        errorMessage: 'Backend connection failed: $e',
      );
    }
  }

  /// Subscribes to backend WebSocket messages.
  ///
  /// - `frame_result`      → update live pose stats in state
  /// - `annotated_frame`   → relay to Android so the phone can display skeleton
  /// - `connection_failed` → backend gave up reconnecting; surface as error
  void _listenToBackend() {
    _backendMsgSub?.cancel();
    _backendMsgSub = _backendWs.messages.listen((msg) {
      final type = msg['type'] as String?;
      switch (type) {
        case 'frame_result':
          state = state.copyWith(poseResult: PoseResult.fromJson(msg));
        case 'annotated_frame':
          // Forward annotated JPEG to Android — phone renders skeleton overlay.
          _localServer.send(msg);
        case 'connection_failed':
          developer.log('[Pairing] Backend permanently unreachable');
          _onBackendFailed();
      }
    });
  }

  void _onBackendFailed() {
    _frameSub?.cancel();
    _frameSub = null;
    _heartbeat?.stop();
    _heartbeat = null;
    _localServer.send(PcMessages.sessionFailed('Backend connection lost'));
    _localServer.kickClient();
    state = state.copyWith(
      status: PairingStatus.error,
      errorMessage: 'Backend connection permanently lost',
    );
  }

  /// Pipes webcam frames from [CameraService] to [BackendWsService].
  void _startFramePipe() {
    if (!state.cameraReady) {
      developer.log('[FramePipe] Camera not ready — skipping frame pipe');
      return;
    }
    _frameSub?.cancel();
    _frameSub = _camera.frameStream.listen((jpegBytes) {
      if (state.status == PairingStatus.sessionActive) {
        _backendWs.sendFrame(jpegBytes);
      }
    });
    developer.log('[FramePipe] Started');
  }

  void _onAndroidDisconnected() {
    developer.log('[Pairing] Android disconnected');
    _frameSub?.cancel();
    _frameSub = null;
    _heartbeat?.stop();
    _heartbeat = null;
    _backendWs.disconnect();
    state = state.copyWith(
      status: PairingStatus.disconnected,
      errorMessage: 'Android disconnected',
    );
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final pairingProvider =
    StateNotifierProvider<PairingNotifier, PairingState>((ref) {
  return PairingNotifier(ref);
});
