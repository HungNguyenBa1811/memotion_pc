import 'package:flutter_test/flutter_test.dart';
import 'package:memotion_pc/services/heartbeat_manager.dart';

void main() {
  group('HeartbeatManager', () {
    // Short timeout so tests finish in milliseconds, not 20 s.
    const short = Duration(milliseconds: 200);

    test('fires onTimeout when no ping is received', () async {
      var timedOut = false;
      final hb = HeartbeatManager(onTimeout: () => timedOut = true, timeout: short);
      hb.start();
      await Future.delayed(short + const Duration(milliseconds: 50));
      expect(timedOut, isTrue);
    });

    test('receivedPing resets timer — no timeout fires', () async {
      var timedOut = false;
      final hb = HeartbeatManager(onTimeout: () => timedOut = true, timeout: short);
      hb.start();
      for (var i = 0; i < 5; i++) {
        await Future.delayed(const Duration(milliseconds: 80));
        hb.receivedPing();
      }
      hb.stop();
      expect(timedOut, isFalse);
    });

    test('stop before timeout — onTimeout never fires', () async {
      var timedOut = false;
      final hb = HeartbeatManager(onTimeout: () => timedOut = true, timeout: short);
      hb.start();
      hb.stop();
      await Future.delayed(short + const Duration(milliseconds: 50));
      expect(timedOut, isFalse);
    });

    test('double start is idempotent — only one timeout fires', () async {
      var callCount = 0;
      final hb = HeartbeatManager(onTimeout: () => callCount++, timeout: short);
      hb.start();
      hb.start(); // no-op
      await Future.delayed(short + const Duration(milliseconds: 50));
      expect(callCount, equals(1));
    });

    test('receivedPing after stop does not crash', () {
      final hb = HeartbeatManager(onTimeout: () {}, timeout: short);
      hb.start();
      hb.stop();
      expect(() => hb.receivedPing(), returnsNormally);
    });

    test('timeout rearms after receivedPing — fires if pings stop', () async {
      var timedOut = false;
      final hb = HeartbeatManager(onTimeout: () => timedOut = true, timeout: short);
      hb.start();
      await Future.delayed(const Duration(milliseconds: 80));
      hb.receivedPing(); // reset once…
      // …then stop pinging — timeout must still fire
      await Future.delayed(short + const Duration(milliseconds: 50));
      expect(timedOut, isTrue);
    });
  });
}
