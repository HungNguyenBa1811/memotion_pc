import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../providers/camera_provider.dart';
import '../providers/pairing_provider.dart';

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
  late final Stopwatch _stopwatch = Stopwatch()..start();
  Timer? _uiTimer;
  bool _ending = false; // true while endSession() + fetchResult is running

  @override
  void initState() {
    super.initState();
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    _stopwatch.stop();
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
      if (next.status == PairingStatus.disconnected ||
          next.status == PairingStatus.error ||
          next.status == PairingStatus.sessionComplete) {
        _stopwatch.stop();
        if (!_ending) {
          // Backend-triggered end — navigate without waiting for _confirmEnd.
          context.go(AppRoutes.result, extra: {'status': next.status});
        }
      }
    });

    return Scaffold(
      body: Row(
        children: [
          // ── Camera / video panel ───────────────────────────────────────
          Expanded(
            flex: 6,
            child: _buildCameraPanel(state),
          ),
          // ── Info sidebar ───────────────────────────────────────────────
          Container(
            width: 300,
            color: AppTheme.surfaceContainer,
            child: _buildSidebar(state),
          ),
        ],
      ),
    );
  }

  // ── Camera panel ──────────────────────────────────────────────────────────

  Widget _buildCameraPanel(PairingState state) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Live camera preview or placeholder
        _CameraPreviewLayer(cameraReady: state.cameraReady),

        // Session timer (top-left)
        Positioned(
          top: 24,
          left: 24,
          child: _TimerBadge(elapsed: _elapsed),
        ),

        // Connection status (top-right)
        Positioned(
          top: 24,
          right: 24,
          child: _HeartbeatIndicator(),
        ),

        // Pose stage indicator (bottom-left)
        if (state.poseResult?.stage != null)
          Positioned(
            bottom: 24,
            left: 24,
            child: _StageBadge(stage: state.poseResult!.stage!),
          ),

        // Score bar (bottom-centre)
        if (state.poseResult != null)
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(child: _ScoreBar(score: state.poseResult!.score)),
          ),
      ],
    );
  }

  // ── Sidebar ───────────────────────────────────────────────────────────────

  Widget _buildSidebar(PairingState state) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          const Text(
            'Session Info',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),

          _InfoRow(
            label: 'Session ID',
            value: widget.sessionId.isEmpty
                ? '-'
                : '${widget.sessionId.substring(0, 8)}...',
          ),
          const SizedBox(height: 12),
          _InfoRow(
            label: 'Exercise',
            value: widget.exerciseType.replaceAll('_', ' ').toUpperCase(),
          ),
          const SizedBox(height: 12),
          _InfoRow(
            label: 'Status',
            value: _statusLabel(state.status),
            valueColor: AppTheme.primary,
          ),

          const Divider(height: 40),

          // ── Real-time pose stats ──────────────────────────────────────
          const Text(
            'Live Stats',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          _RepCounter(reps: state.poseResult?.reps ?? 0),
          const SizedBox(height: 20),
          _ScoreDisplay(score: state.poseResult?.score ?? 0.0),
          const SizedBox(height: 16),
          if (state.poseResult?.feedback != null)
            _FeedbackCard(feedback: state.poseResult!.feedback!),

          const Spacer(),

          // ── Camera status ─────────────────────────────────────────────
          if (!state.cameraReady)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Icon(Icons.videocam_off,
                      size: 16, color: AppTheme.onSurfaceMuted),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Camera unavailable',
                      style: TextStyle(
                          color: AppTheme.onSurfaceMuted, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),

          // ── End session button ────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.error,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _ending ? null : () => _confirmEnd(context),
              icon: _ending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.stop_circle_outlined),
              label: Text(_ending ? 'Đang lưu...' : 'Kết thúc session'),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _statusLabel(PairingStatus status) {
    return switch (status) {
      PairingStatus.sessionActive => 'Đang hoạt động',
      PairingStatus.paired => 'Đã kết nối',
      PairingStatus.disconnected => 'Mất kết nối',
      _ => status.name,
    };
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

// ── Camera preview layer ───────────────────────────────────────────────────

class _CameraPreviewLayer extends ConsumerWidget {
  final bool cameraReady;

  const _CameraPreviewLayer({required this.cameraReady});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jpeg = ref.watch(cameraPreviewProvider);

    if (jpeg != null) {
      return Image.memory(
        jpeg,
        fit: BoxFit.cover,
        gaplessPlayback: true, // suppress flicker between frames
      );
    }

    if (cameraReady) {
      return _buildPlaceholder('Đang khởi tạo camera...');
    }
    final errorMsg = ref.watch(
      pairingProvider.select((s) => s.errorMessage),
    );
    return _buildPlaceholder(
      errorMsg != null
          ? '$errorMsg\nSession vẫn tiếp tục qua backend'
          : 'Camera không khả dụng\nSession vẫn tiếp tục qua backend',
    );
  }

  Widget _buildPlaceholder(String message) {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off, size: 80, color: Colors.white24),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Overlay widgets ───────────────────────────────────────────────────────

class _TimerBadge extends StatelessWidget {
  final String elapsed;
  const _TimerBadge({required this.elapsed});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer, color: AppTheme.primary, size: 18),
          const SizedBox(width: 8),
          Text(
            elapsed,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _StageBadge extends StatelessWidget {
  final String stage;
  const _StageBadge({required this.stage});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        stage.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          letterSpacing: 2,
        ),
      ),
    );
  }
}

