import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_lite_camera/flutter_lite_camera.dart';
import 'package:image/image.dart' as img;

/// Manages the PC webcam via [FlutterLiteCamera].
///
/// Exposes a broadcast [frameStream] of JPEG-encoded frames at ~30fps.
/// Resolution is fixed at 640×480 (native constraint of the plugin).
class CameraService {
  final _lite = FlutterLiteCamera();
  bool _opened = false;
  bool _running = false;

  final _frameController = StreamController<Uint8List>.broadcast();

  /// JPEG frames (~30fps, 640×480, quality 75).
  Stream<Uint8List> get frameStream => _frameController.stream;

  bool get isInitialized => _opened;

  /// Opens the camera at [cameraIndex] and starts the capture loop.
  Future<void> init({int cameraIndex = 0}) async {
    final devices = await _lite.getDeviceList();
    if (devices.isEmpty) throw StateError('No camera found on this device.');

    final idx = cameraIndex.clamp(0, devices.length - 1);
    final ok = await _lite.open(idx);
    if (!ok) throw StateError('Failed to open camera "${devices[idx]}".');

    _opened = true;
    _running = true;
    _captureLoop();
  }

  Future<void> _captureLoop() async {
    while (_running && !_frameController.isClosed) {
      try {
        final frame = await _lite.captureFrame();
        final bytes = frame['data'] as Uint8List?;
        final w = (frame['width'] as int?) ?? 640;
        final h = (frame['height'] as int?) ?? 480;

        if (bytes != null) {
          final jpeg = _toJpeg(bytes, w, h);
          if (jpeg != null && !_frameController.isClosed) {
            _frameController.add(jpeg);
          }
        }
      } catch (e) {}
      // ~33fps — yield to event loop between frames
      await Future.delayed(const Duration(milliseconds: 30));
    }
  }

  /// Encodes an RGB888 buffer to JPEG at quality 75.
  Uint8List? _toJpeg(Uint8List rgb, int w, int h) {
    try {
      final raw = img.Image.fromBytes(
        width: w,
        height: h,
        bytes: rgb.buffer,
        format: img.Format.uint8,
        numChannels: 3,
        order: img.ChannelOrder.bgr,
      );
      return Uint8List.fromList(img.encodeJpg(raw, quality: 75));
    } catch (e) {
      return null;
    }
  }

  Future<void> dispose() async {
    _running = false;
    if (_opened) {
      await _lite.release();
      _opened = false;
    }
    if (!_frameController.isClosed) await _frameController.close();
  }
}
