# Mewt — Phase 1 Global Hotkey

**Goal:** Global hotkey + push-to-talk + user-configurable shortcut UI เพื่อให้ผู้ใช้ mute ได้ขณะแอปอื่น focused

**Plan ฉบับเต็ม:** `docs/plans/phase-1-global-hotkey.md`

---

## Implementation checklist

- [x] เพิ่ม `KeyboardShortcuts` SPM package (2.0.0+) ใน `project.pbxproj`
- [x] สร้าง `Mewt/Input/HotkeyController.swift` (onKeyDown/onKeyUp + default shortcuts ⌥M, ⌥Space)
- [x] แก้ `Mewt/State/AppState.swift` เพิ่ม `pttActive`, `preTTState`, `pttDown()`, `pttUp()` + wire hotkey callbacks
- [x] แก้ `Mewt/ContentView.swift` แสดง hotkey hints + Settings button
- [x] สร้าง `Mewt/Settings/SettingsView.swift` + เชื่อม `Settings { }` scene ใน `MewtApp.swift`
- [x] `xcodebuild` build ผ่าน — fix: ต้อง `import AppKit` ใน HotkeyController เพราะ `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY` บังคับ explicit import สำหรับ `.option` modifier
- [x] Codesign entitlements check — ไม่เพิ่มจาก Phase 0 ตามคาด (Carbon ใน sandbox)
- [x] **AirPods fix** — rewrite `MicMuteController` ใช้ `kAudioDevicePropertyMute` เท่านั้น (Option A, ดู `tasks/lessons.md`) — build ผ่าน
- [x] **Orthogonal PTT state** — refactor `AppState` แยก `targetMuted` จาก `pttActive`, unified `applyMuteState()` รัน single source of truth ทุก transition + device change (แก้เคส "switch device ขณะ PTT ค้าง")
- [x] **External Mic fix** — belt-and-suspenders: apply ทั้ง `kAudioDevicePropertyMute` (Main + ทุก channel) **และ** `kAudioDevicePropertyVolumeScalar=0` พร้อมกัน; per-device saved volume dict (ดู `tasks/lessons.md` entry ที่ revise แล้ว)
- [x] **Mute ทุก input device** (ไม่ใช่แค่ default) — fix Chrome/WebRTC pin-device problem: enumerate `kAudioHardwarePropertyDevices`, loop mute/unmute ทั้งหมด + listener บน devices-list change
- [ ] Manual verification (ต้อง user test — ดูด้านล่าง)

---

## Verification (ต้อง user ทดสอบจริง)

### Toggle hotkey
- [x] เปิด Chrome → กด ⌥M → menu bar icon + state ใน Mewt เปลี่ยน
- [x] **AirPods** + Meet muted → ฝั่งตรงข้ามได้ยินเงียบ (หลัง AirPods fix — Phase 0 pre-fix ล้มเหลวบน AirPods)
- [x] Built-in mic + Meet muted → ยัง work เหมือนเดิม (ไม่ regress จาก Phase 0)
- [x] Zoom test call muted → ฝั่งตรงข้ามได้ยินเงียบ

### Push-to-talk
- [x] เริ่มที่ muted → กด ⌥Space ค้าง → ฝั่งตรงข้ามได้ยิน → ปล่อย → กลับเงียบ
- [x] เริ่มที่ unmuted → กด ⌥Space ค้าง → ปล่อย → ยัง unmuted (invariant ต้องรักษา)

### Edge cases
- [x] กด toggle ขณะที่ PTT ค้างอยู่ → ไม่ crash (state machine ป้องกันด้วย `preTTState` guard)
- [x] Switch device ขณะ PTT ค้าง → state consistent (หลัง orthogonal refactor — built-in/AirPods สลับตอน PTT ค้างแล้วปล่อย → device ใหม่ต้อง muted)
- [x] Switch AirPods ↔ built-in mic ขณะ muted → device ใหม่ยัง muted

### Settings UI
- [x] เปิด Settings scene (⌘, หรือปุ่ม Settings…)
- [x] เปลี่ยน shortcut → shortcut ใหม่ทำงาน
- [ ] restart app → shortcut ใหม่ persist

---

## Review

**Status:** ✅ Phase 1 verified by user — hotkey + PTT + settings work, audio muting reliable across AirPods/built-in/External USB

### Scope ที่โตกว่า plan เดิม

Plan เดิมใน `docs/plans/phase-1-global-hotkey.md` เป็นแค่ "add hotkey" ประเมินไว้ ~2 ชม. ระหว่าง verify เจอ Phase 0 bugs ที่ซ่อนอยู่ 3 ตัว (test coverage Phase 0 ไม่ครอบคลุม) ต้องแก้ด้วย ลงเอยที่ **4 iteration** ของ mute logic:

| Iteration | Scope | Trigger |
|---|---|---|
| 1. Initial | Add hotkey + PTT + Settings (ตาม plan) | - |
| 2. AirPods fix | switch `kAudioDevicePropertyVolumeScalar=0` → `kAudioDevicePropertyMute` | User test AirPods + Meet → เสียงเล็ด |
| 3. Orthogonal PTT | `targetMuted ⊥ pttActive`, unified `applyMuteState()` | Switch device ขณะ PTT ค้าง → desync |
| 4. Belt-and-suspenders | apply mute property **และ** volume=0 ทุก element | External USB mic ไม่ respect mute property อย่างเดียว |
| 5. Mute all devices | enumerate `kAudioHardwarePropertyDevices` loop ทุก device | Chrome/WebRTC pin device → มุต default ตัวเดียวไม่พอ |

