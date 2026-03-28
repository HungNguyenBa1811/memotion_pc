import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:memotion_pc/services/backend_ws_service.dart';

void main() {
  late BackendWsService service;
  late Dio dio;
  late DioAdapter adapter;

  const baseUrl = 'http://test.local';
  const jwt = 'test.jwt.token';

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: baseUrl));
    // UrlRequestMatcher matches on path + method only — ignores body/headers,
    // which makes tests independent of request payload details.
    adapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher(matchMethod: true));
    service = BackendWsService()
      ..baseHttpUrl = baseUrl
      ..dioOverride = dio;
  });

  tearDown(() {
    service.dispose();
  });

  // ── createSession ──────────────────────────────────────────────────────────

  group('createSession', () {
    test('returns session_id from flat response', () async {
      adapter.onPost(
        '/api/pose/sessions',
        (server) => server.reply(200, {'session_id': 'sess_001'}),
      );
      final id = await service.createSession(
        jwt: jwt,
        workoutId: 'w1',
        exerciseType: 'arm_raise',
      );
      expect(id, equals('sess_001'));
    });

    test('returns session_id from nested data wrapper', () async {
      adapter.onPost(
        '/api/pose/sessions',
        (server) => server.reply(200, {'data': {'session_id': 'sess_002'}}),
      );
      final id = await service.createSession(
        jwt: jwt,
        workoutId: 'w2',
        exerciseType: 'yoga',
      );
      expect(id, equals('sess_002'));
    });
  });

  // ── fetchResult (DELETE) ───────────────────────────────────────────────────

  group('fetchResult', () {
    test('parses SessionResult from DELETE response', () async {
      adapter.onDelete(
        '/api/pose/sessions/sess_abc',
        (server) => server.reply(200, {
          'session_id': 'sess_abc',
          'duration_seconds': 90,
          'reps': 12,
          'score': 0.88,
          'summary': 'Good session',
        }),
      );
      final result = await service.fetchResult(
        sessionId: 'sess_abc',
        jwt: jwt,
      );
      expect(result.sessionId, equals('sess_abc'));
      expect(result.durationSeconds, equals(90));
      expect(result.reps, equals(12));
      expect(result.score, closeTo(0.88, 0.001));
      expect(result.summary, equals('Good session'));
    });

    test('parses SessionResult from nested data wrapper', () async {
      adapter.onDelete(
        '/api/pose/sessions/sess_xyz',
        (server) => server.reply(200, {
          'data': {
            'session_id': 'sess_xyz',
            'duration_seconds': 60,
            'reps': 8,
            'score': 0.72,
          },
        }),
      );
      final result = await service.fetchResult(
        sessionId: 'sess_xyz',
        jwt: jwt,
      );
      expect(result.reps, equals(8));
      expect(result.score, closeTo(0.72, 0.001));
    });
  });

  // ── markTaskCompleted ──────────────────────────────────────────────────────

  group('markTaskCompleted', () {
    test('completes without throwing on 200', () async {
      adapter.onPut(
        '/api/tasks/w123/complete',
        (server) => server.reply(200, {'status': 'ok'}),
      );
      await expectLater(
        service.markTaskCompleted(workoutId: 'w123', jwt: jwt),
        completes,
      );
    });

    test('throws DioException on 4xx', () async {
      adapter.onPut(
        '/api/tasks/bad_id/complete',
        (server) => server.reply(404, {'error': 'not found'}),
      );
      await expectLater(
        service.markTaskCompleted(workoutId: 'bad_id', jwt: jwt),
        throwsA(isA<DioException>()),
      );
    });
  });

  // ── fetchWorkoutVideoPath ──────────────────────────────────────────────────

  group('fetchWorkoutVideoPath', () {
    test('returns video_path from flat response', () async {
      adapter.onGet(
        '/api/tasks/w1',
        (server) => server.reply(200, {
          'video_path': '/videos/arm_raise.mp4',
        }),
      );
      final path = await service.fetchWorkoutVideoPath(
        workoutId: 'w1',
        jwt: jwt,
      );
      expect(path, equals('/videos/arm_raise.mp4'));
    });

    test('returns video_path from nested data wrapper', () async {
      adapter.onGet(
        '/api/tasks/w2',
        (server) => server.reply(200, {
          'data': {'video_path': '/videos/yoga.mp4'},
        }),
      );
      final path = await service.fetchWorkoutVideoPath(
        workoutId: 'w2',
        jwt: jwt,
      );
      expect(path, equals('/videos/yoga.mp4'));
    });

    test('returns null when video_path field is absent', () async {
      adapter.onGet(
        '/api/tasks/w3',
        (server) => server.reply(200, {'title': 'Arm Raise'}),
      );
      final path = await service.fetchWorkoutVideoPath(
        workoutId: 'w3',
        jwt: jwt,
      );
      expect(path, isNull);
    });
  });
}
