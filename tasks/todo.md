# Mewt — Task Log

## Phase progression

1. ✅ **Phase 0** — Core mute engine + talk-while-muted (`82ba684`)
2. ✅ **Phase 1** — Global hotkey ⌥M / PTT ⌥Space + Settings, hybrid mute across AirPods/built-in/USB (`253622d`)
3. ✅ **Pre-Phase 2** — `MicStatus` enum + `MuteStateMachine` + `TalkingDebouncer` extract, DI refactor, 43 tests (`c670b91`)
4. ✅ **Phase 2** — Static mascot face + right-click tray quick toggle, 60 tests (`c925135`)
5. ✅ **Phase 3** — Floating overlay window — *this commit*
6. ⏭ **Phase 4** — Animated pets + StoreKit 2 IAP

Plans: `docs/plans/phase-1-global-hotkey.md`, `docs/plans/phase-3-floating-overlay.md`
Lessons: `tasks/lessons.md`

---

## Phase 3 — Floating Overlay (delivered)

**Goal:** Mascot ลอยทุก Space + ทับ fullscreen, draggable, click = toggle mute, persist position. UI surface ของ talk-while-muted detection พร้อมเหตุผล

### Scope delivered

**ไฟล์ใหม่:**
- `Mewt/Overlay/OverlayPosition.swift` — pure value type (clamp + defaultOrigin) + 9 tests
- `Mewt/Overlay/OverlayWindow.swift` — `NSPanel` subclass (`.borderless + .nonactivatingPanel + .fullSizeContentView`, level `.statusBar`, collection `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`)
- `Mewt/Overlay/OverlayMouseTrackerView.swift` — `NSHostingView` subclass override `mouseDown` + `NSWindow.trackEvents` (smooth native drag, click discrimination, `acceptsFirstMouse=true`)
- `Mewt/Overlay/OverlayContentView.swift` — SwiftUI 64pt `MascotFace` + 16pt padding (ear ครบ ไม่โดน clip)
- `Mewt/Overlay/OverlayWindowController.swift` — install + observe visibility + drag handling + position persistence
- `Mewt/State/TalkDetectionStatus.swift` — enum 4 cases (`active` / `disabledByBluetooth(name)` / `unavailable` / `permissionDenied`) + `label` + `helpText` + 6 tests

**ไฟล์แก้:**
- `Mewt/MewtApp.swift` — ย้าย `AppState` ไปเป็น `@State` ของ `MewtApp` + AppDelegate รับผ่าน `static var pendingAppState`; install `OverlayWindowController` ใต้ XCTest guard
- `Mewt/State/AppState.swift` — เพิ่ม `overlayVisible` (UserDefaults), `talkDetection` (TalkDetectionStatus); refresh ตอน start + device change
- `Mewt/Settings/SettingsView.swift` — Overlay toggle + Talk-while-muted Detection section พร้อมเหตุผล
- `Mewt/ContentView.swift` — TalkDetectionRow ใน popover
- `Mewt/Audio/AudioLevelMonitor.swift` — pre-flight format guard + `AVAudioEngineConfigurationChange` notification handler + dispatch debouncer/callback ไป main
- `Mewt/Audio/MicMuteController.swift` — Hybrid mute strategy (Bluetooth `mute=1+vol=0`, wired `mute=1` only) + `defaultInputTransport()` helper

**Tests:** 60 → **82** (+22: 9 OverlayPosition + 4 overlayVisible + 6 TalkDetectionStatus + 3 device-change-talkDetection)

### Iterations ระหว่าง verify

| # | Issue | Trigger | Fix |
|---|---|---|---|
| 1 | Crash ตอน open Settings โดยไม่มี mic | `@Environment(AppState.self)` mandatory แต่ `@NSApplicationDelegateAdaptor` ไม่ Observable → scene cache nil | ย้าย AppState → `@State` ของ MewtApp + static hand-off |
| 2 | Crash ตอน launch (ไม่มี input device) | `installTap` ขว้าง NSException ที่ Swift try ดักไม่ได้ | Pre-flight check `inputFormat.channelCount > 0` → throw Swift error |
| 3 | Mascot ครึ่งหน้าหายขอบจอ + drag กระตุก | `MascotFace` ear render นอก frame; SwiftUI DragGesture roundtrip overhead | Panel 96pt + padding 16, default inset 32; `OverlayMouseTrackerView` ใช้ `NSWindow.trackEvents` (native event loop) |
| 4 | Talk-while-muted ใช้ไม่ได้ | `volume=0` บน external silence tap ด้วย; `mute=1` ก็ silence | Hybrid: Bluetooth = `mute+vol=0`, wired = `mute=1` only (no volume change → tap reads) |
| 5 | EXC_BAD_ACCESS ตอน device change | Engine recreate race + tap callback mutate isolated state | Single engine instance; subscribe `AVAudioEngineConfigurationChange`; nonisolated `process(buffer:)` + dispatch ไป main |

### Status: ✅ Verified by user

Verified: launch + mascot position + drag smooth + click toggle + Settings toggle + persistence + device switching no crash + talkDetection state surface ถูกต้อง

### Known limitations

- **Talk-while-muted alarm บน External Microphone (non-AirPods, non-built-in) ยังไม่ทำงาน** — บาง USB driver apply volume scaling ที่ pre-tap stage และ HAL mute ก็ silence tap ด้วย ทำให้ AVAudioEngine อ่าน silence. UI surface เป็น `talkDetection.active` แต่ alarm ไม่ trigger จริง. **TODO:** investigate alternative detection approach (เช่น Aggregate Device routing, AVCaptureSession path) — เก็บไว้หลัง Phase 4
- **`⌥Space` PTT ยังถูก forward ไปแอพ focused** — Phase 1 carry-over, ต้อง CGEventTap consume + Accessibility permission
