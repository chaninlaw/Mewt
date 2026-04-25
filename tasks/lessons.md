# Lessons Learned — Mewt

บทเรียนที่สะสมจากการทำงานกับ user บน Mewt
ใช้ file นี้ป้องกันการทำผิดแบบเดิมซ้ำ

---

## Pattern

ทุก entry ใช้รูปแบบนี้:

```
### <รูปแบบ/กฎ>
- **Trigger:** เมื่อไหร่จะเจอ
- **Rule:** ต้องทำอะไร / ห้ามทำอะไร
- **Why:** เหตุผล (มักอ้างอิง incident จริง)
```

---

### macOS mic mute: belt-and-suspenders — ต้องใช้ **ทั้ง** `kAudioDevicePropertyMute` **และ** `kAudioDevicePropertyVolumeScalar=0`

- **Trigger:** ต้อง mute microphone system-wide จาก macOS app ให้ทุก client ได้ buffer เงียบจริง
- **Rule:** บน **ทุก connected input device** (ไม่ใช่แค่ default — ดู iteration 3→4 ด้านล่าง) apply **ทั้งสอง** mechanism พร้อมกันและ **ทุก element** (Main + per-channel):
  1. Enumerate `kAudioHardwarePropertyDevices` → filter ที่มี input channels
  2. สำหรับแต่ละ device: `kAudioDevicePropertyMute = 1` on Main element + ทุก input channel (ไม่ใช่ fallback — ทำทั้งหมด)
  3. บันทึก `kAudioDevicePropertyVolumeScalar` ปัจจุบันก่อน แล้วตั้งเป็น 0 บน Main + ทุก channel
  4. บน unmute ทำ inverse: mute=0 ทุก element ทุก device + restore saved volume per-device
  5. Listen `kAudioHardwarePropertyDevices` (hot-plug) เพื่อ re-apply เมื่อ device ใหม่เข้ามาขณะอยู่ใน muted state
- **เก็บ saved volume per-device** ใน `[AudioDeviceID: Float]` — ไม่ใช้ single field เพราะสลับ device แล้วจะข้าม
- **Why (incident 2026-04-25):** วิวัฒนาการของ lesson นี้ผ่าน 3 iteration:
  1. Phase 0 ใช้ `setInputVolume(0)` อย่างเดียว → work กับ built-in, **ล้มเหลวบน AirPods** (HFP driver ไม่ apply volume scalar ก่อน broadcast; Chrome/WebRTC tap ดิบจาก AUHAL)
  2. Phase 1 "Option A" สลับมาใช้ `kAudioDevicePropertyMute` อย่างเดียว → fix AirPods แต่ **ล้มเหลวบน External USB mic** (asymmetry: `AirPods→External` ขณะ PTT = bug, `External→AirPods` = OK → final device = ตัวที่ respect mute property ได้เงียบ; ตัวที่ไม่ respect = เสียงเล็ด)
  3. Phase 1 iteration 3: belt-and-suspenders บน default device เท่านั้น — **ยังล้ม** เมื่อ PTT ค้าง + สลับ device (AirPods→External): scenario asymmetric (External→AirPods work). สาเหตุ: **Chrome/WebRTC pin ที่ device ตอน getUserMedia** ไม่ hot-migrate ตาม default-device-change — เรา mute device ปัจจุบัน แต่ Chrome ยังอ่าน AirPods (ที่ถูก unmute จาก PTT) อยู่
  4. Phase 1 final: **mute ทุก input device พร้อมกัน** (enumerate `kAudioHardwarePropertyDevices`) + listener บน devices-list change → ไม่สน Chrome pin device ไหน ทุกตัวเงียบหมด
- **How to apply:** ห้าม assume "แค่ mute property พอ" หรือ "แค่ volume=0 พอ" ต่อไป — ต่อให้เห็นตัว open-source apps เขียนแบบเดียว ก็ให้สงสัยว่า test coverage ครอบคลุม device ทุกประเภทไหม
- **Cost ยอมรับ:** state เพิ่ม `savedVolumes: [AudioDeviceID: Float]` — trade สำหรับ correctness ที่ไม่สามารถ achieve ด้วย single mechanism

---

### SourceKit "No such module 'X'" / "Cannot find X in scope" มัก transient

