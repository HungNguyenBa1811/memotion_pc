import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router.dart';
import 'core/theme.dart';
import 'providers/settings_provider.dart';

void main() {
  runApp(const ProviderScope(child: MemotionPcApp()));
}

class MemotionPcApp extends ConsumerStatefulWidget {
  const MemotionPcApp({super.key});

  @override
  ConsumerState<MemotionPcApp> createState() => _MemotionPcAppState();
}

class _MemotionPcAppState extends ConsumerState<MemotionPcApp> {
  @override
  void initState() {
    super.initState();
    // Load persisted settings once at startup before any screen is shown.
    ref.read(settingsProvider.notifier).load();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Memotion PC',
      theme: AppTheme.dark,
      debugShowCheckedModeBanner: false,
      routerConfig: appRouter,
    );
  }
}
