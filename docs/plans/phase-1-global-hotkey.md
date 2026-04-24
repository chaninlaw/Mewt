# Phase 1 — Global Hotkey

> Plan สำหรับ session ใหม่หลัง `/clear` — ไฟล์นี้เขียนให้ self-contained

---

## Context

**โปรเจ็ค:** Mewt — macOS menu bar app สำหรับ mute microphone system-wide + detect talk-while-muted (mascot แมว)

**สถานะก่อนเริ่ม Phase 1:**
- Phase 0 (core mute engine + talk-while-muted) ผ่านและ commit แล้วที่ `82567fa` — "Bootstrap Mewt..."
- Verified: mute ได้จริงทุกแอป (QuickTime test แล้ว), talk-while-muted trigger ได้ภายใน ~1s
- โครงสร้างโค้ด:
  ```
  Mewt/
  ├── MewtApp.swift              — MenuBarExtra entry, ใช้ @State AppState
  ├── ContentView.swift          — menu UI (status + toggle button + level bar)
  ├── Mewt.entitlements          — sandbox + device.audio-input
  ├── State/AppState.swift       — @Observable @MainActor orchestrator
  └── Audio/
      ├── MicMuteController.swift    — CoreAudio volume control + device listener
      └── AudioLevelMonitor.swift    — AVAudioEngine RMS + talking debounce
  ```
- Build config: macOS 26.4 target, App Sandbox + Hardened Runtime เปิด, Swift 5 + MainActor default isolation
- Plan Phase 0 อ้างอิง: `/Users/ninja/.claude2/plans/kind-wiggling-candle.md`
- Workflow docs: `CLAUDE.md` (repo root), checklist `tasks/todo.md`, lessons `tasks/lessons.md`

**ปัญหาที่ Phase 1 แก้:** ตอนนี้ต้องคลิก menu bar ทุกครั้งเพื่อ mute — ใน Zoom/Meet meeting จริง เสียเวลาและเสียโฟกัส ทำให้แอป "ใช้จริงไม่ได้"

**Outcome ที่ต้องการ:** ผู้ใช้กด shortcut ได้ขณะ meeting app ใดๆ focused โดยไม่ต้องสลับออก — unlock actual usability

---

## Goal

1. **Toggle mute hotkey** — กด 1 ครั้ง สลับ mute/unmute
2. **Push-to-talk (PTT) hotkey** — กดค้าง = unmute, ปล่อย = กลับสภาพเดิม
3. **Menu UI** แสดง hotkey ที่ set อยู่ให้เห็น
4. **Settings scene** ให้ user เปลี่ยน shortcut เองได้ (ยิงสั้นๆ ได้เกือบฟรีจาก library ที่เลือก)

---

## Technical decision: ใช้ `KeyboardShortcuts` SPM package

**เปรียบเทียบทางเลือก:**
| Approach | Sandbox? | PTT key-up? | User config UI? | LOC ประมาณ |
|---|---|---|---|---|
| `NSEvent.addGlobalMonitorForEvents` | ต้องขอ Input Monitoring permission | ใช้ได้ | ต้องเขียนเอง | ~200 |
| Carbon `RegisterEventHotKey` | ✅ ใช้ได้ | ต้อง `InstallEventHandler` + `kEventHotKeyReleased` manual | ต้องเขียนเอง | ~250 (verbose) |
| **`KeyboardShortcuts` (Sindre Sorhus)** | ✅ ใช้ได้ (ใช้ Carbon ใต้ฮูด) | ✅ มี `.onKeyUp` | ✅ มี `Recorder` SwiftUI view สำเร็จ | ~50 |

**เลือก KeyboardShortcuts package** — battle-tested ใน App Store apps จำนวนมาก (Dato, Shareful, ฯลฯ), maintain โดย Sindre Sorhus, API สะอาด, ได้ settings UI มาด้วย

**Repository:** `https://github.com/sindresorhus/KeyboardShortcuts` — ใช้ version ล่าสุด (2.x)

**แลกกับ:** third-party dependency ตัวแรก — ยอมรับได้เพราะ alternative คือ reimplement ส่วนที่คนทำเก่งกว่าทำอยู่แล้ว (CLAUDE.md "No Laziness" = ไม่ทำทางลัดที่ sloppy, ไม่ใช่ = reimplement ทุกอย่าง)

---

## Hotkey defaults

