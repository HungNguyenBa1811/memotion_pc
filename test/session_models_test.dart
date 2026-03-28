import 'package:flutter_test/flutter_test.dart';
import 'package:memotion_pc/models/pose_result.dart';
import 'package:memotion_pc/models/session_models.dart';

void main() {
  // ── SessionResult ──────────────────────────────────────────────────────────

  group('SessionResult.fromJson', () {
    test('parses all fields correctly', () {
      final result = SessionResult.fromJson({
        'session_id': 'sess_abc',
        'duration_seconds': 120,
        'reps': 15,
        'score': 0.87,
        'summary': 'Great form overall',
      });
      expect(result.sessionId, equals('sess_abc'));
      expect(result.durationSeconds, equals(120));
      expect(result.reps, equals(15));
      expect(result.score, closeTo(0.87, 0.001));
      expect(result.summary, equals('Great form overall'));
    });

    test('uses defaults for missing fields', () {
      final result = SessionResult.fromJson({});
      expect(result.sessionId, equals(''));
      expect(result.durationSeconds, equals(0));
      expect(result.reps, equals(0));
      expect(result.score, equals(0.0));
      expect(result.summary, isNull);
    });

    test('parses score from int field', () {
      final result = SessionResult.fromJson({'score': 1});
      expect(result.score, equals(1.0));
    });

    test('unwraps nested data wrapper', () {
      // Backend sometimes wraps: { "data": { ... } }
      final inner = {
        'session_id': 'sess_xyz',
        'duration_seconds': 60,
        'reps': 10,
        'score': 0.75,
      };
      // fromJson works on the inner map — caller must unwrap
      final result = SessionResult.fromJson(inner);
      expect(result.sessionId, equals('sess_xyz'));
    });
  });

  // ── SessionConfig ──────────────────────────────────────────────────────────

  group('SessionConfig', () {
    const base = SessionConfig(
      jwt: 'jwt.token',
      workoutId: 'w1',
      exerciseType: 'arm_raise',
    );

    test('videoPath is null by default', () {
      expect(base.videoPath, isNull);
    });

    test('copyWith sets videoPath', () {
      final updated = base.copyWith(videoPath: '/videos/arm_raise.mp4');
      expect(updated.videoPath, equals('/videos/arm_raise.mp4'));
      expect(updated.jwt, equals(base.jwt));
      expect(updated.workoutId, equals(base.workoutId));
      expect(updated.exerciseType, equals(base.exerciseType));
    });

    test('copyWith without arg preserves existing videoPath', () {
      const withVideo = SessionConfig(
        jwt: 'j',
        workoutId: 'w',
        exerciseType: 'yoga',
        videoPath: '/videos/yoga.mp4',
      );
      final copy = withVideo.copyWith();
      expect(copy.videoPath, equals('/videos/yoga.mp4'));
    });
  });

  // ── PoseResult ─────────────────────────────────────────────────────────────

  // Protocol: each phase uses a named key, NOT a generic "data" key.
  // phase 1 → 'detection', phase 2 → 'calibration', phase 3 → 'sync',
  // phase 4 → 'final_report', phase 5 → completed (no data).

  group('PoseResult.fromJson', () {
    test('phase 3 (sync/training) — parses rep_count, current_score, fatigue', () {
      final r = PoseResult.fromJson({
        'phase': 3,
        'phase_name': 'sync',
        'message': 'Keep back straight',
        'timestamp': 1711612800.5, // float seconds
        'sync': {
          'rep_count': 5,
          'current_score': 92.0,
          'fatigue_level': 'low',
        },
      });
      expect(r.phase, equals(PosePhase.sync));
      expect(r.phaseName, equals('sync'));
      expect(r.message, equals('Keep back straight'));
      expect(r.repCount, equals(5));
      expect(r.currentScore, closeTo(92.0, 0.01));
      expect(r.fatigueLevel, equals('low'));
      // float seconds → ms
      expect(r.timestamp, equals(1711612800500));
    });

    test('phase 4 (final_report) — parses scores and grade', () {
      final r = PoseResult.fromJson({
        'phase': 4,
        'phase_name': 'scoring',
        'final_report': {
          'total_score': 85.5,
          'rom_score': 80.0,
          'stability_score': 90.0,
          'flow_score': 86.5,
          'grade': 'B+',
        },
      });
      expect(r.phase, equals(PosePhase.scoring));
      expect(r.totalScore, closeTo(85.5, 0.01));
      expect(r.grade, equals('B+'));
    });

    test('phase 1 (detection) — parses detection key', () {
      final r = PoseResult.fromJson({
        'phase': 1,
        'phase_name': 'detection',
        'detection': {
          'pose_detected': true,
          'stable_count': 7,
          'progress': 0.6,
        },
      });
      expect(r.phase, equals(PosePhase.detection));
      expect(r.poseDetected, isTrue);
      expect(r.stableCount, equals(7));
      expect(r.progress, closeTo(0.6, 0.001));
    });

    test('phase 2 (calibration) — parses calibration key', () {
      final r = PoseResult.fromJson({
        'phase': 2,
        'calibration': {
          'current_joint': 'left_shoulder',
          'current_joint_name': 'Vai trái',
          'current_angle': 145.3,
          'user_max_angle': 170.0,
          'progress': 0.62,
          'queue_index': 1,
          'total_joints': 4,
          'overall_progress': 0.25,
          'position_instruction': 'Giơ tay lên cao hơn',
          'countdown_remaining': 2.1,
        },
      });
      expect(r.phase, equals(PosePhase.calibration));
      expect(r.currentJoint, equals('left_shoulder'));
      expect(r.currentJointName, equals('Vai trái'));
      expect(r.currentAngle, closeTo(145.3, 0.01));
      expect(r.userMaxAngle, closeTo(170.0, 0.01));
      expect(r.calibrationProgress, closeTo(0.62, 0.001));
      expect(r.queueIndex, equals(1));
      expect(r.totalJoints, equals(4));
      expect(r.overallProgress, closeTo(0.25, 0.001));
      expect(r.positionInstruction, equals('Giơ tay lên cao hơn'));
      expect(r.countdownRemaining, closeTo(2.1, 0.01));
    });

    test('phase 5 (completed) parses correctly', () {
      final done = PoseResult.fromJson({'phase': 5});
      expect(done.phase, equals(PosePhase.completed));
    });

    test('defaults to scoring phase when phase field is absent', () {
      final r = PoseResult.fromJson({});
      expect(r.phase, equals(PosePhase.scoring));
      expect(r.repCount, equals(0));
      expect(r.currentScore, equals(0.0));
    });

    test('copyWith overrides individual fields', () {
      final r = PoseResult.fromJson({
        'phase': 3,
        'sync': {'rep_count': 3, 'current_score': 50.0},
      });
      final updated = r.copyWith(repCount: 7, fatigueLevel: 'medium');
      expect(updated.repCount, equals(7));
      expect(updated.currentScore, closeTo(50.0, 0.001));
      expect(updated.fatigueLevel, equals('medium'));
      expect(updated.phase, equals(PosePhase.sync));
    });
  });
}
