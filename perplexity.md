Đây là toàn bộ research về `flutter_lite_camera` — đọc kỹ phần **"Hạn chế nghiêm trọng"** trước khi quyết định dùng.

***

## Tóm tắt nhanh

`flutter_lite_camera` (v0.0.2) là plugin **hoàn toàn độc lập**, không dùng `CameraController`, không dùng `camera_platform_interface`. API cực đơn giản nhưng đổi lại có constraint cứng không thể thay đổi được. [github](https://github.com/yushulx/flutter_lite_camera)

***

## API lấy frame — Không phải Stream, là Poll-loop thủ công

Không có `Stream`, không có callback, không có `startImageStream`. Thay vào đó là một method đồng bộ-theo-yêu-cầu: [github](https://github.com/yushulx/flutter_lite_camera)

```dart
Map<String, dynamic> frame = await _flutterLiteCamera.captureFrame();
```

Bạn tự xây dựng capture loop bằng `Future.delayed`: [pub](https://pub.dev/packages/flutter_lite_camera/example)

```dart
Future<void> _captureFrames() async {
  if (!_isCameraOpened || !_shouldCapture) return;

  final Map<String, dynamic> frame = await _flutterLiteCamera.captureFrame();

  if (frame.containsKey('data')) {
    final Uint8List rgbBuffer = frame['data'];   // ← raw bytes
    final int width            = frame['width'];  // luôn = 640
    final int height           = frame['height']; // luôn = 480
    // xử lý frame...
  }

  if (_shouldCapture) {
    Future.delayed(const Duration(milliseconds: 30), _captureFrames); // ~33fps
  }
}
```

### Cấu trúc `frame` map đầy đủ:

| Key | Type | Giá trị |
|---|---|---|
| `'data'` | `Uint8List` | Raw pixel bytes — **RGB888** (3 bytes/pixel) |
| `'width'` | `int` | Cứng = **640** |
| `'height'` | `int` | Cứng = **480** |

***

## Format pixel — RGB888, KHÔNG phải BGRA

Đây là điểm khác biệt quan trọng với `camera_windows` fork: [dev](https://dev.to/yushulx/how-to-build-a-lightweight-flutter-camera-plugin-for-windows-linux-and-macos-4hia)

- **Format**: `RGB888` — 3 bytes/pixel, thứ tự `R, G, B`
- **Resolution**: Cứng **640×480**, không thể thay đổi
- Nếu cần render lên `Canvas`, phải convert sang RGBA8888 thủ công (swap B↔R, thêm alpha=255): [pub](https://pub.dev/packages/flutter_lite_camera/example)

```dart
final pixels = Uint8List(width * height * 4); // RGBA buffer
for (int i = 0; i < width * height; i++) {
  pixels[i * 4]     = rgbBuffer[i * 3 + 2]; // B ← lấy từ B của RGB
  pixels[i * 4 + 1] = rgbBuffer[i * 3 + 1]; // G
  pixels[i * 4 + 2] = rgbBuffer[i * 3];     // R
  pixels[i * 4 + 3] = 255;                  // A
}
```

- Nếu gửi qua **WebSocket** dưới dạng raw bytes thì không cần convert — gửi thẳng `frame['data']`

***

## Init Flow — API hoàn toàn riêng, không có CameraController

Không có `CameraPreview`, không có `Texture` widget. Bạn tự render frame qua `CustomPaint`: [pub](https://pub.dev/packages/flutter_lite_camera/example)

```dart
import 'package:flutter_lite_camera/flutter_lite_camera.dart';

final _camera = FlutterLiteCamera(); // singleton instance

// Bước 1: Liệt kê devices
final List<String> devices = await _camera.getDeviceList();
// devices[i] là tên device string (e.g. "USB2.0 HD UVC WebCam")

// Bước 2: Mở camera theo index
final bool opened = await _camera.open(0); // index, không phải CameraDescription

// Bước 3: Poll frames thủ công (xem vòng lặp ở trên)
_captureFrames();

// Bước 4: Release
await _camera.release();
```

**Không có**: `CameraController`, `CameraPreview`, `availableCameras()`, `ResolutionPreset`, `enableAudio`, `fps` param — hoàn toàn tách biệt khỏi `camera` ecosystem. [github](https://github.com/yushulx/flutter_lite_camera)

***

## Pubspec & Version Constraints

```yaml
dependencies:
  flutter_lite_camera: ^0.0.2
```

| Constraint | Giá trị |
|---|---|
| **Version hiện tại** | `0.0.2` (pub.dev) |
|  **Flutter SDK** | ≥ 3.0.0 |
| **Dart SDK** | Không publish rõ (infer ≥ 2.17 từ Flutter 3.0) |
| **Platforms** | Windows ✅, Linux ✅, macOS ✅ |
| **Android/iOS** | ❌ Không hỗ trợ |
| **Cần `camera` package?** | ❌ Không — hoàn toàn độc lập |
| **Maintained?** | ✅ Active — last release 2025  [pub](https://pub.dev/packages/flutter_lite_camera/changelog) |

***

## Hạn chế nghiêm trọng cần cân nhắc

Trước khi dùng cho `CameraService` gửi WebSocket, có 3 điều phải biết: [dev](https://dev.to/yushulx/how-to-build-a-lightweight-flutter-camera-plugin-for-windows-linux-and-macos-4hia)

1. **Resolution cứng 640×480** — không thể dùng `ResolutionPreset.high` hay bất kỳ preset nào. Đây là giới hạn native layer, không override được
2. **Không có live preview widget** — phải tự vẽ `ui.Image` lên `CustomPaint` mỗi 30ms, tốn CPU hơn `Texture`-based `CameraPreview`
3. **Poll thay vì push** — không có event-driven callback. Nếu xử lý frame chậm hơn 30ms, frames sẽ bị drop hoặc queue lại. Phải dùng `Isolate` nếu cần xử lý nặng để không block vòng loop

***

## So sánh nhanh 3 lựa chọn

| | `flutter_lite_camera` | `yushulx/flutter_camera_windows` fork | `camera_desktop` |
|---|---|---|---|
| Frame access Windows | ✅ Poll (`captureFrame`) | ✅ Stream callback | ❌ |
| Format | RGB888 | BGRA8888 | N/A |
| Resolution | **Cứng 640×480** | Theo `ResolutionPreset` | Theo preset |
| CameraController | ❌ | Dùng platform API | ✅ |
| Maintained | ✅ 2025 | ⚠️ Stale 2023 | ✅ 2025 |
| Pub.dev | ✅ | ❌ git only | ✅ |

Nếu mục tiêu là **gửi frame qua WebSocket ở 640×480** thì `flutter_lite_camera` là lựa chọn đơn giản nhất và ít rủi ro nhất. Nếu cần resolution cao hơn thì fork `flutter_camera_windows` là con đường duy nhất hiện tại, dù stale.