| Action | Default shortcut | เหตุผล |
|---|---|---|
| Toggle mute | `⌥M` (Option+M) | เบา, จำง่าย, **ไม่ชน Zoom** (`⌘⇧A`) และ Meet (`⌘D` / browser) |
| Push-to-talk | `⌥Space` (Option+Space ค้าง) | ไม่ชน Spotlight (`⌘Space`), ถือค้างได้สบาย |

**หลีกเลี่ยงการใช้ `fn` key** เพราะ:
1. `KeyboardShortcuts` package ไม่รองรับ fn เป็น modifier อย่างเดียว
2. macOS ใหม่ใช้ fn เปิด emoji picker / Dictation → conflict แน่นอน
3. Touch Bar Mac มี fn behavior แปลกๆ

User เปลี่ยน shortcut ได้ผ่าน Settings scene → default เป็นแค่ starting point

---

## Architecture

### PTT state machine (สำคัญ — อย่าทำพลาด)

```
state: { muted, unmuted }
pttHeld: Bool

events:
  toggle hotkey → flip state (ignore pttHeld)
  PTT down → save previous state; force unmuted
  PTT up → restore saved state
```

**Invariant:** ถ้า user ตอนเริ่มเป็น `unmuted` แล้วกด PTT ค้าง → ปล่อย → ต้องกลับเป็น `unmuted` เหมือนเดิม (PTT ไม่ควรเปลี่ยนจุดปกติของระบบ)

### ไฟล์ใหม่

`Mewt/Input/HotkeyController.swift`:
```swift
import KeyboardShortcuts

@MainActor
final class HotkeyController {
    var onToggle: (() -> Void)?
    var onPTTDown: (() -> Void)?
    var onPTTUp: (() -> Void)?

    func start() {
        KeyboardShortcuts.onKeyDown(for: .toggleMute) { [weak self] in
            self?.onToggle?()
        }
        KeyboardShortcuts.onKeyDown(for: .pushToTalk) { [weak self] in
            self?.onPTTDown?()
        }
        KeyboardShortcuts.onKeyUp(for: .pushToTalk) { [weak self] in
            self?.onPTTUp?()
        }
    }
}

extension KeyboardShortcuts.Name {
    static let toggleMute  = Self("toggleMute",  default: .init(.m, modifiers: [.option]))
    static let pushToTalk  = Self("pushToTalk",  default: .init(.space, modifiers: [.option]))
}
```

### แก้ `AppState.swift`

เพิ่ม:
```swift
var pttActive: Bool = false
private var preTTState: Bool? = nil    // บันทึก isMuted ก่อนกด PTT
private let hotkeys = HotkeyController()

// ใน init() หลัง levelMonitor setup
hotkeys.onToggle = { [weak self] in self?.toggleMute() }
hotkeys.onPTTDown = { [weak self] in self?.pttDown() }
hotkeys.onPTTUp   = { [weak self] in self?.pttUp() }
hotkeys.start()

func pttDown() {
    guard preTTState == nil else { return }  // ignore re-entrance
    preTTState = isMuted
    pttActive = true
    if isMuted {
        muteController.unmute()
        isMuted = false
        isTalkingWhileMuted = false
    }
    statusMessage = "Push-to-talk"
}

func pttUp() {
    guard let prev = preTTState else { return }
    pttActive = false
    if prev && !isMuted {
        muteController.mute()
        isMuted = true
    }
    preTTState = nil
    statusMessage = prev ? "Muted" : "Unmuted"
}
```

### แก้ `ContentView.swift`

- เพิ่มแถวเล็กใต้ปุ่ม Mute แสดง "⌥M to toggle · ⌥Space to talk"
- เปลี่ยน emoji เมื่อ `pttActive` → 🗣️ (optional, Phase 2 พอได้)
- เพิ่มปุ่ม "Settings…" เปิด Settings scene

### สร้าง Settings scene

`Mewt/Settings/SettingsView.swift`:
```swift
import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Toggle mute:",   name: .toggleMute)
            KeyboardShortcuts.Recorder("Push-to-talk:",  name: .pushToTalk)
        }
        .padding(20)
        .frame(width: 360)
    }
}
```

แก้ `MewtApp.swift` เพิ่ม `Settings { SettingsView() }` scene

---

## Implementation steps (ลำดับ)

1. **เพิ่ม Swift Package dependency** (15 นาที)
   - เพิ่มผ่าน `.xcodeproj` package resolution — `https://github.com/sindresorhus/KeyboardShortcuts`, rule: Up to Next Major 2.0.0
   - Alternative: เพิ่ม `packageReferences` + `XCRemoteSwiftPackageReference` ใน `project.pbxproj` ตรงๆ (ถ้าไม่ใช้ Xcode GUI)

