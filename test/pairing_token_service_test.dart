import 'package:flutter_test/flutter_test.dart';
import 'package:memotion_pc/services/pairing_token_service.dart';

void main() {
  group('PairingTokenService', () {
    test('generateToken returns a non-empty string', () {
      final token = PairingTokenService.generateToken();
      expect(token, isNotEmpty);
    });

    test('generateToken returns different tokens each call', () {
      final t1 = PairingTokenService.generateToken();
      final t2 = PairingTokenService.generateToken();
      expect(t1, isNot(equals(t2)));
    });

    test('generated token is at least 40 chars (32 bytes base64url)', () {
      final token = PairingTokenService.generateToken();
      // 32 bytes → ~43 base64url chars
      expect(token.length, greaterThanOrEqualTo(40));
    });

    test('generateExpiryMs returns a future timestamp', () {
      final before = DateTime.now().millisecondsSinceEpoch;
      final expiry = PairingTokenService.generateExpiryMs();
      expect(expiry, greaterThan(before));
    });

    test('generateExpiryMs is approximately 10 minutes in the future', () {
      final expiry = PairingTokenService.generateExpiryMs();
      final now = DateTime.now().millisecondsSinceEpoch;
      final diffMinutes = (expiry - now) / 60000;
      expect(diffMinutes, closeTo(10.0, 0.1));
    });

    test('isExpired returns false for future timestamp', () {
      final future = DateTime.now()
          .add(const Duration(minutes: 5))
          .millisecondsSinceEpoch;
      expect(PairingTokenService.isExpired(future), isFalse);
    });

    test('isExpired returns true for past timestamp', () {
      final past = DateTime.now()
          .subtract(const Duration(minutes: 1))
          .millisecondsSinceEpoch;
      expect(PairingTokenService.isExpired(past), isTrue);
    });

    test('validateToken returns true for equal tokens', () {
      const token = 'abc123';
      expect(PairingTokenService.validateToken(token, token), isTrue);
    });

    test('validateToken returns false for different tokens', () {
      expect(
        PairingTokenService.validateToken('abc123', 'xyz789'),
        isFalse,
      );
    });

    test('validateToken returns false for different lengths', () {
      expect(
        PairingTokenService.validateToken('short', 'much-longer-token'),
        isFalse,
      );
    });
  });
}
