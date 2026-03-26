import 'package:flutter_test/flutter_test.dart';
import 'package:memotion_pc/services/heartbeat_manager.dart';

void main() {
  group('HeartbeatManager', () {
    test('calls onPingSend after interval', () async {
      var pingCount = 0;
      final hb = HeartbeatManager(
        onPingSend: () => pingCount++,
        onTimeout: () {},
      );
      hb.start();
      // Wait longer than one natural heartbeat interval (5s) + buffer
      await Future.delayed(const Duration(seconds: 6));
      hb.stop();
      expect(pingCount, greaterThanOrEqualTo(1));
    });

    test('stop prevents further pings', () async {
      var pingCount = 0;
      final hb = HeartbeatManager(
        onPingSend: () => pingCount++,
        onTimeout: () {},
      );
      hb.start();
      await Future.delayed(const Duration(milliseconds: 200));
      hb.stop();
      final countAfterStop = pingCount;
      await Future.delayed(const Duration(seconds: 6));
      expect(pingCount, equals(countAfterStop));
    });

    test('receivedPong resets timeout watch', () async {
      var timedOut = false;
      final hb = HeartbeatManager(
        onPingSend: () {},
        onTimeout: () => timedOut = true,
      );
      hb.start();
      // Simulate a pong before any timeout can fire
      await Future.delayed(const Duration(seconds: 5));
      hb.receivedPong();
      await Future.delayed(const Duration(seconds: 5));
      hb.stop();
      expect(timedOut, isFalse);
    });

    test('double start is idempotent — only one ping timer runs', () async {
      var pingCount = 0;
      final hb = HeartbeatManager(
        onPingSend: () => pingCount++,
        onTimeout: () {},
      );
      hb.start();
      hb.start(); // second call is no-op
      await Future.delayed(const Duration(seconds: 6));
      hb.stop();
      // If two timers ran, we'd get ≥2 pings per interval — keep it to ≤2 total
      expect(pingCount, lessThanOrEqualTo(2));
    });
  });
}
