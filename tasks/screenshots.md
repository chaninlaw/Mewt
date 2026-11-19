# Mewt Mic — App Store Screenshots

6 screenshots, rendered from code. No manual capture, no desktop cleanup, no design tool.

```bash
scripts/screenshots.sh
```

That's it. The script renders every shot, copies the PNGs into `tasks/screenshots/`, and checks each one is 2880×1800, RGB, no alpha. Upload them to App Store Connect in filename order.

---

## How it works

The real SwiftUI views (`ContentView` and its pages) are hosted offscreen with fixture state, then drawn into a 2880×1800 bitmap (960×600 pt at 3x). Nothing in the popover is redrawn by hand, so the shots stay true to the build: change the UI, re-run the script.

| File | Role |
|---|---|
| `MewtTests/Screenshots/ScreenshotTests.swift` | Shot list: fixture state, captions, file names |
| `MewtTests/Screenshots/ScreenshotArtboard.swift` | Artboard layout, brand palette, mock menu bar, popover chrome |
| `MewtTests/Screenshots/ScreenshotRenderer.swift` | Offscreen render → flattened sRGB PNG |
| `scripts/screenshots.sh` | Runs the suite, copies output, verifies size/alpha |

Details:
- The suite only runs when `MEWT_SCREENSHOTS` is set (the script passes `TEST_RUNNER_MEWT_SCREENSHOTS=1`). Normal `xcodebuild test` runs skip it.
- The test host is sandboxed, so PNGs are written to `~/Library/Containers/com.chaninlaw.Mewt/Data/tmp/MewtScreenshots/` first; the script copies them out.
- Fixtures use the test doubles (`MockMuteController`, `MockAudioLevelMonitor`, `MockTipBackend`) and a throwaway `UserDefaults` suite. Nothing touches the real mic, TCC, or StoreKit.
- Hotkey labels come from `KeyboardShortcuts`, which reads the app's real defaults. If you've rebound your hotkeys, reset them to ⌥M / ⌥Space before rendering.
- The render window is made key and active (parked off-screen) so prominent buttons draw in the accent colour. The accent is the Mac's system accent, so render on a Mac set to the default (blue) accent.
- Tip prices are shown in USD ($0.99 / $2.99 / $9.99, Apple's tiers for ฿35 / ฿99 / ฿349), since the gallery is shown worldwide.

## Style

Style (ก), chosen 2026-11-19: flat brand background (`#F7F7F5` → `#EDEDE9`, from `site/styles.css`), caption on the left, and on the right a rounded slice of desktop (warm wallpaper, mock menu bar) with the dark popover hanging from the cat icon.

Caption block: eyebrow (13pt, caps, tracked) → headline (44pt bold, explicit `\n` line breaks) → one sentence of detail (17pt). Keep headlines to two or three short lines; the column is 400pt wide.

## Shot list

| # | File | Popover state | Eyebrow / headline |
|---|---|---|---|
| 1 | `01-hero-unmuted.png` | Main page, unmuted, input level ~58% | MENU BAR MIC CONTROL / A mic indicator you can trust |
| 2 | `02-muted.png` | Main page, muted (paw), level flat | ONE CLICK / System-wide silence, instantly |
| 3 | `03-hotkey-settings.png` | Settings page (hotkey recorders + Report a Bug) | KEYBOARD FIRST / Any hotkey. Even push-to-talk. |
| 4 | `04-welcome-privacy.png` | Welcome page, permission not yet granted | PRIVATE BY DESIGN / 100% local. No account. No cloud. |
| 5 | `05-menu-bar-states.png` | Four menu-bar strips: unmuted, talking, push-to-talk, muted | AT A GLANCE / Your mic state, right in the menu bar |
| 6 | `06-support.png` | Support page with the 3 tip cards | FREE FOREVER / Every feature free. Tips welcome. |

Shot 6 doubles as the **IAP review screenshot** for all three tips (`tasks/app-store-connect-tips.md` step 3).

The hero uses the plain cat, not the talking animation: the `talk-*` assets cut the wave out with an SVG mask, and the mask rasterises soft at popover size. The talking glyph still appears in shot 5 at menu-bar size, where it reads fine.

## Changing things

- **Caption or state:** edit the matching `@Test` in `ScreenshotTests.swift`, re-run the script.
- **New shot:** add a `@Test`, give the file a numbered name, add a row above.
- **Layout or colours:** `ScreenshotArtboard.swift`. The popover arrow points at `MenuBarStrip.catCenterFromTrailing`; if you change the menu-bar items, adjust that constant.
- **Look at a shot quickly:** `open tasks/screenshots/01-hero-unmuted.png`.

## Sanity check before upload

- [ ] `scripts/screenshots.sh` prints ✓ for all 6 (2880×1800, RGB, no alpha)
- [ ] Each one opened and checked by eye: no clipped text, popover arrow under the cat, prominent buttons blue (not grey)
- [ ] Captions match the current build (no retired features, no paid tier, tips called "tips" never "donations")
- [ ] Hotkeys show ⌥M / ⌥Space
- [ ] Upload in order 01 → 06
