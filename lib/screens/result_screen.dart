import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../models/session_models.dart';
import '../providers/pairing_provider.dart';

class ResultScreen extends ConsumerWidget {
  final PairingStatus finalStatus;

  const ResultScreen({super.key, required this.finalStatus});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionResult = ref.watch(
      pairingProvider.select((s) => s.sessionResult),
    );
    final isSuccess = finalStatus == PairingStatus.sessionComplete;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Status icon ───────────────────────────────────────────
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSuccess
                        ? AppTheme.primary.withValues(alpha: 0.15)
                        : AppTheme.error.withValues(alpha: 0.15),
                  ),
                  child: Icon(
                    isSuccess
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    size: 64,
                    color: isSuccess ? AppTheme.primary : AppTheme.error,
                  ),
                ),
                const SizedBox(height: 28),

                Text(
                  isSuccess ? 'Session hoàn tất!' : _errorTitle(finalStatus),
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(
                  isSuccess
                      ? 'Kết quả đã được gửi về Android.'
                      : _errorSubtitle(finalStatus),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppTheme.onSurfaceMuted, height: 1.5),
                ),

                // ── Stats card (success only) ──────────────────────────────
                if (isSuccess) ...[
                  const SizedBox(height: 36),
                  _StatsCard(result: sessionResult),
                ],

                const SizedBox(height: 40),

                // ── Actions ───────────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Session mới'),
                      onPressed: () async {
                        await ref.read(pairingProvider.notifier).reset();
                        if (context.mounted) {
                          await ref
                              .read(pairingProvider.notifier)
                              .startServer();
                          if (context.mounted) {
                            context.go(AppRoutes.qrDisplay);
                          }
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _errorTitle(PairingStatus status) => switch (status) {
        PairingStatus.disconnected => 'Mất kết nối Android',
        PairingStatus.error => 'Lỗi session',
        _ => 'Session kết thúc',
      };

  String _errorSubtitle(PairingStatus status) => switch (status) {
        PairingStatus.disconnected =>
          'Android đã ngắt kết nối trong lúc session đang chạy.\nSession đã bị huỷ.',
        PairingStatus.error => 'Đã xảy ra lỗi trong lúc thực hiện session.',
        _ => '',
      };
}

// ── Stats card ────────────────────────────────────────────────────────────────

class _StatsCard extends StatelessWidget {
  final SessionResult? result;
  const _StatsCard({required this.result});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: result == null
          ? const _NoResultPlaceholder()
          : _ResultContent(result: result!),
    );
  }
}

class _NoResultPlaceholder extends StatelessWidget {
  const _NoResultPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Icon(Icons.hourglass_empty, size: 40, color: AppTheme.onSurfaceMuted),
        SizedBox(height: 12),
        Text(
          'Kết quả chưa có\nXem chi tiết trên điện thoại.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.onSurfaceMuted, height: 1.5),
        ),
      ],
    );
  }
}

class _ResultContent extends StatelessWidget {
  final SessionResult result;
  const _ResultContent({required this.result});

  @override
  Widget build(BuildContext context) {
    final minutes = result.durationSeconds ~/ 60;
    final seconds = result.durationSeconds % 60;
    final durationLabel =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    return Column(
      children: [
        // ── 3 big numbers ──────────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _StatTile(
              value: '${result.reps}',
              label: 'Reps',
              icon: Icons.repeat,
            ),
            _divider(),
            _StatTile(
              value: '${(result.score * 100).toStringAsFixed(0)}%',
              label: 'Form Score',
              icon: Icons.star_outline,
              valueColor: _scoreColor(result.score),
            ),
            _divider(),
            _StatTile(
              value: durationLabel,
              label: 'Duration',
              icon: Icons.timer_outlined,
            ),
          ],
        ),

        // ── Score bar ──────────────────────────────────────────────────
        const SizedBox(height: 24),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: result.score.clamp(0.0, 1.0),
            backgroundColor: Colors.white12,
            valueColor:
                AlwaysStoppedAnimation(_scoreColor(result.score)),
            minHeight: 10,
          ),
        ),

        // ── AI summary ─────────────────────────────────────────────────
        if (result.summary != null && result.summary!.isNotEmpty) ...[
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppTheme.primary.withValues(alpha: 0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.auto_awesome,
                    size: 16, color: AppTheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    result.summary!,
                    style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.onSurface,
                        height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 60,
        color: Colors.white12,
      );

  Color _scoreColor(double score) => score >= 0.8
      ? AppTheme.primary
      : score >= 0.5
          ? Colors.orange
          : AppTheme.error;
}

class _StatTile extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color? valueColor;

  const _StatTile({
    required this.value,
    required this.label,
    required this.icon,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 18, color: AppTheme.onSurfaceMuted),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: valueColor ?? AppTheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
              color: AppTheme.onSurfaceMuted, fontSize: 12),
        ),
      ],
    );
  }
}
