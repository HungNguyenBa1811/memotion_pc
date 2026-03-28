import 'dart:async';
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
  starting, // Starting local WS server
  awaitingPairing, // Server up, waiting for Android to connect and pair
  paired, // pair_request validated, pair_confirmed sent
  sessionActive, // Backend session started, forwarded session_id to Android
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
  final PoseResult? poseResult; // latest real-time result from backend
  final bool cameraReady; // camera successfully initialized
  final int debugFramesSent; // DEBUG: frames piped to backend
  final int debugMsgsReceived; // DEBUG: frame_result msgs from backend
  final String debugLastMsg; // DEBUG: last raw backend message summary

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
    this.debugFramesSent = 0,
    this.debugMsgsReceived = 0,
    this.debugLastMsg = '—',
  });

  bool get isQrReady =>
      lanIp != null &&
      wsPort != null &&
      qrToken != null &&
      tokenExpiryMs != null;

  bool get isTokenExpired =>
      tokenExpiryMs != null && PairingTokenService.isExpired(tokenExpiryMs!);

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
    int? debugFramesSent,
    int? debugMsgsReceived,
    String? debugLastMsg,
  }) {
    return PairingState(
      status: status ?? this.status,
      lanIp: lanIp ?? this.lanIp,
      wsPort: wsPort ?? this.wsPort,
      qrToken: qrToken ?? this.qrToken,
      tokenExpiryMs: tokenExpiryMs ?? this.tokenExpiryMs,
      sessionConfig:
          clearSession ? null : (sessionConfig ?? this.sessionConfig),
      sessionId: clearSession ? null : (sessionId ?? this.sessionId),
      sessionResult:
          clearSession ? null : (sessionResult ?? this.sessionResult),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      poseResult: clearPoseResult ? null : (poseResult ?? this.poseResult),
      cameraReady: cameraReady ?? this.cameraReady,
      debugFramesSent: debugFramesSent ?? this.debugFramesSent,
      debugMsgsReceived: debugMsgsReceived ?? this.debugMsgsReceived,
      debugLastMsg: debugLastMsg ?? this.debugLastMsg,
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
  StreamSubscription<Uint8List>? _frameSub; // feeds BackendWsService
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
        result = await _backendWs.fetchResult(sessionId: sessionId, jwt: jwt);
      } catch (e) {}

      // Mark task complete on backend before notifying Android.
      final workoutId = state.sessionConfig?.workoutId;
      if (workoutId != null && workoutId.isNotEmpty) {
        try {
          await _backendWs.markTaskCompleted(workoutId: workoutId, jwt: jwt);
        } catch (e) {}
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
      // Camera already initialized — restart preview sub (cancelled by reset()).
      _previewSub?.cancel();
      _previewSub = _camera.frameStream.listen((jpeg) {
        _ref.read(cameraPreviewProvider.notifier).state = jpeg;
      });
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
    } catch (e) {
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
        ) -
        refreshBuffer;
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
        _onAndroidDisconnected();
      }
    });
  }

  void _handleMessage(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;

    switch (type) {
      case AndroidMessageType.pairRequest:
        _handlePairRequest(msg);
      case AndroidMessageType.heartbeatPing:
        _localServer.send(PcMessages.heartbeatPong());
        _heartbeat?.receivedPing();
      case AndroidMessageType.disconnect:
        _onAndroidDisconnected();
    }
  }

  Future<void> _handlePairRequest(Map<String, dynamic> msg) async {
    if (state.isTokenExpired) {
      _localServer
          .send(PcMessages.sessionFailed('QR code expired. Please refresh.'));
      return;
    }

    final request = PairRequest.fromJson(msg);
    if (request.jwt.isEmpty) {
      _localServer.send(PcMessages.sessionFailed('Missing JWT.'));
      return;
    }

    state = state.copyWith(
      status: PairingStatus.paired,
      sessionConfig: SessionConfig(
        jwt: request.jwt,
        workoutId: request.workoutId,
        exerciseType: request.exerciseType,
        videoUrl: request.videoUrl, // full URL if mobile sends it
      ),
    );

    _localServer.send(PcMessages.pairConfirmed());

    _heartbeat = HeartbeatManager(onTimeout: _onAndroidDisconnected);
    _heartbeat!.start();

    await _connectToBackend(request);
  }

  Future<void> _connectToBackend(PairRequest request) async {
    // Apply latest settings before every session so URL changes take effect
    // without restarting the app.
    final settings = _ref.read(settingsProvider);
    _backendWs.baseHttpUrl = settings.backendBaseUrl;
    _backendWs.baseWsUrl = settings.backendWsBase;

    try {
      // Fetch video path in parallel with session creation — non-fatal if fails.
      final results = await Future.wait([
        _backendWs.createSession(
          jwt: request.jwt,
          workoutId: request.workoutId,
          exerciseType: request.exerciseType,
        ),
        _backendWs
            .fetchWorkoutVideoPath(
              workoutId: request.workoutId,
              jwt: request.jwt,
            )
            .catchError((_) => null),
      ]);

      final sessionId =
          results[0]!; // non-null: createSession always returns String
      final videoPath = results[1]; // String? from fetchWorkoutVideoPath

      await _backendWs.connect(sessionId: sessionId, jwt: request.jwt);

      // Priority: video_url from pair_request (mobile sends full URL).
      // Fallback: build URL from fetched videoPath (relative path from API).
      final existingVideoUrl = state.sessionConfig?.videoUrl;
      final resolvedVideoUrl = existingVideoUrl?.isNotEmpty == true
          ? existingVideoUrl
          : (videoPath != null && videoPath.isNotEmpty)
              ? '${_backendWs.baseHttpUrl}$videoPath'
              : null;

      state = state.copyWith(
        status: PairingStatus.sessionActive,
        sessionId: sessionId,
        sessionConfig: state.sessionConfig?.copyWith(
          videoPath: videoPath,
          videoUrl: resolvedVideoUrl,
        ),
      );

      _localServer.send(PcMessages.sessionStarted(sessionId));

      // Start listening to backend results and piping frames
      _listenToBackend();
      _startFramePipe();
    } catch (e) {
      _localServer.send(PcMessages.sessionFailed('Backend error: $e'));
      state = state.copyWith(
        status: PairingStatus.error,
        errorMessage: 'Backend connection failed: $e',
      );
    }
  }

  /// Subscribes to backend WebSocket messages.
  ///
  /// Backend message routing (real protocol — no generic 'type' field on frames):
  /// - `event: session_completed` → trigger session end
  /// - `error` key present        → log and surface in debug overlay
  /// - `phase` key present        → frame result → update [PoseResult]
  /// - `type: annotated_frame`    → relay skeleton to Android
  /// - `type: connection_failed`  → internal sentinel from [BackendWsService]
  void _listenToBackend() {
    _backendMsgSub?.cancel();
    _backendMsgSub = _backendWs.messages.listen(
      (msg) {
        // 1. session_completed event — one-time signal from backend
        if (msg['event'] == 'session_completed') {
          state = state.copyWith(
            poseResult: PoseResult.fromJson({'phase': 5}),
            debugLastMsg: 'event=session_completed',
          );
          return;
        }

        // 2. Internal sentinel: BackendWsService max-reconnect exhausted
        if (msg['type'] == 'connection_failed') {
          state = state.copyWith(debugLastMsg: 'connection_failed');
          _onBackendFailed();
          return;
        }

        // 3. annotated_frame — relay skeleton overlay to Android
        if (msg['type'] == 'annotated_frame') {
          _localServer.send(msg);
          return;
        }

        // 4. Error message: {"error": "...", "code": "..."}
        if (msg.containsKey('error')) {
          final errMsg = msg['error'] ?? '';
          final errCode = msg['code'] ?? '';
          state =
              state.copyWith(debugLastMsg: 'ERROR code=$errCode msg=$errMsg');
          return;
        }

        // 5. Frame result — identified by presence of 'phase' int field.
        //    Backend does NOT use a generic 'type' field on these messages.
        if (msg.containsKey('phase')) {
          final n = state.debugMsgsReceived + 1;
          final phase = msg['phase'];
          final phaseName = msg['phase_name'] ?? '?';
          final fps = msg['fps']?.toStringAsFixed(1) ?? '-';
          state = state.copyWith(
            poseResult: PoseResult.fromJson(msg),
            debugMsgsReceived: n,
            debugLastMsg: '#$n ph=$phase($phaseName) fps=$fps',
          );
          return;
        }

        // 6. Unknown
        state =
            state.copyWith(debugLastMsg: 'unknown keys=${msg.keys.toList()}');
      },
      onError: (e) {
        state = state.copyWith(debugLastMsg: 'ERROR: $e');
      },
      onDone: () {
        state = state.copyWith(debugLastMsg: 'stream closed');
      },
    );
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
      state =
          state.copyWith(debugLastMsg: 'FramePipe SKIPPED: camera not ready');
      return;
    }
    _frameSub?.cancel();
    _frameSub = _camera.frameStream.listen((jpegBytes) {
      if (state.status == PairingStatus.sessionActive) {
        _backendWs.sendFrame(jpegBytes);
        final n = state.debugFramesSent + 1;
        // Update counter every 30 frames to avoid excessive rebuilds
        if (n % 30 == 0) {
          state = state.copyWith(debugFramesSent: n);
        }
      }
    });
  }

  void _onAndroidDisconnected() {
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