2. **สร้าง `Mewt/Input/HotkeyController.swift`** (20 นาที)
   - เอาตาม snippet ข้างบน + add log.info ตอนแต่ละ callback ยิง

3. **แก้ `AppState.swift`** (30 นาที)
   - เพิ่ม property, init setup, `pttDown()`, `pttUp()`
   - ระวัง: ต้อง test กรณี PTT ค้างแล้ว user กด toggle ระหว่างนั้น → ต้อง early-return ใน pttUp ถ้า state ผิด

4. **แก้ `ContentView.swift`** (15 นาที)
   - แสดง hotkey strings (ใช้ `KeyboardShortcuts.getShortcut(for: .toggleMute)?.description` หรือ hardcode ชั่วคราว)
   - เพิ่มปุ่ม Settings

5. **สร้าง `Mewt/Settings/SettingsView.swift` + เชื่อมเข้า MewtApp** (20 นาที)

6. **Build + manual verify** (30 นาที)

**เวลารวมคาด:** ~2 ชั่วโมง

---

## Verification (Definition of Done)

1. **Toggle hotkey ทำงานขณะแอปอื่น focused**
   - เปิด Chrome → กด `⌥M` → state ใน Mewt menu bar เปลี่ยน ✅
   - เปิด Zoom test call → กด `⌥M` → ฝั่งตรงข้ามได้ยินเงียบ ✅

2. **Push-to-talk ทำงาน**
   - เริ่มที่ muted → กด `⌥Space` ค้าง → ฝั่งตรงข้ามได้ยิน ✅
   - ปล่อย → กลับเงียบ ✅
   - เริ่มที่ unmuted → กด ⌥Space ค้าง → ไม่เปลี่ยน ✅
   - ปล่อย → ยัง unmuted อยู่ ✅ (invariant รักษาไว้)

3. **Race condition edge case**
   - กด toggle ขณะที่ PTT ค้างอยู่ → ไม่ crash, state consistent
   - กด PTT สลับ device → state consistent

4. **Settings UI**
   - เปลี่ยน toggle shortcut เป็น `⌃⌥M` แล้วกด → ทำงานตาม shortcut ใหม่
   - restart app → shortcut ที่เปลี่ยนยังอยู่ (persist)

5. **Sandbox check**
   - `codesign -d --entitlements - --xml Mewt.app | plutil -p -` — ไม่มี entitlement พิเศษเพิ่มจาก Phase 0

6. **Build + no warnings จาก swift compiler**

---

## ไฟล์ที่จะแก้ / สร้าง

**สร้างใหม่:**
- `Mewt/Input/HotkeyController.swift`
- `Mewt/Settings/SettingsView.swift`

**แก้:**
- `Mewt/State/AppState.swift` (add PTT state + hotkey wiring)
- `Mewt/ContentView.swift` (hotkey hints + Settings button)
- `Mewt/MewtApp.swift` (add Settings scene)
- `Mewt.xcodeproj/project.pbxproj` (SPM package reference)

**ไม่แตะ:**
- `Mewt/Audio/*` — core ทำงานดีอยู่
- `Mewt.entitlements` — ไม่ต้องเพิ่ม entitlement ใหม่ (KeyboardShortcuts ใช้ Carbon ซึ่งทำงานใน sandbox ได้)

---

## Out of scope (เก็บไว้ phase ต่อๆ ไป)

- CGEventTap เพื่อ consume event (ป้องกัน ⌥Space leak ไปถึง focused app) — ต้อง Accessibility permission, ซับซ้อน
- Launch on login toggle
- Mascot face เปลี่ยนตาม state (Phase 2)
- Animated pet (Phase 4 — paid tier)

---

## Known limits ที่ต้องบอก user หลังเสร็จ

- `⌥Space` จะยังถูกส่งต่อไปให้แอปที่ focused อยู่ด้วย → ถ้า user เจอปัญหา (เช่นช่องว่างเกิดใน text field) ให้เปลี่ยน shortcut ใน Settings
- Settings scene ใช้ native `Settings { }` SwiftUI scene — เปิดด้วย `⌘,` หรือจากเมนู

---

## หลัง Phase 1 เสร็จ

เลือกต่อ:
- **Phase 2: Mascot** — เปลี่ยน menu bar icon เป็น cat emoji, status ต่างๆ
- **Phase 3: Floating overlay window** ลอยข้างเมาส์ (ยากสุด — window management)
- **Phase 4: Animated pets + StoreKit 2 IAP**
