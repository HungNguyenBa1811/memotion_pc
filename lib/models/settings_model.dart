import '../core/constants.dart';

class AppSettings {
  final String backendBaseUrl;
  final String backendWsBase;
  final int cameraIndex; // index into availableCameras()

  const AppSettings({
    required this.backendBaseUrl,
    required this.backendWsBase,
    required this.cameraIndex,
  });

  static AppSettings get defaults => const AppSettings(
        backendBaseUrl: AppConstants.defaultBackendHttp,
        backendWsBase: AppConstants.defaultBackendWs,
        cameraIndex: 0,
      );

  AppSettings copyWith({
    String? backendBaseUrl,
    String? backendWsBase,
    int? cameraIndex,
  }) =>
      AppSettings(
        backendBaseUrl: backendBaseUrl ?? this.backendBaseUrl,
        backendWsBase: backendWsBase ?? this.backendWsBase,
        cameraIndex: cameraIndex ?? this.cameraIndex,
      );
}
