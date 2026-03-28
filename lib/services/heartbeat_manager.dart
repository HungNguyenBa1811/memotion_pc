import 'dart:async';

import '../core/constants.dart';

/// Tracks the heartbeat from Android to PC.
///
/// Android sends [heartbeat_ping] every [AppConstants.heartbeatInterval].
/// Call [receivedPing] each time a ping arrives — this resets the timeout.
/// If no ping is received within [AppConstants.heartbeatTimeout], [onTimeout] is called.
class HeartbeatManager {
  final void Function() onTimeout;
  final Duration _timeout;

  Timer? _timeoutTimer;
  bool _running = false;

  HeartbeatManager({
    required this.onTimeout,

    /// Override timeout duration — useful for tests to avoid waiting 20 s.
    Duration? timeout,
  }) : _timeout = timeout ?? AppConstants.heartbeatTimeout;

  void start() {
    if (_running) return;
    _running = true;
    _resetTimer();
  }

  /// Call each time a [heartbeat_ping] is received from Android.
  void receivedPing() {
    if (!_running) return;
    _resetTimer();
  }

  void stop() {
    _running = false;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
  }

  void _resetTimer() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(_timeout, () {
      if (!_running) return;
      stop();
      onTimeout();
    });
  }
}
