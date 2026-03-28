/// Config for the exercise session received from Android.
class SessionConfig {
  final String jwt;
  final String workoutId;
  final String exerciseType;
  final String? videoPath; // relative path fetched from GET /api/tasks/{id}
  final String? videoUrl;  // full URL from pair_request.session_config.video_url

  const SessionConfig({
    required this.jwt,
    required this.workoutId,
    required this.exerciseType,
    this.videoPath,
    this.videoUrl,
  });

  SessionConfig copyWith({String? videoPath, String? videoUrl}) => SessionConfig(
        jwt: jwt,
        workoutId: workoutId,
        exerciseType: exerciseType,
        videoPath: videoPath ?? this.videoPath,
        videoUrl: videoUrl ?? this.videoUrl,
      );
}

/// Result of a completed exercise session.
class SessionResult {
  final String sessionId;
  final int durationSeconds;
  final int reps;
  final double score;       // legacy 0.0–1.0
  final String? summary;

  // Extended fields from backend DELETE response
  final double? totalScore;                         // 0–100
  final double? romScore;
  final double? stabilityScore;
  final double? flowScore;
  final String? grade;
  final double? caloriesBurned;
  final String? exerciseName;
  final String? fatigueLevelFinal;
  // recommendations is a List<String> from the backend REST API
  final List<String>? recommendations;

  const SessionResult({
    required this.sessionId,
    required this.durationSeconds,
    required this.reps,
    required this.score,
    this.summary,
    this.totalScore,
    this.romScore,
    this.stabilityScore,
    this.flowScore,
    this.grade,
    this.caloriesBurned,
    this.exerciseName,
    this.fatigueLevelFinal,
    this.recommendations,
  });

  factory SessionResult.fromJson(Map<String, dynamic> json) {
    // total_reps (v2) takes precedence over reps (legacy)
    final reps = json['total_reps'] as int? ?? json['reps'] as int? ?? 0;
    return SessionResult(
      sessionId: json['session_id'] as String? ?? '',
      durationSeconds: json['duration_seconds'] as int? ?? 0,
      reps: reps,
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      summary: json['summary'] as String?,
      totalScore: (json['total_score'] as num?)?.toDouble(),
      romScore: (json['rom_score'] as num?)?.toDouble(),
      stabilityScore: (json['stability_score'] as num?)?.toDouble(),
      flowScore: (json['flow_score'] as num?)?.toDouble(),
      grade: json['grade'] as String?,
      caloriesBurned: (json['calories_burned'] as num?)?.toDouble(),
      exerciseName: json['exercise_name'] as String?,
      fatigueLevelFinal: json['fatigue_level'] as String?,
      // recommendations is List<String> in v2 API
      recommendations: (json['recommendations'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
    );
  }
}
