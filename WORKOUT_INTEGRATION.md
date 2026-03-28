# Báo cáo kỹ thuật: Workout Flow — Mobile → Training Complete → PC Mode

**Ngày:** 2026-03-27 | **Vai trò:** Senior Mobile Developer | **Phiên bản đọc:** feature/base-app

---

## 1. Tổng quan luồng

Có **hai luồng song song** từ Workout Detail, dùng chung điểm kết thúc:

```
WorkoutDetailScreen
├── [Nút "Start Workout"]  ──→  LOCAL AI FLOW  ──→  WorkoutTrainingCompleteScreen
└── [Nút "Connect to PC"]  ──→  PC MODE FLOW   ──→  context.go('/home')
```

---

## 2. Chi tiết từng màn hình

### 2.1 WorkoutDetailScreen

**File:** `lib/features/workout/screens/workout_detail_screen.dart`
**Đầu vào:** `workoutId: String`

**Luồng khởi tạo:**
1. `initState` → `workoutDetailProvider.notifier.loadWorkout(workoutId)`
2. `GET /api/tasks/{task_id}` → `TaskDto` → `WorkoutTaskMapper.toWorkoutTask()`
3. Render: title, description, video preview (thumbnail + inline player)
4. Video URL = `${ApiConstants.baseUrl}${workout.videoPath}`

**Điểm phân nhánh (hai nút CTA):**

| Nút | Method | Route | Extra params |
|-----|--------|-------|-------------|
| Start Workout | `_startWorkoutExercise(workout)` | `/pose-detection` | `workoutId`, `exerciseType`, `videoPath` |
| Connect to PC | `_connectToPc(workout)` | `/pc-qr-scan` | `workoutId`, `exerciseType` |

**`exerciseType` mapping:**
```dart
WorkoutType.yoga     → 'yoga'
WorkoutType.exercise → 'arm_raise'
default              → 'arm_raise'
```

> **Bug cần biết:** `exerciseType` hiện chỉ map được `yoga` và `arm_raise`. Các type khác đều fallback về `arm_raise`.

---

### 2.2 LOCAL AI FLOW: PoseDetectionScreen → PoseTrainingScreen

#### Phase 1 & 2 — PoseDetectionScreen

**File:** `lib/features/workout/screens/pose_detection_screen.dart`
**Đầu vào:** `workoutId`, `exerciseType`, `videoPath`

**Khởi tạo:**
```
initState
  ├── CameraService.initialize(useFrontCamera: true)
  ├── poseSessionProvider.notifier.startSession(exerciseType)
  │     └── POST /api/pose/sessions { user_id, exercise_type, default_joint }
  │         ← { session_id, current_phase: 1, websocket_url }
  ├── poseSessionProvider.notifier.connectWebSocket()
  │     └── ws://100.27.167.208:8005/api/pose/sessions/{id}/ws
  └── CameraService.startStreaming(onFrame: (bytes, ts) → sendFrame(bytes, ts))
        └── 30fps: captureFrame() → JPEG → base64 → WebSocket
```

**Phase 1 — Detection:**
- Server trả về `PoseFrameResult` → phase=1, `{pose_detected, stable_count, progress, landmarks}`
- UI hiển thị progress bar, "đang phát hiện tư thế"
- **Khi `progress == 100%`** → server tự chuyển phase → WebSocket emit `PosePhase.calibration`

**Phase 2 — Calibration:**
- Server trả về `{current_joint, current_angle, user_max_angle, calibration_progress, queue_index, total_joints}`
- UI hiển thị khớp hiện tại đang đo, góc, hướng dẫn tư thế
- **Khi phase 2 hoàn thành** → server emit `PosePhase.sync`

**Chuyển màn:**
```dart
// Trong PoseDetectionScreen, lắng nghe phaseChanges stream
onPhaseChange(PosePhase.sync) → context.push('/pose-training', extra: {
  'workoutId': workoutId,
  'exerciseType': exerciseType,
  'videoPath': videoPath,
})
```

#### Phase 3 — PoseTrainingScreen

