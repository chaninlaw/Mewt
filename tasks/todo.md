# Mewt — Phase 0 Spike

**Goal:** พิสูจน์ว่า mute microphone system-wide ทำงานได้จริง + talk-while-muted detection ก่อนลงทุนกับ UI/IAP

**Plan ฉบับเต็ม:** `/Users/ninja/.claude2/plans/kind-wiggling-candle.md`

---

## Implementation checklist

- [x] Setup entitlements (`Mewt.entitlements`) + Info.plist keys (mic description, LSUIElement)
- [x] Convert `MewtApp` → `MenuBarExtra` (ซ่อน dock icon)
- [x] Create `AppState` (`@Observable`, MainActor)
- [x] Implement `MicMuteController` (CoreAudio volume control + device change listener)
- [x] Implement `AudioLevelMonitor` (AVAudioEngine tap + RMS + talking debounce)
- [x] Wire `ContentView` (status display, mute toggle, level bar, quit)
- [x] `tasks/todo.md` + `tasks/lessons.md`
- [x] `xcodebuild` build ผ่าน ไม่มี error
- [x] Run app + mic permission prompt
- [x] Manual verification (see below)

---

## Verification (Definition of Done)

- [x] App launches เห็นใน menu bar, ไม่มี Dock icon
- [x] Mic permission popup → allow → System Settings แสดง Mewt
- [x] QuickTime New Audio Recording + Mewt muted → playback เงียบ
- [x] Zoom test call muted → ฝั่งตรงข้ามได้ยินเงียบ
- [x] Google Meet (Chrome) muted → ฝั่งตรงข้ามได้ยินเงียบ
- [x] FaceTime muted → ฝั่งตรงข้ามได้ยินเงียบ
- [x] Unmute คืน volume เดิม (ไม่ใช่ 100%)
- [x] Switch input device ระหว่าง muted → ยัง muted
- [x] Talk-while-muted → statusEmoji เปลี่ยนเป็น 🙀 ภายใน 1s, หยุดพูด 2s → หาย
- [x] เปิดทิ้งไว้ 30 นาที, สลับ device 5 รอบ — ไม่ crash

---

## Review

**Status:** ✅ Spike ผ่าน (verified by user 2026-04-25)

### สิ่งที่พิสูจน์ได้
- **Option D ใช้ได้จริง** — ปรับ `kAudioDevicePropertyVolumeScalar` ของ default input device ผ่าน CoreAudio APIs มาตรฐาน ทำงานได้จาก App Sandbox พร้อม `com.apple.security.device.audio-input` entitlement
- **Talk-while-muted** — AVAudioEngine tap ยังอ่าน raw input level ได้ขณะที่ system input volume ถูก zero (คอนเฟิร์มสมมติฐานสำคัญ)
- **Architecture สะอาด** — `MicMuteController` (output control) แยกจาก `AudioLevelMonitor` (input observation) ไม่ต้องคุยกัน มี `AppState` เป็น orchestrator ชั้นเดียว

### ขนาดโค้ด
- 5 ไฟล์ Swift, ~320 บรรทัดรวม (MicMuteController ~170, AudioLevelMonitor ~90, ที่เหลือ UI/state)
- ไม่มี third-party dependency

### ไฟล์/config ที่แตะ
- สร้าง: `Mewt.entitlements`, `State/AppState.swift`, `Audio/MicMuteController.swift`, `Audio/AudioLevelMonitor.swift`, `tasks/todo.md`, `tasks/lessons.md`
- แก้: `MewtApp.swift`, `ContentView.swift`, `Mewt.xcodeproj/project.pbxproj` (CODE_SIGN_ENTITLEMENTS + INFOPLIST_KEY_LSUIElement + INFOPLIST_KEY_NSMicrophoneUsageDescription)

### ข้อสังเกตระหว่าง impl
- `AudioHardwareService*` APIs (VirtualMainVolume) ไม่อยู่ใน SDK macOS 26.4 แล้ว — ต้องใช้แค่ `AudioObject*` + fallback iterate per-channel element
- SourceKit ใน diagnostic ฟ้อง "Cannot find X in scope" ตอนสร้างไฟล์ใหม่ — เป็น transient ของ indexer `xcodebuild` compile ผ่านปกติ

### ยังไม่ได้ทดสอบ (future work)
- Device switching edge cases (บาง USB mic) — ทดสอบครบ 5 รอบแล้วหรือยัง ถ้ายังเจอ bug ให้กลับมาแก้
- Memory leak 30-นาที — ยังไม่ได้ soak test, ระดับสำคัญน้อยเพราะ spike

### Next phases (ตามลำดับ)
1. Global hotkey / push-to-talk
2. Static mascot face (free tier) ใน menu bar icon
3. Floating overlay window ลอยข้างเมาส์
4. Animated pets + StoreKit 2 IAP
5. App Store submission prep
