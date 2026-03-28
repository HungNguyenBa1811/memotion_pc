/// Backend phase for the pose session (5 phases total).
enum PosePhase { detection, calibration, sync, scoring, completed }

/// Real-time pose result from the backend WebSocket.
///
/// Top-level fields: phase, phase_name, timestamp, message, warning
/// Phase-specific fields are nested under "data".
///
/// ```json
/// {
///   "phase": 2, "phase_name": "calibration",
///   "timestamp": 1711612800.123,
///   "message": "Hold the position", "warning": null,
///   "data": { "current_joint": "left_shoulder", "progress": 0.62, ... }
/// }
/// ```
class PoseResult {
  final PosePhase phase;
  final String phaseName;
  final String? message;   // server instruction, shown in UI
  final String? warning;
  final int timestamp;

  // Phase 1 — Detection (from data)
  final bool poseDetected;
  final int stableCount;
  final double progress;           // 0.0–1.0 detection progress

  // Phase 2 — Calibration (from data)
  final String? currentJoint;
  final String? currentJointName;
  final double? currentAngle;
  final double? userMaxAngle;
  final double calibrationProgress; // data.progress (per-joint)
  final double overallProgress;     // data.overall_progress
  final int queueIndex;
  final int totalJoints;
  final String? positionInstruction; // data.position_instruction
  final double? countdownRemaining;  // data.countdown_remaining

  // Phase 4 — Scoring (from data)
  final int repCount;              // data.rep_count
  final double currentScore;       // data.current_score  (0.0–100.0)
  final String? fatigueLevel;      // data.fatigue_level

  // Phase 4 — Final scores (from data when scoring completes)
  final double? totalScore;
  final double? romScore;
  final double? stabilityScore;
  final double? flowScore;
  final String? grade;

  // Phase 3/4 — Pose landmarks for overlay drawing
  // Each item: {x: 0-1, y: 0-1, visibility: 0-1}
  final List<Map<String, dynamic>> landmarks;

  const PoseResult({
    this.phase = PosePhase.scoring,
    this.phaseName = 'scoring',
    this.message,
    this.warning,
    required this.timestamp,
    this.poseDetected = false,
    this.stableCount = 0,
    this.progress = 0.0,
    this.currentJoint,
    this.currentJointName,
    this.currentAngle,
    this.userMaxAngle,
    this.calibrationProgress = 0.0,
    this.overallProgress = 0.0,
    this.queueIndex = 0,
    this.totalJoints = 1,
    this.positionInstruction,
    this.countdownRemaining,
    this.repCount = 0,
    this.currentScore = 0.0,
    this.fatigueLevel,
    this.totalScore,
    this.romScore,
    this.stabilityScore,
    this.flowScore,
    this.grade,
    this.landmarks = const [],
  });

