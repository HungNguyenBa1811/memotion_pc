import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../models/settings_model.dart';

/// Persists [AppSettings] to SharedPreferences.
class SettingsService {
  static const _keyHttpUrl     = 'backend_http_url';
  static const _keyWsUrl       = 'backend_ws_url';
  static const _keyCameraIndex = 'camera_index';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      backendBaseUrl: prefs.getString(_keyHttpUrl) ?? AppConstants.defaultBackendHttp,
      backendWsBase:  prefs.getString(_keyWsUrl)   ?? AppConstants.defaultBackendWs,
      cameraIndex:    prefs.getInt(_keyCameraIndex) ?? 0,
    );
  }

  Future<void> save(AppSettings s) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString(_keyHttpUrl,     s.backendBaseUrl),
      prefs.setString(_keyWsUrl,       s.backendWsBase),
      prefs.setInt(   _keyCameraIndex, s.cameraIndex),
    ]);
  }

  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_keyHttpUrl),
      prefs.remove(_keyWsUrl),
      prefs.remove(_keyCameraIndex),
    ]);
  }
}
