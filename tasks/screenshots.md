# Mewt Mic — Screenshot Spec

5 screenshots, ordered by priority. App Store lets you upload up to 10; we ship 5 to keep the gallery tight.

---

## Technical Requirements

| Field           | Value                                                                   |
| --------------- | ----------------------------------------------------------------------- |
| **Format**      | PNG, RGB, no alpha                                                      |
| **Color space** | sRGB                                                                    |
| **DPI**         | 72                                                                      |
| **Dimensions**  | One of: `1280×800`, `1440×900`, `2560×1600`, `2880×1800`                |
| **Target**      | `2880×1800` (Retina, future-proof — App Store down-scales for previews) |

> If shooting on M-series Mac with Retina display: native screenshot is `2880×1800` at 72dpi. Just don't scale it down.

---

## Capture Setup (one-time)

```bash
# Clean desktop: hide all icons
defaults write com.apple.finder CreateDesktop -bool false && killall Finder

# Hide menu-bar clutter (or use Bartender to tuck non-essential icons)
# In System Settings → Control Center, set "Battery", "Wi-Fi", "Sound" → Don't Show in Menu Bar
# Leave: Mewt cat icon, clock, Control Center

# Set a neutral wallpaper (cream/beige to match brand) — or use Apple's default
```

After each capture, restore:

```bash
defaults write com.apple.finder CreateDesktop -bool true && killall Finder
```

---

## Capture Commands

```bash
# Window screenshot (includes shadow — usually nicer for App Store)
# Press ⌘+⇧+4, then SPACE, then click on the window
# Saves to Desktop as "Screen Shot YYYY-MM-DD at HH.MM.SS.png"

# Area screenshot for menu-bar shots (no shadow)
# Press ⌘+⇧+4, drag selection over the menu-bar region

# CLI alternative (good for scripting)
screencapture -w ~/Desktop/mewt-shot.png     # interactive window pick
screencapture -R x,y,w,h ~/Desktop/area.png  # exact rectangle
```

---

## Shot List

### Shot 1 — Hero: Popover with Cat + Input Level

**Goal**: Hook in 1 second. Show the mascot, the level meter, and "the mic is on" state.

- App state: **Unmuted**, mid-speech (input level bar partially filled)
- Open the popover by clicking the menu-bar icon
- Capture: Popover window + the cat-face menu-bar icon visible above
- Caption (App Store overlay, optional): _"A live mic indicator you can trust"_

**Tip**: Talk softly while triggering screenshot so amplitude bar shows movement but not clipping. Or fake it by toggling debug if available.

---

### Shot 2 — Muted State

**Goal**: Show the contrast — cat sleeping / muted badge, level bar flat.

- App state: **Muted**
- Popover open, "Unmute" button visible
- Menu-bar icon shows muted variant

Caption: _"One click, system-wide silence"_

---

### Shot 3 — Hotkey Settings

**Goal**: Show customisation depth without going overboard.

- Open Settings… from popover
- Show hotkey configuration row with `⌥M` and `⌥Space` visible
- Crop to settings panel only (don't include full window chrome if it's noisy)

Caption: _"Bind any hotkey, including push-to-talk"_

---

### Shot 4 — Welcome Card (Privacy Promise)

**Goal**: Sell trust. This is the screenshot that converts privacy-conscious buyers.

- Trigger: `tccutil reset Microphone com.chaninlaw.Mewt && open /Applications/Mewt\ Mic.app`
- Capture the first-run welcome card showing the privacy bullet points (local-only, no network, no account)
- Don't trigger the system mic prompt — capture BEFORE clicking "Grant"

Caption: _"100% local. No account. No cloud."_

---

### Shot 5 — Menu-Bar Status Switching

**Goal**: Show that the menu-bar icon is informative without opening the popover.

- Compose a 3-state strip in a single image:
  - Left third: unmuted icon
  - Middle third: talking icon (with waveform badge)
  - Right third: muted icon (with paw-print badge)
- Either screenshot the menu bar 3 times and composite in Preview/Figma, OR
- Take a single wide menu-bar capture during a live demo if all 3 states cycle quickly

Caption: _"See your mic state at a glance"_

---

## File Naming

Save with leading numbers so they upload in order:

```
01-hero-unmuted.png
02-muted.png
03-hotkey-settings.png
04-welcome-privacy.png
05-menu-bar-states.png
```

Keep originals in `tasks/screenshots/originals/` (gitignored — these are big files). Upload to App Store Connect directly from disk.

---

## Sanity Check Before Upload

- [ ] All 5 are `2880×1800` (Retina) or scaled-from-Retina, not stretched up from low-res
- [ ] No personal info visible (other menu-bar icons removed, Dock hidden / on another display)
- [ ] No wallpaper with copyright or recognisable third-party content
- [ ] No marketing copy that contradicts current build (no "Plus" mentions, no "talk-while-muted alert")
- [ ] If overlays/captions are added in design tool, embed them — App Store will NOT add captions for you
- [ ] PNG, sRGB, no alpha — verify with `sips -g all 01-hero-unmuted.png`

---

## Optional: Add Captions in a Design Tool

App Store does not provide overlay text — if you want captions like the ones above, composite them in Figma/Sketch/Pixelmator before exporting.

Simple recipe:

1. New `2880×1800` artboard, cream/beige background matching brand
2. Place the raw screenshot at ~80% size, slightly offset
3. Add bold caption text above or below
4. Export PNG at full resolution

This is optional — pure screenshots also work fine for a utility app where the UI sells itself.