- **Trigger:** หลังสร้าง Swift file ใหม่, เพิ่ม SPM package, หรือ refactor ตัว type หลัก ในโปรเจ็คที่ใช้ `PBXFileSystemSynchronizedRootGroup` (objectVersion 77+)
- **Rule:** อย่ารีบ "แก้" diagnostic พวกนี้ — run `xcodebuild build` ก่อนเสมอ; ถ้า build ผ่าน = indexer lag เฉยๆ ไม่ใช่ bug ในโค้ด
- **Why:** Phase 0 และ Phase 1 เจอบ่อยมาก (HotkeyController, AppState references, KeyboardShortcuts import) ทุกครั้ง `xcodebuild` compile ผ่าน ตัว error ของ compiler จริงๆ จะโผล่เป็น full absolute path + line/col ใน build output, SourceKit-only diagnostic จะหายเองหลัง indexer ตามทัน

---

### Orthogonal state สำหรับ transient override (เช่น PTT)

- **Trigger:** ออกแบบ state ที่มี "ค่าหลัก" และ "การ override ชั่วคราว" (push-to-talk, temporary bypass, emergency override, hover preview ฯลฯ)
- **Rule:** แยก 2 axis เป็น 2 field อิสระ เช่น `target: T` (ผู้ใช้ตั้งไว้) + `overrideActive: Bool` ให้ "physical/effective state" เป็น **derived** จากทั้งคู่ แล้ว sync ที่จุดเดียว (`applyState()`) ซึ่งเรียกจากทุก transition รวมถึง external event (device change, reconnect ฯลฯ)
- **ห้าม:** ใช้ field เดียวแบบเก็บ `isCurrent` แล้ว override ทับชั่วคราว พร้อมมี `savedPrev` อีก field เพื่อ restore — pattern นี้ desync ง่ายเวลา external event (เช่น device switch) มาขัดจังหวะ
- **Why (incident 2026-04-25):** Phase 1 ตอนแรกใช้ `isMuted: Bool` + `preTTState: Bool?` — PTT down ตั้ง `isMuted = false` ชั่วคราว device-change handler มี logic `if isMuted { applyMute() }` → เจอ `isMuted=false` ก็ข้าม → device ใหม่ไม่ถูก mute → pttUp กด mute แต่ physical ไม่ settle ทัน → UI โกหกว่า muted ผู้ใช้ต้อง toggle รอบนึงให้ re-sync. แก้โดยแยก `targetMuted` กับ `pttActive` ให้ orthogonal, single `applyMuteState()` คำนวณ `targetMuted && !pttActive` เรียกจาก 4 จุด (toggle, pttDown, pttUp, deviceChanged) → desync เป็นไปไม่ได้
- **How to apply:** เจอ code ที่ `if someCondition { saveOldState(); override() }` + ต้อง restore ใน callback คนละตัว → สัญญาณว่าควรแยก axis ออก

---

### `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES` บังคับ explicit import

- **Trigger:** เพิ่มโค้ดที่ใช้ extension members จากโมดูลที่ไม่ได้ `import` ตรงๆ (เช่น `.option` modifier บน `NSEvent.ModifierFlags` ที่ SPM package re-exports)
- **Rule:** ต้อง `import AppKit` (หรือโมดูลที่ define member จริง) ใน file ที่ใช้ — แม้ library ที่ `import` จะ re-export ก็ไม่พอ
- **Why:** Phase 1 ครั้งแรก compile fail "`.option` is not available due to missing import of defining module 'AppKit'" แม้ `import KeyboardShortcuts` แล้ว Swift upcoming feature นี้ปิด transitive member visibility เพื่อให้ dependency ชัดเจน
- **How to apply:** เมื่อเจอ "X is not available due to missing import of defining module Y" → เพิ่ม `import Y` ใน file นั้น (ไม่ใช่ใน library)

---

### Hand-edit `project.pbxproj` เพิ่ม test target — feasible ถ้าใช้ objectVersion 77+

