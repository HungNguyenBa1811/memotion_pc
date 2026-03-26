import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/settings_model.dart';
import '../services/settings_service.dart';

class SettingsNotifier extends StateNotifier<AppSettings> {
  final SettingsService _service;

  SettingsNotifier(this._service) : super(AppSettings.defaults);

  /// Loads persisted settings from secure storage. Call once at app start.
  Future<void> load() async {
    state = await _service.load();
  }

  Future<void> update(AppSettings updated) async {
    state = updated;
    await _service.save(updated);
  }

  Future<void> reset() async {
    await _service.reset();
    state = AppSettings.defaults;
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier(SettingsService());
});
