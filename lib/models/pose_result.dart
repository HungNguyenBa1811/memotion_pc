/// Real-time pose detection result received from the backend WebSocket.
///
/// Backend sends this after processing each frame:
/// ```json
/// {
///   "type": "frame_result",
///   "reps": 5,
///   "score": 0.87,
///   "feedback": "Keep your back straight",
///   "stage": "down",
///   "timestamp": 1234567890
/// }
/// ```
class PoseResult {
  final int reps;
  final double score;
  final String? feedback;
  final String? stage; // e.g. "up" / "down" for rep counting
  final int timestamp;

  const PoseResult({
    required this.reps,
    required this.score,
    this.feedback,
    this.stage,
    required this.timestamp,
  });

  factory PoseResult.fromJson(Map<String, dynamic> json) {
    return PoseResult(
      reps: json['reps'] as int? ?? 0,
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      feedback: json['feedback'] as String?,
      stage: json['stage'] as String?,
      timestamp: json['timestamp'] as int? ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }

  PoseResult copyWith({int? reps, double? score, String? feedback, String? stage}) {
    return PoseResult(
      reps: reps ?? this.reps,
      score: score ?? this.score,
      feedback: feedback ?? this.feedback,
      stage: stage ?? this.stage,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }
}
