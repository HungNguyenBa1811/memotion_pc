import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../models/session_models.dart';
import '../providers/pairing_provider.dart';

const _coral = Color(0xFFD67052);

class ResultScreen extends ConsumerWidget {
  final PairingStatus finalStatus;

  const ResultScreen({super.key, required this.finalStatus});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(pairingProvider.select((s) => s.sessionResult));
    final isSuccess = finalStatus == PairingStatus.sessionComplete;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Header ────────────────────────────────────────────────
                Text(
                  isSuccess ? 'Session Complete' : _errorTitle(finalStatus),
                  style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.onSurfaceMuted,
                      letterSpacing: 1.2),
                ),
                const SizedBox(height: 4),
                Text(
                  isSuccess ? 'Great Effort!' : _errorSubtitle(finalStatus),
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                if (isSuccess) ...[
                  // ── Score arc ────────────────────────────────────────
                  _ScoreArc(result: result),
                  const SizedBox(height: 12),
                  const Text(
                    "You're making excellent progress.",
                    style: TextStyle(
                        color: AppTheme.onSurfaceMuted, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // ── Stats row ────────────────────────────────────────
                  if (result != null) _StatsRow(result: result),

                  // ── AI summary ───────────────────────────────────────
                  if (result?.summary != null &&
                      result!.summary!.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _SummaryCard(summary: result.summary!),
                  ],

                  // ── Improvements ─────────────────────────────────────
                  if (result?.recommendations != null &&
                      result!.recommendations!.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'What to improve',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...result.recommendations!
                        .map((r) => _RecommendationCard(text: r)),
                  ],
                ] else ...[
                  // ── Error icon ───────────────────────────────────────
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.error.withValues(alpha: 0.12),
                    ),
                    child: const Icon(Icons.error_outline,
                        size: 52, color: AppTheme.error),
                  ),
                ],

                const SizedBox(height: 48),

                // ── Actions ───────────────────────────────────────────────
                _ActionsRow(finalStatus: finalStatus, ref: ref),
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
          'Android đã ngắt kết nối trong lúc session đang chạy.',
        PairingStatus.error => 'Đã xảy ra lỗi trong lúc thực hiện session.',
        _ => '',
      };
}

// ── Score arc ─────────────────────────────────────────────────────────────────

class _ScoreArc extends StatelessWidget {
  final SessionResult? result;
  const _ScoreArc({required this.result});

  @override
  Widget build(BuildContext context) {
    // Prefer totalScore (0–100) from extended API; fall back to legacy score (0–1)
    final scoreOf100 =
        result?.totalScore ?? ((result?.score ?? 0.0) * 100);
    final progress = (scoreOf100 / 100).clamp(0.0, 1.0);
    final grade = result?.grade;

    final scoreColor = scoreOf100 >= 80
        ? AppTheme.primary
        : scoreOf100 >= 60
            ? Colors.orange
            : AppTheme.error;

    return SizedBox(
      width: 180,
      height: 180,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 180,
            height: 180,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 14,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation(scoreColor),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${scoreOf100.toInt()}',
                style: const TextStyle(
                    fontSize: 52, fontWeight: FontWeight.bold),
              ),
              const Text(
                'Score',
                style: TextStyle(
                    color: AppTheme.onSurfaceMuted, fontSize: 13),
              ),
              if (grade != null) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: _coral,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    grade,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── Stats row ─────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final SessionResult result;
  const _StatsRow({required this.result});

  @override
  Widget build(BuildContext context) {
    final minutes = result.durationSeconds ~/ 60;
    final seconds = result.durationSeconds % 60;
    final durationLabel =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    // Accuracy: prefer flowScore, else romScore, else legacy score*100
    final accuracy = result.flowScore ??
        result.romScore ??
        (result.score * 100);
    final kcal = result.caloriesBurned;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _StatTile(value: durationLabel, label: 'Duration',
              icon: Icons.timer_outlined),
          _vDivider(),
          _StatTile(
            value: '${accuracy.toStringAsFixed(0)}%',
            label: 'Accuracy',
            icon: Icons.star_outline,
            valueColor: accuracy >= 80
                ? AppTheme.primary
                : accuracy >= 60
                    ? Colors.orange
                    : AppTheme.error,
          ),
          _vDivider(),
          if (kcal != null) ...[
            _StatTile(
                value: '${kcal.toInt()}',
                label: 'Kcal',
                icon: Icons.local_fire_department_outlined),
            _vDivider(),
          ],
          _StatTile(
              value: '${result.reps}',
              label: 'Reps',
              icon: Icons.repeat),
        ],
      ),
    );
  }

  Widget _vDivider() => Container(
        width: 1, height: 56, color: Colors.white12);
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Icon(icon, size: 18, color: AppTheme.onSurfaceMuted),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: valueColor ?? AppTheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  color: AppTheme.onSurfaceMuted, fontSize: 11)),
        ],
      ),
    );
  }
}

// ── Summary card ──────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final String summary;
  const _SummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_awesome, size: 16, color: AppTheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              summary,
              style: const TextStyle(
                  fontSize: 13, color: AppTheme.onSurface, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Recommendation card ───────────────────────────────────────────────────────

class _RecommendationCard extends StatelessWidget {
  final String text;
  const _RecommendationCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primary.withValues(alpha: 0.15),
            ),
            child: const Icon(Icons.tips_and_updates_outlined,
                size: 14, color: AppTheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Actions row ───────────────────────────────────────────────────────────────

class _ActionsRow extends StatelessWidget {
  final PairingStatus finalStatus;
  final WidgetRef ref;
  const _ActionsRow({required this.finalStatus, required this.ref});

  @override
  Widget build(BuildContext context) {
    final isSuccess = finalStatus == PairingStatus.sessionComplete;
    return Column(
      children: [
        if (isSuccess)
          SizedBox(
            width: 301,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _coral,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => context.go(AppRoutes.qrDisplay),
              child: const Text('Done'),
            ),
          ),
        const SizedBox(height: 12),
        SizedBox(
          width: 301,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('New Session'),
            onPressed: () async {
              await ref.read(pairingProvider.notifier).reset();
              if (context.mounted) {
                await ref.read(pairingProvider.notifier).startServer();
                if (context.mounted) context.go(AppRoutes.qrDisplay);
              }
            },
          ),
        ),
      ],
    );
  }
}