class _ScoreBar extends StatelessWidget {
  final double score; // 0.0 – 1.0
  const _ScoreBar({required this.score});

  @override
  Widget build(BuildContext context) {
    final color = score >= 0.8
        ? AppTheme.primary
        : score >= 0.5
            ? Colors.orange
            : AppTheme.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Form: ', style: TextStyle(color: Colors.white70, fontSize: 13)),
          SizedBox(
            width: 120,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: score.clamp(0.0, 1.0),
                backgroundColor: Colors.white24,
                valueColor: AlwaysStoppedAnimation(color),
                minHeight: 8,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${(score * 100).toStringAsFixed(0)}%',
            style: TextStyle(
                color: color, fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

// ── Sidebar stat widgets ───────────────────────────────────────────────────

class _RepCounter extends StatelessWidget {
  final int reps;
  const _RepCounter({required this.reps});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '$reps',
          style: const TextStyle(
            fontSize: 64,
            fontWeight: FontWeight.bold,
            color: AppTheme.primary,
            height: 1,
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 8, left: 6),
          child: Text(
            'reps',
            style: TextStyle(color: AppTheme.onSurfaceMuted, fontSize: 16),
          ),
        ),
      ],
    );
  }
}

class _ScoreDisplay extends StatelessWidget {
  final double score;
  const _ScoreDisplay({required this.score});

  Color get _color => score >= 0.8
      ? AppTheme.primary
      : score >= 0.5
          ? Colors.orange
          : AppTheme.error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Form score',
          style: TextStyle(color: AppTheme.onSurfaceMuted, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: score.clamp(0.0, 1.0),
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation(_color),
                  minHeight: 8,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${(score * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                color: _color,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  final String feedback;
  const _FeedbackCard({required this.feedback});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.tips_and_updates_outlined,
              size: 16, color: AppTheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              feedback,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.onSurface,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeartbeatIndicator extends StatefulWidget {
  @override
  State<_HeartbeatIndicator> createState() => _HeartbeatIndicatorState();
}

class _HeartbeatIndicatorState extends State<_HeartbeatIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.favorite,
              size: 14,
              color:
                  Color.lerp(AppTheme.primary, Colors.red, _controller.value),
            ),
            const SizedBox(width: 6),
            const Text(
              'Android connected',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                const TextStyle(color: AppTheme.onSurfaceMuted, fontSize: 12)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? AppTheme.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
