# Phase 3 — Floating Overlay Window

> Plan สำหรับ session ใหม่หลัง `/clear` — self-contained ตาม pattern ของ `phase-1-global-hotkey.md`

---

## Context

**โปรเจ็ค:** Mewt — macOS menu bar app, mute system-wide + talk-while-muted detection + cat mascot

**สถานะก่อนเริ่ม Phase 3:**
- ✅ Phase 0 — core mute engine + talk-while-muted (`82dd084`)
- ✅ Phase 1 — global hotkey + PTT + Settings (`253622d`)
- ✅ Pre-Phase 2 — `MicStatus` + `MuteStateMachine` + DI refactor + 43 tests (`c670b91`)
- ✅ Phase 2 — static mascot face + right-click tray quick toggle + 60 tests (`c925135`)
- Branch: `main` clean

**สถาปัตยกรรมตอนนี้:**
```
Mewt/
├── MewtApp.swift                  — @main + AppDelegate (NSStatusItem owner)
├── ContentView.swift              — popover UI (mascot + level + buttons)
├── State/
│   ├── AppState.swift             — @Observable @MainActor orchestrator
│   ├── MicStatus.swift            — derived enum
│   └── MuteStateMachine.swift     — pure state machine
├── Audio/                         — MicMuteController + AudioLevelMonitor + TalkingDebouncer
├── Input/HotkeyController.swift   — KeyboardShortcuts wrapper
├── Mascot/                        — MascotPose (pure) + MascotFace (SwiftUI)
├── Tray/                          — TrayController (NSStatusItem) + TrayClickRouter (pure)
└── Settings/SettingsView.swift
```

**ปัญหาที่ Phase 3 แก้:** menu bar icon เห็นยากตอนประชุม (ตาอยู่ที่หน้าผู้พูดหรือ slides), `MARKETING.md` ระบุ free-tier ต้องมี **floating dot indicator** ที่ลอยข้างเมาส์ตลอดเวลา — ทั้งเป็น value prop เด่นและเป็น upsell hook ไป Phase 4 (Plus tier ปรับขนาด/opacity/animated pets)

**Outcome ที่ต้องการ:** หน้าต่างเล็ก ๆ ลอยอยู่ทุก Space ทุก fullscreen แสดง mascot — ผู้ใช้เห็น state ทันทีโดยไม่ต้องสลับสายตามาที่ menu bar; click ที่ overlay = toggle mute

---

## Goal

1. **Always-on-top floating window** ลอยทุก Space + ทับ fullscreen apps (Zoom, Meet, Keynote)
2. **แสดง mascot** ที่ render สถานะปัจจุบัน (reuse `MascotFace` จาก Phase 2)
3. **Drag-to-move** + persist position ระหว่าง relaunch
4. **Click on overlay = toggle mute** (เร็วกว่ากดที่ menu bar)
5. **Visibility toggle** ใน Settings (default: visible)

---

## Out of scope (เก็บไว้ Phase 4 paid tier)

ตาม `MARKETING.md` Free tier เน้น "ลอยข้างเมาส์ + dot indicator"; Plus tier เพิ่ม:
- ปรับขนาด overlay (Phase 3 hardcode 64pt)
- ปรับ opacity (Phase 3 = 1.0 เสมอ)
- Click-through mode (`ignoresMouseEvents`)
- Animated mascot motion + level-driven scaling
- Multiple pets / accessories

---

## Technical decisions

### Window class: `NSPanel` (ไม่ใช่ `NSWindow`)

| ตัวเลือก | ข้อดี | ข้อเสีย |
|---|---|---|
| `NSWindow` | flexibility สูง | ต้องจัดการ focus เอง — กลายเป็น key window ดึง app activation |
| **`NSPanel` w/ `.nonactivatingPanel`** | ออกแบบสำหรับ floating utility, ไม่ดึง app activation | style mask ผสมต้อง subclass override `canBecomeKey/Main` |
| SwiftUI `Window` scene | declarative | ไม่มี API สำหรับ `.statusBar` level / `.canJoinAllSpaces` ใน macOS 26.4 stable |

