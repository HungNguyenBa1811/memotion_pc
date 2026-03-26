import 'dart:convert';

/// QR payload broadcast by PC, scanned by Android.
///
/// JSON format:
/// ```json
/// { "ip": "192.168.1.x", "port": 8765, "token": "...", "expires_at": 1234567890000 }
/// ```
class QrPayload {
  final String ip;
  final int port;
  final String token;
  final int expiresAt; // unix ms

  const QrPayload({
    required this.ip,
    required this.port,
    required this.token,
    required this.expiresAt,
  });

  String toJsonString() => jsonEncode({
        'ip': ip,
        'port': port,
        'token': token,
        'expires_at': expiresAt,
      });

  bool get isExpired => DateTime.now().millisecondsSinceEpoch > expiresAt;
}

/// Message types received from Android.
class AndroidMessageType {
  static const String pairRequest = 'pair_request';
  static const String heartbeatPing = 'heartbeat_ping';
  static const String disconnect = 'disconnect';
}

/// Message types sent to Android.
class PcMessageType {
  static const String pairConfirmed = 'pair_confirmed';
  static const String sessionStarted = 'session_started';
  static const String heartbeatPong = 'heartbeat_pong';
  static const String sessionComplete = 'session_complete';
  static const String sessionFailed = 'session_failed';
}

/// Parsed pair_request received from Android.
class PairRequest {
  final String jwt;
  final String workoutId;
  final String exerciseType;

  const PairRequest({
    required this.jwt,
    required this.workoutId,
    required this.exerciseType,
  });

  factory PairRequest.fromJson(Map<String, dynamic> json) {
    final config = json['session_config'] as Map<String, dynamic>? ?? {};
    return PairRequest(
      jwt: json['jwt'] as String? ?? '',
      workoutId: config['workout_id'] as String? ?? '',
      exerciseType: config['exercise_type'] as String? ?? 'arm_raise',
    );
  }
}

/// PC → Android message builders.
class PcMessages {
  static Map<String, dynamic> pairConfirmed() => {'type': PcMessageType.pairConfirmed};

  static Map<String, dynamic> sessionStarted(String sessionId) => {
        'type': PcMessageType.sessionStarted,
        'session_id': sessionId,
      };

  static Map<String, dynamic> heartbeatPong() => {'type': PcMessageType.heartbeatPong};

  static Map<String, dynamic> sessionComplete() => {'type': PcMessageType.sessionComplete};

  static Map<String, dynamic> sessionFailed(String message) => {
        'type': PcMessageType.sessionFailed,
        'message': message,
      };
}
