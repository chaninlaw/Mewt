# Mewt — Pre-Submission Checklist

Use this before pushing a build to App Store Connect. Tracks every reviewer-blocking item identified in the audit (`docs/` history if archived).

---

## 1. Build & Sign

- [ ] `xcodebuild -scheme Mewt -configuration Release build` — green
- [ ] `xcodebuild -scheme Mewt test` — 154/154 passing
- [ ] Archive build (`Product → Archive`) succeeds
- [ ] Code signing: **Developer ID Application** (for notarisation) **or** **Apple Distribution** (for direct App Store)
- [ ] Hardened Runtime enabled (verify in archive's `codesign -d --entitlements - <app>` output)
- [ ] Sandbox enabled with **only** `com.apple.security.app-sandbox` + `com.apple.security.device.audio-input`

## 2. Info.plist Audit

Run `plutil -p <Mewt Mic.app>/Contents/Info.plist` against the archived build and confirm:

- [ ] `LSUIElement = YES` (menu-bar accessory, no Dock icon)
- [ ] `LSApplicationCategoryType = "public.app-category.utilities"`
- [ ] `NSMicrophoneUsageDescription` matches current behavior — **no mention of "talk-while-muted detection"**. Expected copy:
  > Mewt uses your microphone to mute it system-wide and show the input level on the menu bar. Audio is processed locally and never recorded, stored, or transmitted.
- [ ] `CFBundleShortVersionString` matches `MARKETING_VERSION`
- [ ] `CFBundleVersion` bumped from previous submission

## 3. Privacy Manifest

- [ ] `Mewt/PrivacyInfo.xcprivacy` present in archived bundle (`<app>/Contents/Resources/PrivacyInfo.xcprivacy`)
- [ ] `NSPrivacyTracking` = `false`
- [ ] `NSPrivacyCollectedDataTypes` = empty array
- [ ] `NSPrivacyAccessedAPITypes` declares `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`
- [ ] If SPM dependencies ship their own privacy manifests, Xcode bundles them under `<app>/Contents/Resources/<package>.bundle/PrivacyInfo.xcprivacy` — confirm `KeyboardShortcuts` is present (or document its absence in reviewer notes)

## 4. Fresh-Install Permission Flow (manual smoke test)

On a clean macOS user (or after `tccutil reset Microphone com.chaninlaw.Mewt`):

- [ ] Launch app → cat icon appears in menu bar, **no Dock icon**
- [ ] Click menu-bar icon → welcome card appears (NOT the main page)
- [ ] Welcome card explains: what Mewt does + privacy guarantees (local only, no network, no account)
- [ ] **System mic dialog has not fired yet** at this point
- [ ] Click "Grant Microphone Access" → system dialog appears with the new usage string
- [ ] Tap **Allow** → welcome dismisses, main page shows input-level bar, mute button works
- [ ] Quit & relaunch → welcome card **does NOT** show again
- [ ] Toggle mute via menu-bar (right-click) and hotkey (⌥M) — both work
- [ ] PTT (hold ⌥Space) — temporary unmute while held, mic re-mutes on release

Repeat with **Deny** at the system dialog:

- [ ] Welcome dismisses, main page shows "Mic permission needed"
- [ ] Mute still works via menu-bar click / hotkey (CoreAudio path is separate from level monitor)

## 5. App Store Connect Metadata

- [ ] **Primary Category**: Utilities (matches `LSApplicationCategoryType`)
- [ ] **Secondary Category**: Entertainment (per `MARKETING.md`)
- [ ] **Privacy Practices** answered: **Data Not Collected** (no analytics, no network)
- [ ] **Support URL** — public page describing the app + contact info
- [ ] **Privacy Policy URL** — public page even though we don't collect data (Apple requires it)
- [ ] **Screenshots**: 5 images per the plan in `MARKETING.md` — but **drop** the "Talk-while-muted alert" screenshot (feature retired 2026-05-07)
- [ ] **App description** — do **NOT** mention "Mewt Plus $4.99/year" or any paid tier; 1.0 ships free-only without IAP
- [ ] **Keywords** — from `MARKETING.md`: mute mic, virtual microphone, meeting companion, desk pet, animated mic indicator

## 6. App Review Notes (paste into App Store Connect)

```
Mewt is a menu-bar utility that mutes your microphone system-wide and
shows live input level. There is no account, no network, no in-app
purchase, and no data collection.

How to test:
1. Launch the app. A cat-face icon appears in the menu bar (top-right).
   The Dock is intentionally empty — this is an accessory app
   (LSUIElement).
2. Left-click the menu-bar icon. On first launch you'll see a welcome
   card explaining what the app does and how mic permission is used.
3. Click "Grant Microphone Access" — the standard system dialog will
   appear. Tap Allow.
4. The popover transitions to the main page. You will see:
   - The cat mascot (status indicator)
   - A Mute/Unmute button
   - The current input level (a horizontal bar)
   - Hotkey hints
5. Click "Mute" — your system audio input goes silent across all apps
   (verified via System Settings > Sound > Input or any meeting app).
6. Click "Unmute" — input restored.
7. Hotkeys (default):
   - Toggle Mute: ⌥M (Option + M)
   - Push-to-Talk: ⌥Space (hold to temporarily unmute)
   You can change these under "Settings…" inside the popover.
8. Right-click the menu-bar icon to toggle mute without opening the
   popover.

Permissions:
- Microphone access is required only to control the mute state and
  display input level. Audio is never recorded, stored, or transmitted.
  All processing is local.

No account or sign-in is required. The app works fully offline.

Privacy policy: <YOUR_PRIVACY_URL>
Support: <YOUR_SUPPORT_URL>
```

## 7. Final Sanity

- [ ] No `print(...)` statements in Release build (use `Logger` instead — currently clean)
- [ ] No TODO/FIXME comments referring to "ship blocker" — `grep -rn "TODO\|FIXME" Mewt/`
- [ ] Bundle name in Finder reads **"Mewt Mic"** (current `PRODUCT_NAME`) — decide whether to keep "Mic" suffix or rename to plain "Mewt" before submission (display name affects discoverability)
- [ ] `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` are unique vs. last submission