→ **NSPanel subclass** + override `canBecomeKey = false`, `canBecomeMain = false`

### Window level: `.statusBar`

- เหนือ window ปกติทุกแอพ
- ใต้ system menu bar / Spotlight / NotificationCenter
- ทดสอบกับ `.popUpMenu` (สูงกว่า) เผื่อบาง fullscreen app เลือกกินไปด้วย — fallback ถ้า `.statusBar` ไม่พอ

### Collection behavior (สำคัญมาก)

```swift
panel.collectionBehavior = [
    .canJoinAllSpaces,      // ทุก Space ของผู้ใช้
    .fullScreenAuxiliary,   // ทับ fullscreen apps (Zoom share screen ฯลฯ)
    .stationary,            // ไม่ swoop ตอน Mission Control
    .ignoresCycle,          // Cmd-` ไม่ cycle มาที่ panel
]
```

### Background transparency

```swift
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = false   // mascot เป็นวงกลม shadow รูปสี่เหลี่ยมจะดูแปลก
```

### Drag implementation

ใช้ `panel.isMovableByWindowBackground = true` + observe `NSWindow.didMoveNotification` → persist origin หลัง user ปล่อยเมาส์ (debounced 300ms)

**ระวัง:** drag conflict กับ click-to-toggle — ใช้ pattern:
- `MouseDown → record location`
- `MouseUp → ถ้า drag distance < 4pt = treat as click; else = drag`

แต่จริงๆ `isMovableByWindowBackground` consume mouse event ก่อนถึง SwiftUI → click ถูกกินเสมอ. ทางแก้: **ไม่ใช้ `isMovableByWindowBackground` เลย** — ทำ drag manual ผ่าน SwiftUI `DragGesture` บน mascot view, แล้วเรียก `panel.setFrameOrigin` ตามที่ drag ไป + threshold 4pt ก่อน fire drag

### Position persistence

`UserDefaults` keys:
- `overlay.frame.x: Double`
- `overlay.frame.y: Double`
- `overlay.frame.screenUUID: String?` — `NSScreen.localizedName` ใช้ไม่ได้ (เปลี่ยนภาษา); ใช้ `screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]` (CGDirectDisplayID)
- `overlay.visible: Bool` (default `true`)

**Restore logic:**
1. ถ้า saved displayID ตรงกับ screen ที่ connect อยู่ → restore origin ตามนั้น (clamp ใน visibleFrame)
2. ถ้าหลุด (monitor unplugged) → fallback `NSScreen.main.visibleFrame` มุมขวาล่าง offset 24pt จาก trailing edge

### State changes ใน AppState

เพิ่ม:
```swift
@ObservationIgnored
private let defaults = UserDefaults.standard

var overlayVisible: Bool {
    didSet { defaults.set(overlayVisible, forKey: "overlay.visible") }
}

func toggleOverlay() { overlayVisible.toggle() }
```

ใน `init`:
```swift
self.overlayVisible = defaults.object(forKey: "overlay.visible") as? Bool ?? true
```

### XCTest guard

`OverlayWindowController.install()` ต้องไม่ถูกเรียกใต้ XCTest (เหมือน `TrayController.install()`) — guard ใน `AppDelegate.applicationDidFinishLaunching` ที่มีอยู่แล้ว

---

## Architecture

### ไฟล์ใหม่

#### `Mewt/Overlay/OverlayPosition.swift` (pure, testable)
```swift
import CoreGraphics

struct OverlayPosition: Equatable {
    var origin: CGPoint
    var displayID: UInt32?

    /// Clamp origin into a screen's visibleFrame so the mascot is never
    /// off-screen after a monitor change. Returns the clamped origin.
    static func clamp(
        _ origin: CGPoint,
        size: CGSize,
        within visibleFrame: CGRect
    ) -> CGPoint { ... }

    /// Default position: bottom-right of main screen, 24pt inset.
    static func defaultOrigin(
        size: CGSize,
        within visibleFrame: CGRect
    ) -> CGPoint { ... }
}
```

#### `Mewt/Overlay/OverlayWindow.swift`
```swift
@MainActor
final class OverlayWindow: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovableByWindowBackground = false  // we drive drag from SwiftUI
        ignoresMouseEvents = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