- **Trigger:** ต้องการเพิ่ม unit test target แต่ไม่สะดวก / ไม่ต้องการให้ user เปิด Xcode GUI (เช่น Claude Code automation)
- **Rule:** ถ้า project ใช้ `PBXFileSystemSynchronizedRootGroup` (objectVersion 77+, Xcode 16+) → hand-edit ได้ไม่เจ็บ เพราะไฟล์ใหม่ auto-include ผ่าน group, ไม่ต้องเพิ่ม `PBXBuildFile` ทีละไฟล์
- **Sections ที่ต้องเพิ่มครบ (9 sections):** `PBXContainerItemProxy`, `PBXFileReference` (xctest product), `PBXFileSystemSynchronizedRootGroup` (tests folder), `PBXFrameworksBuildPhase`, `PBXGroup` (update mainGroup + Products), `PBXNativeTarget` (productType `com.apple.product-type.bundle.unit-test`), `PBXProject.targets`, `PBXResourcesBuildPhase`, `PBXSourcesBuildPhase`, `PBXTargetDependency`, `XCBuildConfiguration` × 2, `XCConfigurationList`
- **Build settings สำคัญสำหรับ hosted test bundle:** `TEST_HOST = $(BUILT_PRODUCTS_DIR)/<App>.app/Contents/MacOS/<App>`, `BUNDLE_LOADER = $(TEST_HOST)`, `PRODUCT_BUNDLE_IDENTIFIER = <app-id>.Tests`, `GENERATE_INFOPLIST_FILE = YES`
- **UUID naming:** ใช้ prefix ที่ไม่ชนของเดิม (เช่น Mewt ใช้ `BCB6C34x/BCB6C3xx` → test ใช้ `BCB6C501...`) 24 hex chars
- **ไม่ต้องสร้าง `.xcscheme` file** ถ้า scheme หลักมีอยู่แล้ว — `xcodebuild test -scheme <AppScheme>` auto-discover test target ที่ลิงก์ด้วย `PBXTargetDependency`
- **Why (incident 2026-04-25):** เพิ่ม test target สำหรับ Mewt จาก scratch โดย hand-edit pbxproj — สำเร็จครั้งแรก, 15 tests run passed ภายใน 0.003s. โจทย์: `PBXFileSystemSynchronizedRootGroup` ตัด step ที่เจ็บที่สุด (file-reference churn) ออก — ก่อน Xcode 16 ต้องเพิ่ม PBXBuildFile + PBXFileReference ทุก test file ซึ่ง error-prone
- **How to apply:** ก่อน edit commit pbxproj ไว้ก่อน — ถ้าพลาด `git checkout HEAD -- project.pbxproj` revert ทันทีโดยไม่กระทบไฟล์ Swift ที่แก้คู่กัน

---

### `XCTestConfigurationFilePath` env guard สำหรับ app target ที่ host test

- **Trigger:** macOS/iOS app target ที่ eagerly init hardware (mic, camera, network) ใน `@main` → hosted unit test bundle run จะไป launch app ซึ่ง fire side effects (permission prompt, mute เสียงจริง)
- **Rule:** ใน init ของ root state object (เช่น `AppState`) guard:
  ```swift
  guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
  start()
  ```
- **Why:** Mewt มี `AppState.init() → start()` ที่เปิด `AVAudioEngine` + register CoreAudio listener + mute/unmute HAL. Hosted test bundle (TEST_HOST=Mewt.app) launch app เข้า test process → ถ้าไม่ guard ทุก `xcodebuild test` จะ prompt mic permission และเล่นกับ physical mic ของ dev จริง
- **How to apply:** เฉพาะ app ที่ hardware-heavy หรือ network-heavy — app ธรรมดา init ปลอดภัยไม่ต้อง guard. Pair กับ "wire callbacks (safe) แยกจาก start hardware (env-guarded)" pattern เพื่อให้ test ใช้ mocks + wired callbacks ได้โดยไม่ผ่าน guard

---

### Adding `@MainActor` protocol conformance ทำให้ Swift strict-check static property isolation

