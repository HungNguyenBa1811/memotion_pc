import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../providers/pairing_provider.dart';

class QrDisplayScreen extends ConsumerStatefulWidget {
  const QrDisplayScreen({super.key});

  @override
  ConsumerState<QrDisplayScreen> createState() => _QrDisplayScreenState();
}

class _QrDisplayScreenState extends ConsumerState<QrDisplayScreen> {
  Timer? _countdownTimer;
  int _secondsLeft = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(pairingProvider.notifier).startServer();
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown(int expiryMs) {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining =
          (expiryMs - DateTime.now().millisecondsSinceEpoch) ~/ 1000;
      if (!mounted) return;
      setState(() => _secondsLeft = remaining.clamp(0, 600));
      if (_secondsLeft == 0) {
        _countdownTimer?.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pairingProvider);

    // Navigate when session is active
    ref.listen<PairingState>(pairingProvider, (prev, next) {
      if (next.status == PairingStatus.sessionActive) {
        context.go(
          AppRoutes.exercise,
          extra: {
            'session_id': next.sessionId ?? '',
            'exercise_type': next.sessionConfig?.exerciseType ?? '',
            'workout_id': next.sessionConfig?.workoutId ?? '',
          },
        );
      }
      // Start countdown when QR first appears
      if (next.tokenExpiryMs != null &&
          next.tokenExpiryMs != prev?.tokenExpiryMs) {
        _startCountdown(next.tokenExpiryMs!);
      }
    });

    return Scaffold(
      // Gear icon — top-right, only visible while awaiting pairing.
      floatingActionButton: state.status == PairingStatus.awaitingPairing ||
              state.status == PairingStatus.idle
          ? FloatingActionButton(
              mini: true,
              tooltip: 'Cài đặt',
              backgroundColor: AppTheme.surfaceContainer,
              onPressed: () => context.push(AppRoutes.settings),
              child: const Icon(Icons.settings_outlined,
                  color: AppTheme.onSurfaceMuted),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endTop,
      body: Row(
        children: [
          // ── Left panel: QR ──────────────────────────────────────────────
          Expanded(
            flex: 5,
            child: Container(
              color: AppTheme.surfaceContainer,
              child: _buildQrPanel(state),
            ),
          ),
          // ── Right panel: Instructions ────────────────────────────────────
          Expanded(
            flex: 4,
            child: _buildInstructionsPanel(state),
          ),
        ],
      ),
    );
  }

  Widget _buildQrPanel(PairingState state) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // QR or loading/error
        if (state.status == PairingStatus.starting)
          const CircularProgressIndicator()
        else if (state.qrPayload != null && !state.isTokenExpired)
          _buildQrCard(state)
        else if (state.status == PairingStatus.error)
          _buildErrorState(state.errorMessage)
        else
          _buildExpiredState(),

        const SizedBox(height: 24),

        // Refresh button
        if (state.status == PairingStatus.awaitingPairing)
          FilledButton.icon(
            onPressed: () => ref.read(pairingProvider.notifier).refreshToken(),
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh QR'),
          ),
      ],
    );
  }

  Widget _buildQrCard(PairingState state) {
    final qr = state.qrPayload!;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: QrImageView(
            data: qr.toJsonString(),
            version: QrVersions.auto,
            size: 280,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        // Countdown
        _CountdownBadge(secondsLeft: _secondsLeft),
        const SizedBox(height: 8),
        Text(
          '${qr.ip}:${qr.port}',
          style: const TextStyle(
            color: AppTheme.onSurfaceMuted,
            fontSize: 12,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  Widget _buildExpiredState() {
    return const Column(
      children: [
        Icon(Icons.qr_code_2, size: 80, color: AppTheme.onSurfaceMuted),
        SizedBox(height: 16),
        Text(
          'QR code đã hết hạn',
          style: TextStyle(color: AppTheme.onSurfaceMuted),
        ),
      ],
    );
  }

  Widget _buildErrorState(String? message) {
    return Column(
      children: [
        const Icon(Icons.error_outline, size: 80, color: AppTheme.error),
        const SizedBox(height: 16),
        Text(
          message ?? 'Lỗi không xác định',
          style: const TextStyle(color: AppTheme.error),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => ref.read(pairingProvider.notifier).startServer(),
          child: const Text('Thử lại'),
        ),
      ],
    );
  }

  Widget _buildInstructionsPanel(PairingState state) {
    return Padding(
      padding: const EdgeInsets.all(48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Kết nối với Android',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            _statusText(state.status),
            style: const TextStyle(color: AppTheme.primary, fontSize: 15),
          ),
          const SizedBox(height: 40),
          _Step(
            number: 1,
            text: 'Mở app Memotion trên điện thoại',
            active: state.status == PairingStatus.awaitingPairing,
            done: state.status.index > PairingStatus.awaitingPairing.index,
          ),
          const SizedBox(height: 20),
          _Step(
            number: 2,
            text: 'Vào màn Workout → chọn bài tập → nhấn "Kết nối PC"',
            active: state.status == PairingStatus.awaitingPairing,
            done: state.status.index > PairingStatus.awaitingPairing.index,
          ),
          const SizedBox(height: 20),
          _Step(
            number: 3,
            text: 'Quét mã QR hiển thị bên trái',
            active: state.status == PairingStatus.awaitingPairing,
            done: state.status.index > PairingStatus.awaitingPairing.index,
          ),
          const SizedBox(height: 20),
          _Step(
            number: 4,
            text: 'Đợi kết nối backend và bắt đầu luyện tập',
            active: state.status == PairingStatus.paired,
            done: state.status == PairingStatus.sessionActive,
          ),
          if (state.status == PairingStatus.disconnected ||
              state.status == PairingStatus.error) ...[
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.error.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, color: AppTheme.error),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      state.errorMessage ?? 'Đã mất kết nối với Android',
                      style: const TextStyle(color: AppTheme.error),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _statusText(PairingStatus status) {
    return switch (status) {
      PairingStatus.idle => '',
      PairingStatus.starting => 'Đang khởi động server...',
      PairingStatus.awaitingPairing => 'Đang chờ Android kết nối...',
      PairingStatus.paired => 'Đã kết nối! Đang khởi tạo session...',
      PairingStatus.sessionActive => 'Session đang chạy',
      PairingStatus.sessionComplete => 'Session hoàn tất',
      PairingStatus.error => 'Lỗi kết nối',
      PairingStatus.disconnected => 'Mất kết nối',
    };
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _CountdownBadge extends StatelessWidget {
  final int secondsLeft;
  const _CountdownBadge({required this.secondsLeft});

  @override
  Widget build(BuildContext context) {
    final minutes = secondsLeft ~/ 60;
    final seconds = secondsLeft % 60;
    final expired = secondsLeft == 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: expired
            ? AppTheme.error.withValues(alpha: 0.2)
            : AppTheme.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            expired ? Icons.timer_off : Icons.timer,
            size: 16,
            color: expired ? AppTheme.error : AppTheme.primary,
          ),
          const SizedBox(width: 6),
          Text(
            expired
                ? 'Hết hạn'
                : 'Hết hạn sau ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
            style: TextStyle(
              color: expired ? AppTheme.error : AppTheme.primary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int number;
  final String text;
  final bool active;
  final bool done;

  const _Step({
    required this.number,
    required this.text,
    this.active = false,
    this.done = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done
                ? AppTheme.primary
                : active
                    ? AppTheme.primary.withValues(alpha: 0.2)
                    : Colors.white12,
          ),
          alignment: Alignment.center,
          child: done
              ? const Icon(Icons.check, size: 18, color: Colors.white)
              : Text(
                  '$number',
                  style: TextStyle(
                    color: active ? AppTheme.primary : AppTheme.onSurfaceMuted,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              text,
              style: TextStyle(
                color: done || active ? AppTheme.onSurface : AppTheme.onSurfaceMuted,
                height: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
