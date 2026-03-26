import 'dart:convert';
import 'dart:math';

import '../core/constants.dart';

/// Generates and validates the one-time pairing token embedded in the QR code.
///
/// The token is a cryptographically random 32-byte value encoded as base64url.
/// PC stores the active token in memory and validates it against the value
/// received in Android's [pair_request] message.
class PairingTokenService {
  /// Generates a new random token.
  static String generateToken() {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// Returns the expiry timestamp in Unix milliseconds (now + 10 min).
  static int generateExpiryMs() {
    return DateTime.now()
        .add(AppConstants.qrTokenValidity)
        .millisecondsSinceEpoch;
  }

  /// Returns true if the timestamp has passed.
  static bool isExpired(int expiresAtMs) {
    return DateTime.now().millisecondsSinceEpoch > expiresAtMs;
  }

  /// Returns true if [received] matches [expected] (constant-time compare).
  static bool validateToken(String expected, String received) {
    if (expected.length != received.length) return false;
    var diff = 0;
    for (var i = 0; i < expected.length; i++) {
      diff |= expected.codeUnitAt(i) ^ received.codeUnitAt(i);
    }
    return diff == 0;
  }
}