- **Trigger:** มี class implicitly `@MainActor` (เช่น project ตั้ง `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`) ที่มี static property + deinit/C-callback อ่าน static นั้น → เพิ่ม `: SomeMainActorProtocol` conformance → compile error "Main actor-isolated static property X can not be referenced from a nonisolated context"
- **Rule:** สำหรับ static ที่เป็น POD CoreAudio struct, AudioObjectPropertyAddress, หรือ value pure: ใช้ `nonisolated private static let X = ...`. สำหรับ `@convention(c)` closure / function pointer ที่ Swift ไม่ infer ว่า Sendable: ใช้ `nonisolated(unsafe) private static let X: ... = { ... }`
- **Why (incident 2026-04-25):** เพิ่ม `MicMuteControlling: AnyObject` (`@MainActor`) ให้ `MicMuteController` → static `defaultInputDeviceAddress`, `devicesAddress`, `topologyListener` ถูก strictly check → `deinit` (nonisolated by default) เข้าถึงไม่ได้. เคย compile ผ่านก่อน conform เพราะ Swift implicit-isolation tolerant กว่า explicit. Fix แค่ใส่ `nonisolated` ก็จบ — ไม่ต้องแยก class
- **How to apply:** เจอ error ลักษณะ "Main actor-isolated X can not be referenced from a nonisolated context" หลังเพิ่ม protocol → ตรวจ deinit / C callback / `@convention(c)` closure แล้ว mark statics เป็น `nonisolated` (ไม่ใช่ `nonisolated(unsafe)` ก่อน — ใส่ `unsafe` เฉพาะตอน Swift บ่นว่า value ไม่ Sendable)

---

### Time-based test edges: `Date.addingTimeInterval` Double precision พังที่ boundary

- **Trigger:** ทดสอบ time-based state machine โดยเลือก timestamp แบบ `t0.addingTimeInterval(2.3)` ในจุดที่ logic เช็ค `>= 0.3` หรือ boundary อื่น
- **Issue:** Double แทน 2.3 ไม่ได้เป๊ะ (= 2.2999999...) แต่แทน 2.0 ได้เป๊ะ (integer) → diff = 2.2999998 < 0.3 ที่ Double เก็บเป็น 0.2999999889 → boundary check ที่ "ควรจะ true" กลับ false ที่ random test
- **Rule:**
  1. ใช้ค่า exact-binary (powers of 2: 0.5, 0.25, 0.125, 1.0, 2.0) สำหรับ "delta" timestamps
  2. ห้ามใส่ value ตรงกับ threshold เป๊ะ (0.3 sustain → ทดสอบที่ 0.5, ไม่ใช่ 0.3)
  3. ถ้าจำเป็นต้องทดสอบ "just under" / "just over" boundary → ใช้ค่า binary-exact ที่อยู่ขอบใกล้เคียง (0.29 < 0.3, 0.31 > 0.3) แทนการพึ่ง equality
- **Why (incident 2026-04-25):** Tier 3 `TalkingDebouncerTests.resetRequiresFreshSustain` fail เพราะ `t0.addingTimeInterval(2.3) - t0.addingTimeInterval(2.0) ≈ 0.2999999998` ซึ่ง `< 0.3` Double. แก้โดยเปลี่ยน 2.3 → 2.5 (0.5 exact, gap ห่างจากขอบ 0.3 มากพอ)
- **How to apply:** ก่อนเขียน time-based test, ถ้า logic เช็ค `>= duration` ให้เลือก test gap ห่างจาก duration อย่างน้อย 1.5x หรือใช้ค่า binary-exact

---

### `MenuBarExtra` ไม่แยก left-click กับ right-click — ต้อง switch ไป NSStatusItem ถ้าต้องการ right-click distinct action

- **Trigger:** ต้องให้ menu-bar icon ทำงานต่างกันตาม mouse button (เช่น Phase 2: left = open popover, right = quick toggle mute)
- **Rule:** SwiftUI `MenuBarExtra` ทุก style (`.menu`, `.window`) ส่ง click event ไปทาง action เดียวกันโดยไม่บอกว่าเป็น left/right → ต้อง drop ลงไปใช้ `NSApplicationDelegateAdaptor` + `NSStatusBar.system.statusItem(...)` + `button.sendAction(on: [.leftMouseUp, .rightMouseUp])` แล้วอ่าน `NSApp.currentEvent.type` ใน selector
- **Pattern ที่ใช้:** AppDelegate hold `NSStatusItem` + `NSPopover` (popover แทน MenuBarExtra window). Click handler:
  ```swift
  @objc func handleClick(_ sender: Any?) {
      guard let event = NSApp.currentEvent else { return }
      switch event.type {
      case .rightMouseUp: appState.toggleMute()
      case .leftMouseUp:
          if event.modifierFlags.contains(.control) { appState.toggleMute() }
          else { togglePopover() }
      default: break
      }
  }
  ```
