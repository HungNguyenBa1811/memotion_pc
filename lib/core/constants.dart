/// App-wide constants for memotion_pc Desktop app.
class AppConstants {
  AppConstants._();

  // ── Backend defaults (overridable via SettingsScreen) ──
  static const String defaultBackendHttp = 'http://100.27.167.208:8005';
  static const String defaultBackendWs   = 'ws://100.27.167.208:8005';
  static const String poseSessionsEndpoint = '/api/pose/sessions';

  // ── Local WS Server ──
  static const int wsPortStart = 8765;
  static const int wsPortEnd = 8800;

  // ── Heartbeat ──
  static const Duration heartbeatInterval = Duration(seconds: 5);
  static const Duration heartbeatTimeout = Duration(seconds: 20);

  // ── QR Token ──
  static const Duration qrTokenValidity = Duration(minutes: 10);
}

/// Route paths.
class AppRoutes {
  AppRoutes._();

  static const String qrDisplay = '/';
  static const String exercise = '/exercise';
  static const String result = '/result';
  static const String settings = '/settings';
}
