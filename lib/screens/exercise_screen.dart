import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../models/pose_result.dart';
import '../providers/camera_provider.dart';
import '../providers/pairing_provider.dart';

const _coral = Color(0xFFD67052);

class ExerciseScreen extends ConsumerStatefulWidget {
  final String sessionId;
  final String exerciseType;
  final String workoutId;

  const ExerciseScreen({
    super.key,
    required this.sessionId,
    required this.exerciseType,
    required this.workoutId,
  });

  @override
  ConsumerState<ExerciseScreen> createState() => _ExerciseScreenState();
}

class _ExerciseScreenState extends ConsumerState<ExerciseScreen> {
  final _stopwatch = Stopwatch()..start();
  Timer? _uiTimer;
  bool _ending = false;

  // Calibration complete interstitial
  bool _showCalibComplete = false;
  double? _calibMaxAngle;

  Player? _videoPlayer;
  VideoController? _videoController;
  String? _loadedVideoUrl;

  @override
  void initState() {
    super.initState();
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureVideo(ref.read(pairingProvider).sessionConfig?.videoUrl);
    });
  }

  void _ensureVideo(String? videoUrl) {
    if (videoUrl == null || videoUrl.isEmpty) return;
    if (_loadedVideoUrl == videoUrl && _videoController != null) return;
    _videoPlayer?.dispose();
    _videoPlayer = Player();
    _videoController = VideoController(_videoPlayer!);
    _videoPlayer!.open(Media(videoUrl));
    _videoPlayer!.setPlaylistMode(PlaylistMode.loop);
    _videoPlayer!.setVolume(0); // muted — reference only
    _loadedVideoUrl = videoUrl;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    _stopwatch.stop();
    _videoPlayer?.dispose();
    super.dispose();
  }

  String get _elapsed {
    final s = _stopwatch.elapsed;
    final m = s.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = s.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pairingProvider);

    ref.listen<PairingState>(pairingProvider, (prev, next) {
      // Navigate on disconnect / error / complete
      if ((next.status == PairingStatus.disconnected ||
              next.status == PairingStatus.error ||
              next.status == PairingStatus.sessionComplete) &&
          !_ending) {
        _stopwatch.stop();
        context.go(AppRoutes.result, extra: {'status': next.status});
      }
      // Phase 2 → 3: show calibration complete interstitial
      if (prev?.poseResult?.phase == PosePhase.calibration &&
          next.poseResult?.phase == PosePhase.sync &&
          !_showCalibComplete) {
        setState(() {
          _calibMaxAngle = prev?.poseResult?.userMaxAngle;
          _showCalibComplete = true;
        });
      }
      // Phase 5 (completed): auto-end
      if (next.poseResult?.phase == PosePhase.completed &&
          prev?.poseResult?.phase != PosePhase.completed &&
          !_ending) {
        _autoEnd();
      }

      final nextVideoUrl = next.sessionConfig?.videoUrl;
      if (nextVideoUrl != prev?.sessionConfig?.videoUrl &&
          nextVideoUrl != null &&
          nextVideoUrl.isNotEmpty) {
        _ensureVideo(nextVideoUrl);
      }
    });

    return Scaffold(
      body: Stack(
        children: [
          _mainContent(state),
          Positioned(
            bottom: 8,
            right: 8,
            child: _DebugOverlay(state: state),
          ),
        ],
      ),
    );
  }

  Widget _mainContent(PairingState state) {
    if (_showCalibComplete) return _buildCalibCompleteScreen(state);
    final phase = state.poseResult?.phase ?? PosePhase.detection;
    return switch (phase) {
      PosePhase.detection => _buildDetectionScreen(state),
      PosePhase.calibration => _buildCalibrationScreen(state),
      PosePhase.sync => _buildTrainingScreen(state),
      PosePhase.scoring => _buildTrainingScreen(state),
      PosePhase.completed => _buildTrainingScreen(state),
    };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Phase 1 — Detection
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildDetectionScreen(PairingState state) {
    final result = state.poseResult;
    final progress = result?.progress ?? 0.0; // 0.0–1.0
    final poseDetected = result?.poseDetected ?? false;
    final message = result?.message ?? 'Please stand in the frame to start';
    final isConnected = state.status == PairingStatus.sessionActive;

    return Row(
      children: [
        // ── Camera (fills left area) ──────────────────────────────────────
        Expanded(
          child: _CameraFill(cameraReady: state.cameraReady),
        ),
        // ── Right panel: top info + bottom controls ───────────────────────
        SizedBox(
          width: 300,
          child: Column(
            children: [
              // Top: phase info
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                  color: AppTheme.surfaceContainer,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const _PhaseStepRow(currentPhase: 1),
                          _LiveBadge(isLive: isConnected),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'USER DETECTION',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '${(progress * 100).toInt()}%',
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _DetectedBadge(detected: poseDetected),
                    ],
                  ),
                ),
              ),
              // Bottom: instruction + end button
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                decoration: const BoxDecoration(
                  color: AppTheme.surface,
                  border: Border(top: BorderSide(color: Colors.white12)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Detecting...',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      message,
                      style: const TextStyle(
                          color: AppTheme.onSurfaceMuted, fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    _EndSessionButton(
                      ending: _ending,
                      onPressed: () => _confirmEnd(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Phase 2 — Calibration
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildCalibrationScreen(PairingState state) {
    final result = state.poseResult;
    final currentJoint = result?.currentJoint ?? '-';
    final queueIndex = result?.queueIndex ?? 0;
    final totalJoints = result?.totalJoints ?? 1;
    final currentAngle = result?.currentAngle;
    final userMaxAngle = result?.userMaxAngle;
    final countdown = result?.countdownRemaining ?? 0.0;
    final message = result?.message ?? 'Collecting angle measurements...';
    final isConnected = state.status == PairingStatus.sessionActive;

    return Row(
      children: [
        // ── Camera (fills left area) ──────────────────────────────────────
        Expanded(
          child: _CameraFill(cameraReady: state.cameraReady),
        ),
        // ── Right panel: top info + bottom controls ───────────────────────
        SizedBox(
          width: 300,
          child: Column(
            children: [
              // Top: phase info
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                  color: AppTheme.surfaceContainer,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const _PhaseStepRow(currentPhase: 2),
                          _LiveBadge(isLive: isConnected),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'COLLECTING MEASUREMENTS',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          _JointBadge(jointName: currentJoint),
                          const SizedBox(width: 8),
                          _QueueBadge(
                              index: queueIndex + 1, total: totalJoints),
                        ],
                      ),
                      if (currentAngle != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          '${currentAngle.toStringAsFixed(1)}°',
                          style: const TextStyle(
                              fontSize: 36, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'current angle',
                          style: TextStyle(
                              color: AppTheme.onSurfaceMuted, fontSize: 12),
                        ),
                        if (userMaxAngle != null) ...[
                          const SizedBox(height: 8),
                          _MaxAngleBadge(angle: userMaxAngle),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              // Bottom: countdown + instruction + end button
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                decoration: const BoxDecoration(
                  color: AppTheme.surface,
                  border: Border(top: BorderSide(color: Colors.white12)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _CalibCountdownTimer(remaining: countdown),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Calibrating...',
                                style: TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                message,
                                style: const TextStyle(
                                    color: AppTheme.onSurfaceMuted,
                                    fontSize: 12),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _EndSessionButton(
                      ending: _ending,
                      onPressed: () => _confirmEnd(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Calibration Complete interstitial (phase 2→3 transition)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildCalibCompleteScreen(PairingState state) {
    final exerciseName = widget.exerciseType.replaceAll('_', ' ');
    final maxAngle = _calibMaxAngle;

    return Container(
      color: AppTheme.surface,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_outline,
                      size: 64, color: AppTheme.primary),
                  const SizedBox(height: 16),
                  const Text(
                    'CALIBRATION COMPLETE',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.onSurfaceMuted,
                        letterSpacing: 1.5),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    exerciseName,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  if (maxAngle != null) ...[
                    _AngleArc(angle: maxAngle),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: _coral,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Target',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  const Text(
                    'Great Effort!',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Calibration complete. Ready for training.',
                    style: TextStyle(color: AppTheme.onSurfaceMuted),
                    textAlign: TextAlign.center,
                  ),
                  if (maxAngle != null) ...[
                    const SizedBox(height: 28),
                    _CalibStatBox(
                        value: '${maxAngle.toInt()}°', label: 'Max Angle'),
                  ],
                  const SizedBox(height: 40),
                  SizedBox(
                    width: 301,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _coral,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => _confirmEnd(context),
                      child: const Text('Done'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 301,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () =>
                          setState(() => _showCalibComplete = false),
                      child: const Text('Next Step →'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Phase 3 / 4 — Training (Sync → Scoring)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildTrainingScreen(PairingState state) {
    final result = state.poseResult;
    final phase = result?.phase ?? PosePhase.sync;
    final isSynced = phase == PosePhase.scoring || phase == PosePhase.completed;
    final scoreRaw = result?.currentScore ?? 0.0; // 0–100
    final scoreColor = scoreRaw >= 80
        ? AppTheme.primary
        : scoreRaw >= 60
            ? Colors.orange
            : AppTheme.error;
    final landmarks = result?.landmarks ?? const [];
    final message = result?.message ?? 'Analyzing...';
    final fatigueLevel = result?.fatigueLevel;
    final isConnected = state.status == PairingStatus.sessionActive;

    return Column(
      children: [
        // ── Top bar ───────────────────────────────────────────────────────
        Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          color: AppTheme.surfaceContainer,
          child: Row(
            children: [
              _LiveBadge(isLive: isConnected),
              const SizedBox(width: 10),
              _SyncBadge(synced: isSynced),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: scoreColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: scoreColor.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Score ',
                      style: TextStyle(
                          color: AppTheme.onSurfaceMuted, fontSize: 12),
                    ),
                    Text(
                      scoreRaw.toStringAsFixed(1),
                      style: TextStyle(
                        color: scoreColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── Middle: camera left | trainer video right ─────────────────────
        Expanded(
          child: Row(
            children: [
              // Camera half
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _CameraFill(cameraReady: state.cameraReady),
                    if (landmarks.isNotEmpty)
                      CustomPaint(painter: _LandmarkPainter(landmarks)),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: _LiveAnalysisBadge(isLive: isConnected),
                    ),
                    // "Your View" label bottom-right
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Your View',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Trainer video half
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _videoController != null
                        ? Video(controller: _videoController!)
                        : Container(
                            color: Colors.black87,
                            child: const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.videocam_off,
                                      size: 48, color: Colors.white24),
                                  SizedBox(height: 8),
                                  Text('No trainer video',
                                      style: TextStyle(
                                          color: Colors.white38, fontSize: 13)),
                                ],
                              ),
                            ),
                          ),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.play_circle_outline,
                                color: Colors.white, size: 14),
                            SizedBox(width: 5),
                            Text('Trainer View',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── Bottom stats bar ──────────────────────────────────────────────
        Container(
          height: 110,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          color: AppTheme.surfaceContainer,
          child: Row(
            children: [
              _TrainingStatColumn(value: _elapsed, label: 'Duration'),
              Container(
                  width: 1,
                  height: 40,
                  color: Colors.white12,
                  margin: const EdgeInsets.symmetric(horizontal: 12)),
              _TrainingStatColumn(
                  value: '${result?.repCount ?? 0}', label: 'Reps'),
              Container(
                  width: 1,
                  height: 40,
                  color: Colors.white12,
                  margin: const EdgeInsets.symmetric(horizontal: 12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      message,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (fatigueLevel != null) _FatigueChip(level: fatigueLevel),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 160,
                child: _EndSessionButton(
                  ending: _ending,
                  onPressed: () => _confirmEnd(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Auto-end and confirm
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _autoEnd() async {
    if (_ending) return;
    _stopwatch.stop();
    setState(() => _ending = true);
    await ref.read(pairingProvider.notifier).endSession();
    if (mounted) {
      GoRouter.of(context).go(AppRoutes.result,
          extra: {'status': PairingStatus.sessionComplete});
    }
  }

  Future<void> _confirmEnd(BuildContext context) async {
    final router = GoRouter.of(context);
    final notifier = ref.read(pairingProvider.notifier);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surfaceContainer,
        title: const Text('Kết thúc session?'),
        content: const Text(
            'Dữ liệu session sẽ được lưu và Android sẽ nhận kết quả.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Kết thúc'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      _stopwatch.stop();
      setState(() => _ending = true);
      await notifier.endSession();
      if (mounted) {
        router.go(AppRoutes.result,
            extra: {'status': PairingStatus.sessionComplete});
      }
    }
  }
}

// ════════════════════════════════════════════════════════════════════════════
// WIDGETS
// ════════════════════════════════════════════════════════════════════════════

// ── Camera fill ─────────────────────────────────────────────────────────────

class _CameraFill extends ConsumerWidget {
  final bool cameraReady;
  const _CameraFill({required this.cameraReady});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jpeg = ref.watch(cameraPreviewProvider);
    if (jpeg != null) {
      return Image.memory(jpeg, fit: BoxFit.cover, gaplessPlayback: true);
    }
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              cameraReady ? Icons.hourglass_empty : Icons.videocam_off,
              size: 64,
              color: Colors.white24,
            ),
            const SizedBox(height: 12),
            Text(
              cameraReady ? 'Đang khởi tạo camera...' : 'Camera không khả dụng',
              style: const TextStyle(color: Colors.white38, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Landmark overlay ─────────────────────────────────────────────────────────

class _LandmarkPainter extends CustomPainter {
  final List<Map<String, dynamic>> landmarks;
  const _LandmarkPainter(this.landmarks);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.primary
      ..style = PaintingStyle.fill;
    for (final lm in landmarks) {
      final x = (lm['x'] as num?)?.toDouble() ?? 0;
      final y = (lm['y'] as num?)?.toDouble() ?? 0;
      final vis = (lm['visibility'] as num?)?.toDouble() ?? 0;
      if (vis > 0.5) {
        canvas.drawCircle(Offset(x * size.width, y * size.height), 5, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_LandmarkPainter old) => landmarks != old.landmarks;
}

// ── Phase step row ────────────────────────────────────────────────────────────

class _PhaseStepRow extends StatelessWidget {
  final int currentPhase; // 1 = detection, 2 = calibration
  const _PhaseStepRow({required this.currentPhase});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _StepCircle(index: 1, active: true),
        _StepLine(active: currentPhase >= 2),
        _StepCircle(index: 2, active: currentPhase >= 2),
      ],
    );
  }
}

class _StepCircle extends StatelessWidget {
  final int index;
  final bool active;
  const _StepCircle({required this.index, required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? AppTheme.primary : Colors.transparent,
        border: Border.all(
          color: active ? AppTheme.primary : Colors.white38,
          width: 2,
        ),
      ),
      child: Center(
        child: Text(
          '$index',
          style: TextStyle(
            color: active ? Colors.white : Colors.white38,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _StepLine extends StatelessWidget {
  final bool active;
  const _StepLine({required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 2,
      color: active ? AppTheme.primary : Colors.white24,
      margin: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

// ── Badges ────────────────────────────────────────────────────────────────────

class _LiveBadge extends StatelessWidget {
  final bool isLive;
  const _LiveBadge({required this.isLive});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color:
            isLive ? AppTheme.primary.withValues(alpha: 0.85) : Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isLive ? Colors.white : Colors.white38,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isLive ? 'LIVE' : 'OFFLINE',
            style: TextStyle(
              color: isLive ? Colors.white : Colors.white38,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetectedBadge extends StatelessWidget {
  final bool detected;
  const _DetectedBadge({required this.detected});

  @override
  Widget build(BuildContext context) {
    final color = detected ? AppTheme.primary : _coral;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            detected ? Icons.check_circle_outline : Icons.person_search,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            detected ? 'Detected' : 'Searching...',
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _JointBadge extends StatelessWidget {
  final String jointName;
  const _JointBadge({required this.jointName});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sync, size: 13, color: AppTheme.primary),
          const SizedBox(width: 5),
          Text(
            jointName.replaceAll('_', ' '),
            style: const TextStyle(
                color: AppTheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _QueueBadge extends StatelessWidget {
  final int index;
  final int total;
  const _QueueBadge({required this.index, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.4)),
      ),
      child: Text(
        '$index / $total',
        style: const TextStyle(
            color: Colors.blue, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _MaxAngleBadge extends StatelessWidget {
  final double angle;
  const _MaxAngleBadge({required this.angle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _coral.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _coral.withValues(alpha: 0.5)),
      ),
      child: Text(
        'Max: ${angle.toStringAsFixed(1)}°',
        style: const TextStyle(
            color: _coral, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _LiveAnalysisBadge extends StatelessWidget {
  final bool isLive;
  const _LiveAnalysisBadge({required this.isLive});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isLive ? AppTheme.primary : Colors.white38,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'LIVE ANALYSIS',
            style: TextStyle(
              color: isLive ? Colors.white : Colors.white38,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncBadge extends StatelessWidget {
  final bool synced;
  const _SyncBadge({required this.synced});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sync,
              size: 13, color: synced ? AppTheme.primary : Colors.orange),
          const SizedBox(width: 5),
          Text(
            synced ? 'SYNCED' : 'SYNCING',
            style: TextStyle(
              color: synced ? AppTheme.primary : Colors.orange,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Calibration countdown timer ───────────────────────────────────────────────

class _CalibCountdownTimer extends StatelessWidget {
  final double remaining; // 0–3 seconds
  static const double _max = 3.0;

  const _CalibCountdownTimer({required this.remaining});

  @override
  Widget build(BuildContext context) {
    final progress = (remaining / _max).clamp(0.0, 1.0);
    return SizedBox(
      width: 63,
      height: 63,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 63,
            height: 63,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 6,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation(AppTheme.primary),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'HOLD',
                style: TextStyle(
                    fontSize: 9,
                    color: AppTheme.primary,
                    fontWeight: FontWeight.bold),
              ),
              Text(
                '${remaining.toInt()}s',
                style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Angle arc (calibration complete) ─────────────────────────────────────────

class _AngleArc extends StatelessWidget {
  final double angle; // degrees (e.g. 145.0)
  const _AngleArc({required this.angle});

  @override
  Widget build(BuildContext context) {
    final progress = (angle / 180.0).clamp(0.0, 1.0);
    return SizedBox(
      width: 160,
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 160,
            height: 160,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 12,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation(AppTheme.primary),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${angle.toInt()}',
                style:
                    const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
              ),
              const Text(
                'Range',
                style: TextStyle(color: AppTheme.onSurfaceMuted, fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Calibration stat box ──────────────────────────────────────────────────────

class _CalibStatBox extends StatelessWidget {
  final String value;
  final String label;
  const _CalibStatBox({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 110,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(value,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(
                  color: AppTheme.onSurfaceMuted, fontSize: 11)),
        ],
      ),
    );
  }
}

// ── Training stat column ──────────────────────────────────────────────────────

class _TrainingStatColumn extends StatelessWidget {
  final String value;
  final String label;
  const _TrainingStatColumn({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.onSurface)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  color: AppTheme.onSurfaceMuted, fontSize: 11)),
        ],
      ),
    );
  }
}

// ── Fatigue chip ──────────────────────────────────────────────────────────────

class _FatigueChip extends StatelessWidget {
  final String level;
  const _FatigueChip({required this.level});

  Color get _color {
    return switch (level.toUpperCase()) {
      'FRESH' => AppTheme.primary,
      'MILD' => Colors.yellowAccent,
      'MODERATE' => Colors.orange,
      'HIGH' => AppTheme.error,
      _ => AppTheme.onSurfaceMuted,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      'Fatigue: $level',
      style:
          TextStyle(color: _color, fontSize: 11, fontWeight: FontWeight.w600),
    );
  }
}

// ── End session button ────────────────────────────────────────────────────────

class _EndSessionButton extends StatelessWidget {
  final bool ending;
  final VoidCallback onPressed;
  const _EndSessionButton({required this.ending, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.error,
        minimumSize: const Size.fromHeight(44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: ending ? null : onPressed,
      icon: ending
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            )
          : const Icon(Icons.stop_circle_outlined, size: 16),
      label: Text(
        ending ? 'Đang lưu...' : 'End Session',
        style: const TextStyle(fontSize: 13),
      ),
    );
  }
}

// ── Debug overlay ─────────────────────────────────────────────────────────────

class _DebugOverlay extends StatelessWidget {
  final PairingState state;
  const _DebugOverlay({required this.state});

  @override
  Widget build(BuildContext context) {
    final phase = state.poseResult?.phase.name ?? 'detection(waiting)';
    final hasVideoUrl = state.sessionConfig?.videoUrl?.isNotEmpty == true;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.yellow.withValues(alpha: 0.4)),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(
            color: Colors.yellow, fontSize: 11, fontFamily: 'monospace'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('● frames sent : ${state.debugFramesSent}'),
            Text('● backend msgs: ${state.debugMsgsReceived}'),
            Text('● phase       : $phase'),
            Text('● video_url   : ${hasVideoUrl ? 'set' : 'null'}'),
            Text(
              '● last msg    : ${state.debugLastMsg}',
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
