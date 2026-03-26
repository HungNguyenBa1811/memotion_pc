import 'package:go_router/go_router.dart';

import '../providers/pairing_provider.dart';
import '../screens/exercise_screen.dart';
import '../screens/qr_display_screen.dart';
import '../screens/result_screen.dart';
import '../screens/settings_screen.dart';
import 'constants.dart';

final appRouter = GoRouter(
  initialLocation: AppRoutes.qrDisplay,
  routes: [
    GoRoute(
      path: AppRoutes.qrDisplay,
      builder: (context, state) => const QrDisplayScreen(),
    ),
    GoRoute(
      path: AppRoutes.exercise,
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return ExerciseScreen(
          sessionId: extra['session_id'] as String? ?? '',
          exerciseType: extra['exercise_type'] as String? ?? '',
          workoutId: extra['workout_id'] as String? ?? '',
        );
      },
    ),
    GoRoute(
      path: AppRoutes.result,
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        final status =
            extra['status'] as PairingStatus? ?? PairingStatus.sessionComplete;
        return ResultScreen(finalStatus: status);
      },
    ),
    GoRoute(
      path: AppRoutes.settings,
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
);
