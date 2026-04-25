# Mewt — Task Log

## Phase progression

1. ✅ **Phase 0** — Core mute engine + talk-while-muted (`82ba684`)
2. ✅ **Phase 1** — Global hotkey ⌥M / PTT ⌥Space + Settings, hybrid mute across AirPods/built-in/USB (`253622d`)
3. ✅ **Pre-Phase 2** — `MicStatus` enum + `MuteStateMachine` + `TalkingDebouncer` extract, DI refactor, 43 tests (`c670b91`)
4. ✅ **Phase 2** — Static mascot face + right-click tray quick toggle, 60 tests (`c925135`)
5. ✅ **Phase 3** — Floating overlay window (`0c0f30e`)
6. 🛠 **Phase 3.5 — Code-quality pass** *(in progress)*
7. ⏭ **Phase 4** — Animated pets + StoreKit 2 IAP

Plans: `docs/plans/phase-1-global-hotkey.md`, `docs/plans/phase-3-floating-overlay.md`
Lessons: `tasks/lessons.md`

---

## Phase 3.5 — Code-quality pass (Swift best practice + error handling)

**Goal:** ปรับปรุง error categorization ให้ถูกต้อง ไม่กลืน failure mode ผิด, ลด CoreAudio unsafe pointer code, เพิ่ม diagnostic logs, ขัด accessibility ของ UI surfaces — โดยไม่เปลี่ยนพฤติกรรม happy-path

### Scope (delivered)

- [x] **Error handling fix** — `AudioLevelMonitor` แยก `permissionDenied` / `engineStartFailed(Error)` ออกจาก `noInputDevice`; probe `AVCaptureDevice.authorizationStatus(for: .audio)` ก่อน throw permission error; tap removed before re-throw on engine.start() failure (no leaked tap state for retry)
- [x] **AppState mapping** — ลบ catch-all "Mic permission needed" ที่ misattribute non-permission failure; เพิ่ม helper `talkDetectionStatus(for:)` แทน duplication ระหว่าง `startLevelMonitor` กับ `refreshTalkDetectionOnly`; `refreshTalkDetectionOnly` ตอนนี้เคารพ `.permissionDenied` ที่ sticky (device hot-plug ห้ามเขียนทับ)
- [x] **MicMuteController cleanup** — แทนที่ `withMemoryRebound(to: UInt8.self, capacity:)` no-op ด้วย idiomatic `Unmanaged<CFString>` pattern (retain ownership ชัดเจน); เพิ่ม `sharedLog` static + log OSStatus failures ใน `setMuteElement` / `setScalarVolume` ผ่าน `.error` privacy `.public` — มอง Console ออกถ้า talk-while-muted regress
- [x] **Accessibility polish** — Quit button = `role: .destructive`; mute button = `accessibilityLabel` + `accessibilityValue` (state); `OverlayContentView` = `combine` children + label จาก mascot pose + `isButton` trait + hint
- [x] **Verify** — `xcodebuild build` clean + **83 tests ผ่าน** (เพิ่ม `deviceChangePreservesPermissionDenied` invariant)

### Files touched

| File | Change |
|---|---|
| `Mewt/Audio/AudioLevelMonitor.swift` | +`permissionDenied`, +`engineStartFailed(Error)`, TCC probe, tap rollback on engine fail, log restart errors with privacy `.public` |
| `Mewt/State/AppState.swift` | +`Logger`, +static `talkDetectionStatus(for:)`, route per-error catch arms, sticky-permission guard in `refreshTalkDetectionOnly` |
| `Mewt/Audio/MicMuteController.swift` | `Unmanaged<CFString>` for `deviceName`, +`sharedLog`, log OSStatus on `setMute` / `setVolume` failures |
| `Mewt/ContentView.swift` | mute-button `accessibilityLabel`/`Value`, Quit `role: .destructive` |
| `Mewt/Overlay/OverlayContentView.swift` | accessibility group + state-aware label + button trait + hint |
| `MewtTests/AppStateTests.swift` | +1 test for `refreshTalkDetectionOnly` permission invariant |

### Status: ✅ Verified

`xcodebuild build` succeeded; full test suite green (83/83, 0.038s)

### Constraints upheld

- Public surface of `AppState` unchanged → existing tests untouched
- Phase 2/3 verified flows preserved (mute, PTT, overlay drag, persistence)
- `XCTestConfigurationFilePath` env guard pattern intact

### Notes for next phase

- Engine-start error wrapper means `AppState` can now show distinct messages for "no mic", "permission denied", "engine unavailable" — Settings could expose a "Re-grant permission" deep link to System Settings when `talkDetection == .permissionDenied`. Out of scope here; flag for Phase 4 onboarding work.
- `MicMuteController` failure logs are subsystem `com.chaninlaw.Mewt` category `MicMute` — `log stream --predicate 'subsystem == "com.chaninlaw.Mewt"'` will surface them next time the talk-while-muted USB-leak issue is triaged.

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