**File:** `lib/features/workout/screens/pose_training_screen.dart`
**Đầu vào:** `workoutId`, `exerciseType`, `videoPath`

**Khởi tạo:**
```
initState
  ├── CameraService (đã init từ phase 1, restart streaming)
  ├── VideoPlayerController.networkUrl(baseUrl + videoPath)  ← trainer video
  ├── Timer.periodic(1s) → elapsed seconds counter
  └── WebSocket session vẫn active từ trước
```

**Real-time data loop:**
```
Camera frame → WebSocket → Server AI
  Server → PoseFrameResult phase=3:
    { video_frame, current_score, rep_count, fatigue_level }
  → poseSessionProvider cập nhật state
  → UI update: score, repCount, fatigueLevel, elapsed time
```

**Khi user nhấn "Stop":**
```dart
poseSessionProvider.notifier.endSession()
  ├── CameraService.stopStreaming()
  ├── DELETE /api/pose/sessions/{sessionId}
  │     ← PoseSessionResults {
  │         total_score, rom_score, stability_score, flow_score,
  │         grade, total_reps, fatigue_level, duration_seconds,
  │         calibrated_joints, rep_scores, recommendations
  │       }
  └── state.finalResults = PoseSessionResults

→ context.push('/workout-training-complete', extra: {
    'workoutId': workoutId,
    'duration': _formatDuration(elapsedSeconds),
    'durationSeconds': elapsedSeconds,
  })
```

> **Gap nghiêm trọng:** `WorkoutTrainingCompleteScreen` nhận `workoutId + duration + durationSeconds` nhưng **không đọc `poseSessionProvider.finalResults`**. Toàn bộ màn complete (score 85, "Knee Extension", 92% accuracy) đang là **hardcode**. Cần fix trước khi ship.

---

### 2.3 WorkoutTrainingCompleteScreen

**File:** `lib/features/workout/screens/workout_training_complete_screen.dart`
**Đầu vào:** `workoutId: String`, `duration: String` (vd `"12:30"`), `durationSeconds: int`

**Hiện trạng UI (hardcode):**
- Score: `85` (static)
- Exercise name: `"Knee Extension"` (static)
- Accuracy: `"92%"` (static)
- Calories: `"45"` (static)
- Improvement cards: cố định 2 items

**Hai nút:**

| Nút | Action |
|-----|--------|
| Done | `workoutDetailProvider.notifier.markCompleted()` → `PUT /api/tasks/{id}/complete` → `context.go('/workout')` |
| To Homepage | `context.go('/home')` |

> `markCompleted()` chỉ gọi ở đây, sau khi training xong — đây là điểm duy nhất đánh dấu task hoàn thành trong local flow.

---

### 2.4 PC MODE FLOW

#### QrScanScreen

**File:** `lib/features/workout/screens/qr_scan_screen.dart`
**Đầu vào:** `workoutId`, `exerciseType`

**Luồng:**
1. Camera scan QR code từ màn hình PC app
2. Parse JSON: `{ "ip": "...", "port": 8080, "token": "...", "expires_at": 1711512000000 }`
3. `PcQrPayload.fromRawString(qrData)` → validate `isExpired`
4. Gọi `pcSessionProvider.notifier.connectToPc(payload, workoutId, exerciseType)`

**connectToPc internals:**
```dart
// 1. Kết nối WebSocket tới PC
PcPairingService.connect('ws://${payload.ip}:${payload.port}')

// 2. Lấy JWT
jwt = await TokenStorage.instance.getAccessToken()

// 3. Gửi pair_request
send(PcMessage.buildPairRequest(jwt, workoutId, exerciseType))
// → { "type": "pair_request", "jwt": "...", "session_config": { "workout_id": "...", "exercise_type": "..." } }

// 4. Bắt đầu Heartbeat
HeartbeatManager.start(
  onPing: () => send(PcMessage.buildHeartbeatPing()),  // every 5s
  onTimeout: () => _handleTimeout(),                    // after 15s no pong
)
```

**Sau khi QR valid → navigate:**
```dart
context.push('/pc-standby', extra: { 'workoutId': workoutId, 'exerciseType': exerciseType })
```

