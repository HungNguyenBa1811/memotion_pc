/// Config for the exercise session received from Android.
class SessionConfig {
  final String jwt;
  final String workoutId;
  final String exerciseType;

  const SessionConfig({
    required this.jwt,
    required this.workoutId,
    required this.exerciseType,
  });
}

/// Result of a completed exercise session.
class SessionResult {
  final String sessionId;
  final int durationSeconds;
  final int reps;
  final double score;
  final String? summary;

  const SessionResult({
    required this.sessionId,
    required this.durationSeconds,
    required this.reps,
    required this.score,
    this.summary,
  });

  factory SessionResult.fromJson(Map<String, dynamic> json) {
    return SessionResult(
      sessionId: json['session_id'] as String? ?? '',
      durationSeconds: json['duration_seconds'] as int? ?? 0,
      reps: json['reps'] as int? ?? 0,
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      summary: json['summary'] as String?,
    );
  }
}