```

#### `Mewt/Overlay/OverlayContentView.swift`
```swift
struct OverlayContentView: View {
    @Environment(AppState.self) private var appState
    let onDrag: (CGSize) -> Void
    let onClick: () -> Void

    @State private var dragStart: CGPoint?
    @State private var didDrag = false

    var body: some View {
        MascotFace(pose: .from(appState.status), size: 56)
            .padding(4)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if value.translation.width.magnitude > 4
                            || value.translation.height.magnitude > 4 {
                            didDrag = true
                        }
                        if didDrag { onDrag(value.translation) }
                    }
                    .onEnded { _ in
                        if !didDrag { onClick() }
                        didDrag = false
                    }
            )
    }
}
```

#### `Mewt/Overlay/OverlayWindowController.swift`
```swift
@MainActor
final class OverlayWindowController {
    private let appState: AppState
    private let panel: OverlayWindow
    private let defaults: UserDefaults

    init(appState: AppState, defaults: UserDefaults = .standard) {
        self.appState = appState
        self.defaults = defaults
        self.panel = OverlayWindow(contentRect: NSRect(x: 0, y: 0, width: 64, height: 64))
    }

    func install() {
        let host = NSHostingController(
            rootView: OverlayContentView(
                onDrag: { [weak self] tr in self?.applyDrag(tr) },
                onClick: { [weak self] in self?.appState.toggleMute() }
            )
            .environment(appState)
        )
        panel.contentViewController = host
        panel.setFrameOrigin(restoredOrigin())
        applyVisibility()
        observeVisibility()
    }