#### PcStandbyScreen

**File:** `lib/features/workout/screens/pc_standby_screen.dart`

**Trạng thái hiển thị theo `PcSessionStatus`:**
```
idle → connecting → paired → sessionStarted → sessionComplete
                                            ↘ sessionFailed / disconnected
```

**Listener xử lý trạng thái:**
```dart
ref.listen<PcSessionState>(pcSessionProvider, (_, next) {
  if (next.status == PcSessionStatus.sessionComplete) {
    context.go(AppRoutes.home);    // PC đã lưu kết quả lên backend → về home
  }
  if (next.status == sessionFailed || disconnected) {
    _showErrorAndPop(next.errorMessage);
  }
});
```

**PopScope:** `canPop: false` — user phải xác nhận disconnect trước khi thoát.

**Khi disconnect:** `pcSessionProvider.notifier.reset()` → dọn sạch state, `context.pop()`.

---

## 3. Message Protocol: Android ↔ PC (WebSocket)

### Android → PC

| Message | JSON | Timing |
|---------|------|--------|
| `pair_request` | `{"type":"pair_request","jwt":"...","session_config":{"workout_id":"...","exercise_type":"..."}}` | Ngay sau kết nối |
| `heartbeat_ping` | `{"type":"heartbeat_ping"}` | Mỗi 5 giây |

### PC → Android

| Message | JSON | Trigger |
|---------|------|---------|
| `pair_confirmed` | `{"type":"pair_confirmed"}` | PC xác nhận JWT hợp lệ |
| `session_started` | `{"type":"session_started","session_id":"..."}` | PC bắt đầu exercise session |
| `heartbeat_pong` | `{"type":"heartbeat_pong"}` | Trả lời ping |
| `session_complete` | `{"type":"session_complete"}` | PC lưu xong kết quả lên backend |
| `session_failed` | `{"type":"session_failed","reason":"..."}` | Lỗi bên PC |
| `error` | `{"error":"...","code":"500"}` | Lỗi chung |

**Heartbeat timeout:** 15 giây (3 ping bị bỏ qua) → `PcSessionStatus.disconnected`.

---

## 4. API Endpoints PC Mode phải tự gọi

| Endpoint | Method | Thời điểm | Ghi chú |
|----------|--------|-----------|---------|
| `/api/pose/sessions` | `POST` | Khi bắt đầu exercise | PC tạo session trên backend, giống mobile |
| `ws://.../api/pose/sessions/{id}/ws` | `WebSocket` | Trong lúc exercise | PC stream frames tới backend AI |
| `/api/pose/sessions/{id}` | `DELETE` | Khi user kết thúc | Lấy final results |
| `/api/tasks/{id}/complete` | `PUT` | Sau khi lấy results | Mark task done — **bắt buộc trước khi gửi `session_complete`** |

**JWT:** PC nhận JWT từ `pair_request.jwt` và dùng nó cho tất cả API calls trên.

---

## 5. Các vấn đề & Gaps cần lưu ý

### 5.1 Training Complete Screen — hardcode data

PC mode kết thúc bằng `context.go('/home')` và bỏ qua `WorkoutTrainingCompleteScreen` hoàn toàn. Đây là thiết kế đúng vì:
- PC tự lưu kết quả lên backend
- Android không có data để hiển thị
- User về home → pull fresh data từ API

**Khuyến nghị:** Sau khi về home, show một `SnackBar("Bài tập đã hoàn thành!")` là đủ.

### 5.2 markCompleted() — PC phải tự gọi

Trong local flow, `markCompleted()` gọi tại `WorkoutTrainingCompleteScreen`. Với PC mode, Android không đi qua màn này. **PC app phải tự gọi `PUT /api/tasks/{workoutId}/complete`** rồi mới gửi `session_complete`.

### 5.3 exerciseType mapping còn hạn chế

`_getExerciseType()` chỉ trả `yoga` hoặc `arm_raise`. Nếu backend pose detection yêu cầu type cụ thể hơn (`knee_extension`, `shoulder_press`...), cần mở rộng mapping này trên cả Android lẫn PC.

### 5.4 QR Token expiry