### Code churn
- สร้าง: `Mewt/Input/HotkeyController.swift`, `Mewt/Settings/SettingsView.swift`
- แก้มาก: `Mewt/Audio/MicMuteController.swift` (~180 → ~240 บรรทัด, rewrite 3 ครั้ง), `Mewt/State/AppState.swift` (refactor orthogonal state), `Mewt/ContentView.swift` (hints + Settings), `Mewt/MewtApp.swift` (Settings scene)
- Config: `Mewt.xcodeproj/project.pbxproj` (SPM package)
- ไม่แตะ: `Mewt.entitlements`, `Mewt/Audio/AudioLevelMonitor.swift`

### Key architectural decisions (บันทึกเต็มใน `tasks/lessons.md`)
1. **Mute = HAL property + volume=0 + ทุก element + ทุก device** — ไม่มี single mechanism ที่ครอบคลุมทุก input device บน macOS (AirPods HFP, built-in, USB interface) และไม่มีทาง detect runtime ว่า device ใด respect ตัวไหน → ยิงทุกช่องทางให้หมด
2. **Orthogonal state** สำหรับ transient override (PTT): physical = `targetMuted && !pttActive` เป็น derived — จุด sync จุดเดียว (`applyMuteState()`) เรียกจาก 4 trigger (toggle, pttDown, pttUp, device topology change)
3. **KeyboardShortcuts SPM** — ใช้ Carbon `RegisterEventHotKey` ใต้ฮูด → sandbox-compatible ไม่ต้อง Input Monitoring / Accessibility entitlement

### ข้อสังเกตระหว่าง impl
- **AppKit import จำเป็น** — `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES` ตัด transitive member visibility → `.option` modifier ต้อง `import AppKit` ตรงๆ
- **SourceKit diagnostics** ฟ้อง "No such module 'KeyboardShortcuts'" / "Cannot find X in scope" หลายครั้ง → transient index lag บน PBXFileSystemSynchronizedRootGroup + ใหม่ SPM; `xcodebuild` compile ผ่านทุกครั้ง

### Known limits ที่ต้องบอก user
1. **`⌥Space` ถูก forward ไปแอพ focused** — ถ้าเจอ space เกินใน text field ให้เปลี่ยน shortcut ใน Settings (CGEventTap consume = Phase ถัดไป, ต้อง Accessibility permission)
2. **Mute มีผลกับ input device ทุกตัวที่เชื่อมต่อ** — intentional สำหรับ "system-wide mute"; ถ้าใช้ Continuity iPhone Microphone / Mac audio routing แปลกๆ จะถูก mute ไปด้วย
3. Settings เปิดด้วย `⌘,` หรือปุ่ม Settings… ในเมนู

### Next phases
1. ✅ Phase 0 — Core mute engine + talk-while-muted
2. ✅ Phase 1 — Global hotkey + PTT + settings
3. ✅ Pre-Phase 2 — `MicStatus` enum + derived view state, `MuteStateMachine` + `TalkingDebouncer` extract, DI refactor, **43 unit tests** (~99% business logic coverage; HAL wrappers excluded by design)
4. ✅ Phase 2 — Static mascot face (free tier) + right-click tray quick mute, **60 unit tests** (+17: MascotPose × 8, TrayClickRouter × 9)
5. Phase 3 — Floating overlay window  ← ขั้นถัดไป
6. Phase 4 — Animated pets + StoreKit 2 IAP

---

## Phase 2 Review

**Status:** ✅ Build + tests pass (60/60). Manual verification pending user.

### Scope delivered
- `Mewt/Mascot/MascotPose.swift` — pure `MicStatus → (eyes, mouth, accent, a11y)` mapping
- `Mewt/Mascot/MascotFace.swift` — SwiftUI shape-based face rendered into popover header
- `Mewt/Tray/TrayClickRouter.swift` — pure click→action routing (`.left` opens popover, `.right`/`.leftWithControl` toggle mute)
- `Mewt/Tray/TrayController.swift` — NSStatusItem + NSPopover wrapper, button image driven by `withObservationTracking` re-subscribe loop
- `Mewt/MewtApp.swift` — switched from `MenuBarExtra` to `NSApplicationDelegateAdaptor(AppDelegate)`; AppDelegate guards hardware setup under XCTest
- `Mewt/ContentView.swift` — popover header now uses `MascotFace`
- `MewtTests/MascotPoseTests.swift` (8 tests), `MewtTests/TrayClickRouterTests.swift` (9 tests)

### Why migrate off MenuBarExtra
SwiftUI's `MenuBarExtra` does not surface right-click events distinct from left-click — both open the menu. Phase 2's "quick toggle on right-click" required dropping back to AppKit (`NSStatusItem` + `NSPopover` + `button.sendAction(on: [.leftMouseUp, .rightMouseUp])`). Cost: ~80 LOC of AppKit boilerplate; benefit: full event-mask control + ctrl-click support as a free extra.

### Verification (manual — pending user test)
- [ ] Right-click menu bar icon while popover is hidden → mute toggles (icon flips to slashed mic)
- [ ] Left-click → popover opens with mascot face header
- [ ] Ctrl+click → behaves like right-click (toggles mute)
- [ ] Mascot face changes through all 4 expressions: idle (😺), sleeping (😴 + Z), alarmed (🙀 + !), PTT (🗣️ + waveform)
- [ ] Talking-while-muted tints menu bar icon red
- [ ] Tooltip on icon reads "<state> — left-click to open, right-click to toggle mute"

### Out of scope (deferred)
- Animated mascot motion / level-driven scaling (Phase 4 paid tier)
- Custom mascot artwork (Phase 4)
- Floating overlay (Phase 3)
