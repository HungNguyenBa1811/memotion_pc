# Memotion PC — Implementation Plan

---

## Checklist §6 vs Code (WORKOUT_INTEGRATION.md)

| # | Item | Status | File |
|---|------|--------|------|
| 1 | PC WS server lắng nghe port từ QR payload | ✅ | `local_ws_server.dart` |
| 2 | Validate JWT pair_request | ⚠️ | Chỉ check `.isEmpty`; backend implicit validate — chấp nhận được |
| 3 | Gửi pair_confirmed sau validate | ✅ | `pairing_provider.dart` |
| 4 | Start camera + POST /api/pose/sessions | ✅ | `pairing_provider.dart` + `backend_ws_service.dart` |
| 5 | Gửi session_started { session_id } | ✅ | `pairing_provider.dart` |
| 6 | Stream frames → backend WebSocket | ✅ | `_startFramePipe()` |
| 7 | **Render trainer video + real-time score overlay** | ❌ | **Thiếu hoàn toàn** — không có `video_player`, `videoPath` không qua pairing |
| 8 | DELETE /api/pose/sessions/{id} → final results | ✅ | Fixed Sprint 1 |
| 9 | PUT /api/tasks/{workoutId}/complete | ✅ | Fixed Sprint 1 |
| 10 | Gửi session_complete cho Android | ✅ | `pairing_provider.dart` |
| 11 | Heartbeat: respond pong khi nhận ping | ✅ | `_handleMessage` |
| 12 | Timeout 20s khi không nhận ping | ⚠️ | Code: **15s**, docs: **20s** — mismatch |
| 13 | session_failed khi lỗi | ✅ | `_handlePairRequest`, `_onBackendFailed` |

### Gaps ngoài checklist

| Gap | Mức độ | Ghi chú |
|-----|--------|---------|
| `HeartbeatManager` gửi pong chủ động mỗi 5s (không cần thiết) | Low | `onPingSend` callback gọi sai hướng — không crash nhưng gửi thừa message |
| Phase 1/2 (detection/calibration) không có UI | Medium | PC nhảy thẳng vào stream; backend vẫn chạy phase nội bộ; UI hiện chỉ có `_StageBadge` |

---

## Sprint 1 — Critical Bug Fixes ✅ DONE
> Target: App chạy đúng end-to-end với backend

- [x] **1.1** Fix `fetchResult()` dùng GET → DELETE (`backend_ws_service.dart`)
- [x] **1.2** Thêm `markTaskCompleted()` vào `BackendWsService` (`PUT /api/tasks/{id}/complete`)
- [x] **1.3** Gọi `markTaskCompleted()` trong `endSession()` trước khi gửi `session_complete` (`pairing_provider.dart`)
- [x] **1.4** Fix operator precedence bug `LanService.getLocalIp()` (`lan_service.dart`)

---

## Sprint 2 — Trainer Video (Gap #7 — Blocker)
> Target: PC hiển thị trainer video như mobile PoseTrainingScreen

- [x] **2.1** Thêm `media_kit` + `media_kit_video` + `media_kit_libs_windows_video` vào `pubspec.yaml`; init trong `main.dart`
- [x] **2.2** Thêm `fetchWorkoutVideoPath(workoutId, jwt)` vào `BackendWsService` — `GET /api/tasks/{id}` → `video_path`
- [x] **2.3** Fetch videoPath song song với createSession trong `_connectToBackend()`; lưu vào `SessionConfig.videoPath`
- [x] **2.4** `ExerciseScreen`: trainer video full panel, webcam 240×180 PiP góc dưới-trái (ClipRRect r12)

---

## Sprint 3 — Windows-specific & Polish
> Target: App stable, không crash trên Windows

- [x] **3.1** Fix heartbeat timeout: `AppConstants.heartbeatTimeout` 15s → 20s
- [x] **3.2** Min window size 1024×680 — `WM_GETMINMAXINFO` handler trong `win32_window.cpp` (DPI-aware)
- [ ] **3.3** Test firewall ports 8765-8800 — Windows Defender alert khi lần đầu bind port *(manual)*
- [x] **3.4** Refactor `HeartbeatManager` — bỏ `onPingSend`, thêm `receivedPing()`, chỉ track timeout từ phía Android

---

## Sprint 4 — Release Build & Full Flow Test
> Target: Build release, test full flow với Android

- [ ] **4.1** Uncomment JWT guards khi backend live (grep TODO(jwt))
- [ ] **4.2** `flutter build windows --release`
- [ ] **4.3** Test full flow: QR scan → pair → exercise (trainer video + webcam) → stop → result

---

## Status Log

| Date | Sprint | Task | Status |
|------|--------|------|--------|
| 2026-03-27 | — | Init plan | done |
| 2026-03-27 | 1 | 1.1 fetchResult GET→DELETE | done |
| 2026-03-27 | 1 | 1.2-1.3 markTaskCompleted() | done |
| 2026-03-27 | 1 | 1.4 LanService precedence bug | done |
| 2026-03-27 | — | Gap analysis vs WORKOUT_INTEGRATION.md | done |
| 2026-03-27 | 2 | 2.1-2.4 Trainer video + webcam PiP | done |
| 2026-03-27 | 3 | 3.1 Heartbeat timeout 15s→20s | done |
| 2026-03-27 | 3 | 3.2 Min window size WM_GETMINMAXINFO | done |
| 2026-03-27 | 3 | 3.4 Refactor HeartbeatManager | done |
| 2026-03-27 | — | Unit tests: 49 pass (heartbeat, models, backend_ws, local_ws, pairing) | done |