`PcQrPayload.isExpired` check phía Android. PC app cần:
- Generate QR với `expires_at` trong vòng 5 phút (chống replay attack)
- PC WS server cũng phải validate token độc lập, không chỉ tin vào client check

### 5.5 session_id chưa được dùng

`session_started` trả về `session_id`. Hiện `PcStandbyScreen` lưu vào state nhưng không dùng. Đây là hook để sau này Android có thể poll `/api/pose/sessions/{id}` lấy progress realtime nếu cần.

---

## 6. Checklist triển khai PC Mode

```
[ ] PC WS server lắng nghe trên port từ QR payload
[ ] Validate JWT nhận từ pair_request (verify với backend hoặc decode local)
[ ] Gửi pair_confirmed sau validate thành công
[ ] Start camera + tạo pose session: POST /api/pose/sessions
[ ] Gửi session_started { session_id }
[ ] Stream frames tới backend WebSocket (cùng protocol với mobile)
[ ] Render trainer video + real-time score overlay trên PC UI
[ ] Khi user Stop: DELETE /api/pose/sessions/{id} → lấy final results
[ ] PUT /api/tasks/{workoutId}/complete (dùng workoutId từ session_config)
[ ] Gửi session_complete cho Android
[ ] Heartbeat: respond pong mỗi khi nhận ping từ Android
[ ] Timeout: nếu không nhận ping trong 20s → coi Android disconnect, dừng session
[ ] Nếu lỗi: gửi session_failed { reason } rồi đóng WS
```

---

## 7. State Machine tóm tắt

```
ANDROID                              PC
  │                                   │
  │  ws connect                       │
  ├──────────────────────────────────►│
  │                                   │
  │  pair_request {jwt, config}       │
  ├──────────────────────────────────►│  validate JWT
  │                                   │  → paired state
  │              pair_confirmed        │
  │◄──────────────────────────────────┤
  │  status: paired                   │
  │                                   │  POST /api/pose/sessions
  │              session_started      │
  │◄──────────────────────────────────┤
  │  status: sessionStarted           │
  │                                   │
  │  ←─── heartbeat_ping (5s) ──────►│
  │  ◄─── heartbeat_pong ────────────┤
  │                                   │  [user exercises on PC]
  │                                   │  DELETE /api/pose/sessions/{id}
  │                                   │  PUT /api/tasks/{id}/complete
  │              session_complete     │
  │◄──────────────────────────────────┤
  │  → context.go('/home')            │  close WS
```

---

## 8. Key Files Reference

| File | Vai trò |
|------|---------|
| `lib/features/workout/screens/workout_detail_screen.dart` | Entry point, phân nhánh hai luồng |
| `lib/features/workout/screens/pose_detection_screen.dart` | Phase 1 (detection) + Phase 2 (calibration) |
| `lib/features/workout/screens/pose_training_screen.dart` | Phase 3 (sync + scoring) |
| `lib/features/workout/screens/workout_training_complete_screen.dart` | Màn kết quả (hiện hardcode) |
| `lib/features/workout/screens/qr_scan_screen.dart` | Scan QR từ PC |
| `lib/features/workout/screens/pc_standby_screen.dart` | Android chờ PC xử lý |
| `lib/features/workout/data/pose_detection_service.dart` | WebSocket session với backend AI |
| `lib/features/workout/data/pc_pairing_service.dart` | WebSocket peer-to-peer với PC |
| `lib/features/workout/data/heartbeat_manager.dart` | Ping/pong lifecycle |
| `lib/features/workout/data/camera_service.dart` | Camera init + frame streaming |
| `lib/features/workout/providers/pose_detection_provider.dart` | State: pose session (phase, score, results) |
| `lib/features/workout/providers/pc_session_provider.dart` | State: PC pairing lifecycle |
| `lib/features/workout/models/pose_detection_model.dart` | PosePhase, PoseFrameResult, PoseSessionResults |
| `lib/features/workout/models/pc_session_model.dart` | PcSessionStatus, PcQrPayload, PcMessage |
| `lib/core/network/api_constants.dart` | Base URL, endpoints |