  factory PoseResult.fromJson(Map<String, dynamic> json) {
    final phaseInt = json['phase'] as int? ?? 4;
    final phase = switch (phaseInt) {
      1 => PosePhase.detection,
      2 => PosePhase.calibration,
      3 => PosePhase.sync,
      4 => PosePhase.scoring,
      5 => PosePhase.completed,
      _ => PosePhase.scoring,
    };

    // Each phase has its own named key — NOT a generic "data" key.
    // Phase 1 → 'detection', Phase 2 → 'calibration' (fallback 'data'),
    // Phase 3 → 'sync', Phase 4 → 'final_report', Phase 5 → no data.
    final Map<String, dynamic> data = switch (phaseInt) {
      1 => json['detection'] as Map<String, dynamic>? ?? {},
      2 => (json['calibration'] ?? json['data']) as Map<String, dynamic>? ?? {},
      3 => json['sync'] as Map<String, dynamic>? ?? {},
      4 => json['final_report'] as Map<String, dynamic>? ?? {},
      _ => json['data'] as Map<String, dynamic>? ?? {},
    };

    // Backend sends timestamp as float seconds → convert to ms
    final ts = json['timestamp'];
    final timestampMs = ts is double
        ? (ts * 1000).toInt()
        : (ts as int? ?? DateTime.now().millisecondsSinceEpoch);

    return PoseResult(
      phase: phase,
      phaseName: json['phase_name'] as String? ?? phase.name,
      message: json['message'] as String?,
      warning: json['warning'] as String?,
      timestamp: timestampMs,
      // Phase 1
      poseDetected: data['pose_detected'] as bool? ?? false,
      stableCount: data['stable_count'] as int? ?? 0,
      progress: (data['progress'] as num?)?.toDouble() ?? 0.0,
      // Phase 2
      currentJoint: data['current_joint'] as String?,
      currentJointName: data['current_joint_name'] as String?,
      currentAngle: (data['current_angle'] as num?)?.toDouble(),
      userMaxAngle: (data['user_max_angle'] as num?)?.toDouble(),
      calibrationProgress: (data['progress'] as num?)?.toDouble() ?? 0.0,
      overallProgress: (data['overall_progress'] as num?)?.toDouble() ?? 0.0,
      queueIndex: data['queue_index'] as int? ?? 0,
      totalJoints: data['total_joints'] as int? ?? 1,
      positionInstruction: data['position_instruction'] as String?,
      countdownRemaining: (data['countdown_remaining'] as num?)?.toDouble(),
      // Phase 4
      repCount: data['rep_count'] as int? ?? 0,
      currentScore: (data['current_score'] as num?)?.toDouble() ?? 0.0,
      fatigueLevel: data['fatigue_level'] as String?,
      totalScore: (data['total_score'] as num?)?.toDouble(),
      romScore: (data['rom_score'] as num?)?.toDouble(),
      stabilityScore: (data['stability_score'] as num?)?.toDouble(),
      flowScore: (data['flow_score'] as num?)?.toDouble(),
      grade: data['grade'] as String?,
      landmarks: (data['landmarks'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          const [],
    );
  }

  PoseResult copyWith({
    PosePhase? phase,
    String? phaseName,
    String? message,
    String? warning,
    bool? poseDetected,
    int? stableCount,
    double? progress,
    String? currentJoint,
    String? currentJointName,
    double? currentAngle,
    double? userMaxAngle,
    double? calibrationProgress,
    double? overallProgress,
    int? queueIndex,
    int? totalJoints,
    String? positionInstruction,
    double? countdownRemaining,
    int? repCount,
    double? currentScore,
    String? fatigueLevel,
    double? totalScore,
    double? romScore,
    double? stabilityScore,
    double? flowScore,
    String? grade,
    List<Map<String, dynamic>>? landmarks,
  }) {
    return PoseResult(
      phase: phase ?? this.phase,
      phaseName: phaseName ?? this.phaseName,
      message: message ?? this.message,
      warning: warning ?? this.warning,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      poseDetected: poseDetected ?? this.poseDetected,
      stableCount: stableCount ?? this.stableCount,
      progress: progress ?? this.progress,
      currentJoint: currentJoint ?? this.currentJoint,
      currentJointName: currentJointName ?? this.currentJointName,
      currentAngle: currentAngle ?? this.currentAngle,
      userMaxAngle: userMaxAngle ?? this.userMaxAngle,
      calibrationProgress: calibrationProgress ?? this.calibrationProgress,
      overallProgress: overallProgress ?? this.overallProgress,
      queueIndex: queueIndex ?? this.queueIndex,
      totalJoints: totalJoints ?? this.totalJoints,
      positionInstruction: positionInstruction ?? this.positionInstruction,
      countdownRemaining: countdownRemaining ?? this.countdownRemaining,
      repCount: repCount ?? this.repCount,
      currentScore: currentScore ?? this.currentScore,
      fatigueLevel: fatigueLevel ?? this.fatigueLevel,
      totalScore: totalScore ?? this.totalScore,
      romScore: romScore ?? this.romScore,
      stabilityScore: stabilityScore ?? this.stabilityScore,
      flowScore: flowScore ?? this.flowScore,
      grade: grade ?? this.grade,
      landmarks: landmarks ?? this.landmarks,
    );
  }
}
