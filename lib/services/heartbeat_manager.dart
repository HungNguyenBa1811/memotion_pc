import 'dart:async';
import 'dart:developer' as developer;

import '../core/constants.dart';

/// Manages the ping/pong heartbeat between PC and Android.
///
/// PC sends a ping every [AppConstants.heartbeatInterval].
/// If no pong is received within [AppConstants.heartbeatTimeout], [onTimeout] is called.
class HeartbeatManager {
  final void Function() onPingSend;
  final void Function() onTimeout;

  Timer? _pingTimer;
  Timer? _timeoutTimer;
  bool _running = false;

  HeartbeatManager({required this.onPingSend, required this.onTimeout});

  void start() {
    if (_running) return;
    _running = true;
    developer.log('[Heartbeat] Started');
    _schedulePing();
  }

  /// Called when a pong is received from Android.
  void receivedPong() {
    if (!_running) return;
    developer.log('[Heartbeat] Pong received');
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
  }

  void stop() {
    _running = false;
    _pingTimer?.cancel();
    _timeoutTimer?.cancel();
    _pingTimer = null;
    _timeoutTimer = null;
    developer.log('[Heartbeat] Stopped');
  }

  void _schedulePing() {
    _pingTimer = Timer(AppConstants.heartbeatInterval, () {
      if (!_running) return;
      developer.log('[Heartbeat] Ping →');
      onPingSend();
      _startTimeoutWatch();
      _schedulePing(); // schedule next
    });
  }

  void _startTimeoutWatch() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(AppConstants.heartbeatTimeout, () {
      if (!_running) return;
      developer.log('[Heartbeat] Timeout — no pong');
      stop();
      onTimeout();
    });
  }
}