    private func observeVisibility() {
        withObservationTracking { [weak self] in
            _ = self?.appState.overlayVisible
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.applyVisibility()
                self.observeVisibility()
            }
        }
    }

    private func applyVisibility() {
        if appState.overlayVisible {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    private func applyDrag(_ translation: CGSize) { ... }
    private func restoredOrigin() -> CGPoint { ... }
    private func persistOrigin() { ... }   // debounced
}
```

### แก้ไฟล์เดิม

- **`Mewt/State/AppState.swift`** — เพิ่ม `overlayVisible` + `toggleOverlay()` + persistence ผ่าน UserDefaults (init reads, didSet writes). **ระวัง:** UserDefaults read ใน init ต้องไม่ side-effect ใต้ test → safe (defaults read = stateless)
- **`Mewt/MewtApp.swift`** `AppDelegate.applicationDidFinishLaunching`:
  ```swift
  state.start()
  let tray = TrayController(appState: state); tray.install(); self.tray = tray
  let overlay = OverlayWindowController(appState: state); overlay.install(); self.overlay = overlay
  ```
- **`Mewt/Settings/SettingsView.swift`** — เพิ่ม section "Overlay":
  ```swift
  Section("Overlay") {
      Toggle("Show floating mascot", isOn: $appState.overlayVisible)
      Text("Click the mascot to toggle mute. Drag to reposition.")
          .font(.caption).foregroundStyle(.secondary)
  }
  ```
  ต้อง `@Bindable var appState: AppState` (Observation pattern)
- **`Mewt.xcodeproj/project.pbxproj`** — auto-include ผ่าน `PBXFileSystemSynchronizedRootGroup` ของ Mewt target (ตามที่ `lessons.md` บันทึก: ไฟล์ใหม่ใน folder ที่ track ด้วย sync group ไม่ต้อง hand-edit pbxproj)
- **`MewtTests/`** — เพิ่ม `OverlayPositionTests.swift` (pure logic เท่านั้น)

---

## Implementation steps (ลำดับ)

1. **`OverlayPosition.swift`** + tests (30 นาที)
   - Pure type, clamp, defaultOrigin
   - 4-6 unit tests (clamp inside, clamp out-of-bounds top/bottom/left/right, default position)

2. **`AppState` extension** — `overlayVisible` + persistence (15 นาที)
   - 1-2 tests: defaults round-trip, didSet writes

3. **`OverlayWindow.swift`** + `OverlayContentView.swift` (45 นาที)
   - NSPanel subclass — แค่ instantiate
   - SwiftUI content view ใช้ MascotFace
   - **ห้ามทดสอบ NSPanel โดยตรง** ตาม pattern เดียวกับ TrayController

4. **`OverlayWindowController.swift`** (60 นาที)
   - install + observe visibility + drag handling + position persistence
   - debounce save ที่ Timer 300ms

5. **wire ใน AppDelegate** (10 นาที)

6. **Settings UI** — เพิ่ม Overlay section + bindable AppState (15 นาที)

7. **xcodebuild + xcodebuild test** (15 นาที)

8. **Manual verification** (30-45 นาที — ดู checklist ด้านล่าง)

**เวลารวมคาด:** ~3.5 ชั่วโมง

---

## Verification (Definition of Done)

### Visibility & always-on-top
- [ ] App launch → mascot ลอยมุมขวาล่าง (default) ของจอ main
- [ ] เปิด Chrome เต็มจอ → mascot ยังเห็น
- [ ] เปิด Zoom fullscreen → mascot ยังเห็น (test ด้วย Zoom test call)
- [ ] Switch Space (`Ctrl+→`) → mascot ตามไปด้วย
- [ ] Mission Control → mascot ไม่ swoop (stationary)

### Drag
- [ ] Drag mascot ไปมุมซ้ายบน → ตามไป
- [ ] ปล่อย → ตำแหน่งบันทึกใน `defaults read NSGlobalDomain | grep overlay` (หรือ `defaults read <bundle-id>`)
- [ ] Quit + relaunch → mascot อยู่ตรงที่บันทึกไว้
- [ ] Plug 2nd monitor + drag mascot ไปจอ 2 → relaunch → restore ที่จอ 2 (ถ้าจอยังต่อ)
- [ ] Unplug 2nd monitor (เคยอยู่จอ 2) → relaunch → fallback มุมขวาล่าง main screen

### Click → toggle mute
- [ ] Click mascot ขณะ unmuted → mute (mascot เปลี่ยนเป็น 😴)
- [ ] Click อีกที → unmute (😺)
- [ ] Click หลัง drag เสร็จ → ห้าม fire toggle (drag-vs-click discrimination)
- [ ] Click ขณะ Chrome focused → Chrome ยัง focused (nonactivatingPanel)

### Mascot reactivity (ใช้ของ Phase 2)
- [ ] Mute → mascot 😴 ใน overlay (sync กับ menu bar)
- [ ] Mute + พูด → mascot 🙀 alarm + accent ใน overlay
- [ ] PTT (⌥Space ค้าง) → mascot 🗣️ ใน overlay

### Settings
- [ ] เปิด Settings → toggle "Show floating mascot" off → mascot หาย
- [ ] toggle on → mascot กลับมาที่ตำแหน่งเดิม (ไม่ reset)
- [ ] Quit + relaunch หลังจาก toggle off → mascot ยัง hidden (persisted)

### Build & tests
- [ ] `xcodebuild build` — no warnings
- [ ] `xcodebuild test -scheme Mewt` — เดิม 60 + ใหม่ 6-8 tests = 66-68 ผ่านหมด
- [ ] `codesign -d --entitlements -` — ไม่มี entitlement เพิ่ม (overlay ไม่ต้อง permission พิเศษ)

### Doesn't regress Phase 0/1/2
- [ ] Hotkey (⌥M, ⌥Space) ยังทำงาน
- [ ] Right-click menu bar = quick toggle ยังทำงาน
- [ ] Left-click menu bar = popover ยังเปิด
- [ ] Talk-while-muted alert ใน menu bar ยังทำงาน

---

## Known limits & risks

### High risk — ต้อง verify ตอน manual test
1. **`.fullScreenAuxiliary` ใน macOS Tahoe (26.4)** — Apple เปลี่ยน behavior ของ fullscreen overlay บางครั้งระหว่าง major versions; ถ้า Zoom/Meet fullscreen แล้ว overlay หายไป → ลอง `.popUpMenu` level + เพิ่ม `.transient` collection
2. **Click กลายเป็น drag micro-jitter** — trackpad บางตัว generate translation 1-2pt แม้ผู้ใช้ตั้งใจ tap → threshold 4pt อาจน้อยไป; ถ้า fail ลองยก threshold เป็น 6pt
3. **`isMovableByWindowBackground = false` + SwiftUI drag** — บางเวอร์ชัน SwiftUI ไม่ส่ง drag event ผ่าน `nonactivatingPanel`; fallback คือ override `mouseDragged` ที่ NSPanel level

### Medium risk
4. **Multi-monitor restore** — `CGDirectDisplayID` เปลี่ยนหลัง sleep/wake บางครั้ง → ใช้ `CGDisplayIDToOpenGLDisplayMask` เป็น fallback หรือยอมรับว่า "อาจ reset เป็น default หลัง mac sleep ลึก"
5. **Settings binding** — `@Bindable` กับ `@Observable` class ใน macOS Tahoe → ตรวจ syntax (`@Bindable var appState` ไม่ใช่ `@Binding`)

### Low risk
6. **Quit ไม่ dismiss panel** — `NSApplication.shared.terminate(nil)` ปิด window อัตโนมัติ — ไม่ต้องจัดการ
7. **Window restoration หลัง `defaults delete`** — fallback ที่ defaultOrigin ทำงาน

---

## Lessons ที่ต้อง check ก่อนเริ่ม

จาก `tasks/lessons.md`:

- ✅ **`@MainActor` static + nonisolated** — `OverlayWindow` อาจมี static address const → mark `nonisolated` ถ้า compiler บ่น
- ✅ **`withObservationTracking` re-subscribe** — ใช้ pattern เดียวกับ TrayController.observeStatus()
- ✅ **MainActor default-init ใช้ใน default param ไม่ได้** — ใช้ convenience init pattern
- ✅ **XCTest guard** — Mirror AppDelegate guard ที่มีอยู่ — overlay ติดตามเข้าไปใน guarded path เดียวกัน
- ✅ **MenuBarExtra → NSStatusItem migration** — ไม่กระทบ Phase 3 (TrayController แยกอยู่แล้ว)
- ✅ **PBXFileSystemSynchronizedRootGroup** — auto-include ไฟล์ใหม่ ไม่ต้องแก้ pbxproj สำหรับ source files ของ app target

ต้องระวังเพิ่ม:
- **NSPanel + nonactivatingPanel + DragGesture** — ยังไม่เคยใน lessons; ถ้าเจอ behavior แปลก → log lesson หลังแก้

---

## ไฟล์ที่จะแก้ / สร้าง

**สร้างใหม่:**
- `Mewt/Overlay/OverlayPosition.swift`
- `Mewt/Overlay/OverlayWindow.swift`
- `Mewt/Overlay/OverlayContentView.swift`
- `Mewt/Overlay/OverlayWindowController.swift`
- `MewtTests/OverlayPositionTests.swift`

**แก้:**
- `Mewt/State/AppState.swift` (overlayVisible + persistence)
- `Mewt/MewtApp.swift` (AppDelegate install overlay)
- `Mewt/Settings/SettingsView.swift` (Overlay section)
- `MewtTests/AppStateTests.swift` (overlayVisible defaults round-trip — 1-2 tests)

**ไม่แตะ:**
- `Mewt/Audio/*` — core stable
- `Mewt/Tray/*` — Phase 2 separate
- `Mewt/Mascot/*` — reuse 100%
- `Mewt/Input/*` — hotkey unchanged
- `Mewt.entitlements` — ไม่ต้องเพิ่ม (NSPanel ไม่ต้อง permission)

---

## หลัง Phase 3 เสร็จ

1. Phase 4 — Animated pets + StoreKit 2 IAP (Plus tier — ปรับขนาด/opacity, click-through, animations, multiple pets)
2. Pre-Phase 4 — Layer animation system + level-driven motion จาก AudioLevelMonitor.inputLevel
3. (อาจแทรก) — Launch on login toggle, Notification Center widget, custom keyboard shortcut for overlay visibility
