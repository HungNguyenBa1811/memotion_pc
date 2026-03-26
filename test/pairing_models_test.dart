import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:memotion_pc/models/pairing_models.dart';

void main() {
  group('QrPayload', () {
    test('toJsonString serializes correctly', () {
      const payload = QrPayload(
        ip: '192.168.1.100',
        port: 8765,
        token: 'test_token',
        expiresAt: 9999999999999,
      );
      final json = jsonDecode(payload.toJsonString()) as Map<String, dynamic>;
      expect(json['ip'], equals('192.168.1.100'));
      expect(json['port'], equals(8765));
      expect(json['token'], equals('test_token'));
      expect(json['expires_at'], equals(9999999999999));
    });

    test('isExpired returns false for far future', () {
      const payload = QrPayload(
        ip: '192.168.1.1',
        port: 8765,
        token: 'tok',
        expiresAt: 9999999999999,
      );
      expect(payload.isExpired, isFalse);
    });

    test('isExpired returns true for past timestamp', () {
      const payload = QrPayload(
        ip: '192.168.1.1',
        port: 8765,
        token: 'tok',
        expiresAt: 1,
      );
      expect(payload.isExpired, isTrue);
    });
  });

  group('PairRequest', () {
    test('fromJson parses correctly', () {
      final json = {
        'type': 'pair_request',
        'jwt': 'test.jwt.token',
        'session_config': {
          'workout_id': 'w123',
          'exercise_type': 'arm_raise',
        },
      };
      final req = PairRequest.fromJson(json);
      expect(req.jwt, equals('test.jwt.token'));
      expect(req.workoutId, equals('w123'));
      expect(req.exerciseType, equals('arm_raise'));
    });

    test('fromJson uses defaults for missing fields', () {
      final json = {'type': 'pair_request', 'jwt': 'tok'};
      final req = PairRequest.fromJson(json);
      expect(req.workoutId, equals(''));
      expect(req.exerciseType, equals('arm_raise'));
    });
  });

  group('PcMessages', () {
    test('pairConfirmed has correct type', () {
      expect(PcMessages.pairConfirmed()['type'], equals('pair_confirmed'));
    });

    test('sessionStarted includes session_id', () {
      final msg = PcMessages.sessionStarted('sess_abc');
      expect(msg['type'], equals('session_started'));
      expect(msg['session_id'], equals('sess_abc'));
    });

    test('sessionFailed includes message', () {
      final msg = PcMessages.sessionFailed('Backend error');
      expect(msg['type'], equals('session_failed'));
      expect(msg['message'], equals('Backend error'));
    });

    test('heartbeatPong has correct type', () {
      expect(PcMessages.heartbeatPong()['type'], equals('heartbeat_pong'));
    });
  });
}