- **AppDelegate ต้อง mirror XCTest guard ของ AppState** — `applicationDidFinishLaunching` ถูกเรียกตอน hosted test bundle launch app เข้า process; ถ้าไม่ guard จะมี status item โผล่ใน user's menu bar ทุกครั้ง run test + AppState.start() จะ fire (ที่จริงตัวเองมี guard อยู่แล้ว แต่ TrayController.install() ไม่มี → ต้อง guard ที่ AppDelegate level)
- **Why (incident 2026-04-25):** Phase 2 migrate menu-bar layer; `MenuBarExtra` ไม่มี API surface ใดๆ สำหรับ right-click — search Apple docs / forum confirm "by design". SwiftUI-only solution = wrap NSViewRepresentable ก็ไม่ work เพราะ button event ถูกตัดไปแล้วก่อนถึง view. คุ้มที่จะ drop เป็น AppKit เพราะ NSStatusItem + NSPopover แค่ ~80 LOC ได้ control เต็ม
- **How to apply:** ถ้า requirement บอก "right-click ทำ X" หรือ "modifier-click ทำ Y" บน menu bar icon → หยุดคิดเรื่อง MenuBarExtra ทันที, ไป AppDelegate + NSStatusItem โดยตรง. หากเดิม app ใช้ MenuBarExtra อยู่แล้ว, migrate cost = ~1-2 ชม. (รวมเขียน Settings scene กลับ + popover sizing)

---

### `withObservationTracking` เป็น single-fire — ต้อง re-subscribe ภายใน `onChange`

- **Trigger:** ต้องการ propagate `@Observable` state changes ไป AppKit/UIKit imperative code (เช่น set `NSStatusItem.button.image` เมื่อ status เปลี่ยน) — ไม่อยู่ใน SwiftUI view tree
- **Rule:** `withObservationTracking { read } onChange: { ... }` fire `onChange` เพียง **ครั้งเดียว** ต่อการ subscribe — ใน `onChange` ต้อง schedule กลับไป main actor แล้วเรียก function ตัวเองอีกครั้งเพื่อ re-subscribe:
  ```swift
  private func observeStatus() {
      withObservationTracking { [weak self] in
          _ = self?.appState.status
      } onChange: {
          Task { @MainActor [weak self] in
              guard let self else { return }
              self.applyToButton()
              self.observeStatus()  // re-arm
          }
      }
  }
  ```
- **ระวัง:** `onChange` block ถูกเรียก nonisolated และ before การ mutation เสร็จสิ้น — อ่าน `appState.status` ตรงๆ ใน `onChange` จะได้ค่าเก่า. ใช้ `Task { @MainActor in self.applyToButton() }` เพื่อข้ามไป next runloop tick
- **Why (incident 2026-04-25):** Phase 2 wire `appState.status → NSStatusItem.button.image`. ถ้าไม่ re-subscribe → button update ครั้งแรกแล้วค้าง. forgot-to-re-arm คือ pitfall ที่พบบ่อยที่สุดของ Observation API
- **How to apply:** ใช้ pattern นี้เฉพาะที่ต้อง bridge `@Observable` → AppKit imperative. ใน SwiftUI view ไม่ต้องทำ — view tree handle ให้เอง

---

### MainActor-isolated init ใช้เป็น default parameter value ไม่ได้

- **Trigger:** เขียน `init(dep: any Foo = RealFoo())` ที่ `RealFoo()` is `@MainActor` (implicit จาก project default หรือ explicit) → compile fail "call to main actor-isolated initializer 'init()' in a synchronous nonisolated context"
- **Why:** Default parameter values ถูก evaluate ใน synthetic non-isolated context ที่ Swift gen เอง — ไม่สืบ caller's isolation
- **Rule:** ใช้ pattern 2-init แทน:
  ```swift
  convenience init() {
      self.init(dep: RealFoo())  // caller's @MainActor inferred
  }
  init(dep: any Foo) { ... }     // designated, no defaults
  ```
- **Alternative:** `init(dep: (any Foo)? = nil)` แล้ว `self.dep = dep ?? RealFoo()` ใน body — ก็ได้แต่ต้องระวัง accidental nil pass
- **Why (incident 2026-04-25):** Tier 2 DI refactor `AppState.init(muteController: any MicMuteControlling = MicMuteController(), ...)` → fail แม้ `AppState` คือ `@MainActor`. Fix ด้วย convenience init pattern
- **How to apply:** ทุกครั้งที่อยากให้ caller ไม่ต้องระบุ deps ใน production แต่ test inject mocks ได้ → 2-init pattern คือ idiomatic Swift, ไม่ใช่ workaround
