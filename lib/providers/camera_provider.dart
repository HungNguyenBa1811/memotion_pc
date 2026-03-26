import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Latest JPEG frame from the webcam, updated ~33fps by [PairingNotifier].
/// Null until camera is initialised and first frame arrives.
/// Read by [_CameraPreviewLayer] to render a live preview via Image.memory.
final cameraPreviewProvider = StateProvider<Uint8List?>((ref) => null);
