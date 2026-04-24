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
