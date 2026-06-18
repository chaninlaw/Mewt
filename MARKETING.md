# Mewt — Marketing & Branding

## Brand Identity

### ชื่อ: Mewt
- ที่มา: Mute + Meow — เล่นคำ สื่อทั้งฟีเจอร์หลัก (mute mic) และ mascot (แมว)
- จำง่าย, ค้นหาง่าย, จด trademark ได้

### Tagline
*"Your mic buddy that listens when you talk."*

### Mascot
แมว Mewt — pixel-art mascot สีครีม/เบจ ที่หลับตอน mute และเปลี่ยนสถานะตามการพูด

---

## App Store

### Category
- Primary: Utilities
- Secondary: Entertainment

### Keywords
mute mic, microphone, meeting companion, desk pet, mic indicator, push to talk, menu bar

### Screenshot Strategy (5 ภาพ) — 1.0
1. **Hero**: แมว pixel-art ใน popover + status "Unmuted" / Input Level bar — hook ด้วยความน่ารัก + ฟีเจอร์หลัก
2. **One-click mute** จาก menu bar (right-click toggle, left-click popover) — สื่อ utility
3. **Push-to-talk + hotkey settings** — สื่อ control / shortcut-driven
4. **Welcome card** ที่แสดง privacy promise (local-only, no network, no account) — สื่อ trust
5. **Menu-bar icon + status switching** (unmuted/muted/talking) — สื่อ live indicator

---

## 1.0 Ship Scope — "Mewt Mic" (free)

ทุกอย่างที่ 1.0 ship มี — ไม่มี IAP, ไม่มี account, ไม่มี network.

### Core features
- Mute / unmute ด้วย left-click popover button หรือ right-click menu-bar icon
- Global hotkey: toggle mute (default ⌥M), push-to-talk (default ⌥Space)
- Real-time input level meter ใน popover
- Status mascot — pixel-art cat ที่เปลี่ยนสถานะตาม mic state
- First-run welcome card + contextual mic-permission prompt

### Privacy guarantees
- 100% local — ไม่มี network call, ไม่มี analytics, ไม่มี crash reporter
- ไม่มี account, ไม่มี sign-in
- Audio ไม่ถูก record, ไม่ถูก store, ไม่ถูก transmit
- Privacy Manifest declares "no data collected, no tracking"

---

## Future Roadmap (post-1.0)

ขั้นต่อไปขึ้นกับ usage data หลัง 1.0 ship — **ยังไม่ commit ราคา/timeline**. รายการนี้คือไอเดียที่มีกระบวนการประเมินอยู่:

### "Mewt Plus" (planned, IAP)
- Animated character packs: หมา, นก, กระต่าย — ขยับปาก / กระดิกหู ตาม amplitude
- Pet moods + custom colors & accessories (หมวก, แว่น, โบว์)
- ปรับขนาด, opacity, ตำแหน่งบนจอ (re-enable overlay window)

### "Mewt Studio" (planned, IAP)
- ทุกอย่างใน Plus
- User-imported character packs (Lottie / GIF / custom sprite sheet)
- สร้าง + แชร์ character เอง

> **Important**: ไม่เอาราคา/ฟีเจอร์ paid tier ใส่ใน App Store description ของ 1.0 — Apple จะขอ proof ของ IAP ที่ยังไม่มีจริง.

---

## แมว 1.0 — Character Design

### รูปลักษณ์ (ที่ 1.0 ship)
- Pixel-art แมวสีครีม/เบจ ขนาด ~80pt ใน popover hero card, ~18pt ใน menu bar
- Source asset: `assets/CatMascot/rotations/south.png` (92×92 pixel-art sprite)
- ตัวแอป SF Symbol-based badge ตามสถานะ (ขณะที่ bundled animated pack ยัง dark-launched)

### สถานะ (เปลี่ยนตาม mic + amplitude)
- **Unmuted**: ตาเปิด — มาตรพร้อมฟัง, ไม่มี badge
- **Talking**: ตาเปิด + waveform badge — amplitude เหนือ threshold
- **Muted**: ตาเปิด + paw-print badge — mic ปิด
- **Push-to-talk**: temporary unmute while held

### ข้อจำกัด (เปิดทางให้ Plus ในอนาคต)
- ไม่ขยับปากตามเสียง (ใช้ status switching แทน animation)
- ไม่กระดิกหู / กะพริบตา
- ไม่มี accessories
- มีตัวเลือก character pack แค่ตัวเดียว

---

## Value Propositions

### ทำไมคนจะรัก 1.0 (acquisition)
- **No-friction utility** — Hotkey toggle เร็วกว่าเปิด System Settings / คลิกใน Zoom-Meet-Discord
- **Always-visible state** — Menu-bar icon บอก mic state ตลอดเวลา (เห็นโดยไม่ต้อง alt-tab)
- **Privacy-first** — Local-only, ไม่มี account, ไม่มี data collection. ผู้ใช้ที่ระวังเรื่อง privacy ไว้ใจง่าย
- **Light footprint** — Menu bar accessory, ไม่กิน Dock space, ไม่กิน RAM เยอะ

### ทำไมคนจะอยากอัพเกรด (future, post-data)
- **Emotional attachment** — pet อยู่บนจอทั้งวัน เหมือน Tamagotchi ยุคใหม่
- **Social proof** — เพื่อนร่วมงานเห็นใน meeting แล้วถามว่าแอปอะไร = organic marketing
- **Personalization** — คนยอมจ่ายเพื่อให้ของบนจอเป็น "ของฉัน" (เหมือน sticker LINE)

> Ship 1.0 → เก็บ analytics → ตัดสินใจ Plus/Studio scope ตามข้อมูลจริง (ไม่ build paid tier ก่อนรู้ว่าคนจ่ายฟีเจอร์ไหน)
