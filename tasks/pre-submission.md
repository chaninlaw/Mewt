# Mewt — Pre-Submission Checklist

Use this before pushing a build to App Store Connect. Tracks every reviewer-blocking item identified in the audit (`docs/` history if archived).

---

## 1. Build & Sign

- [x] `xcodebuild -scheme Mewt -configuration Release build` — green
- [x] `xcodebuild -scheme Mewt test` — 179/179 passing (2026-11-19, incl. tips + bug report)
- [x] Archive build (`Product → Archive`) succeeds — verified 2026-07-08 via `xcodebuild -scheme Mewt -configuration Release archive` → **ARCHIVE SUCCEEDED**. Re-verified in bundle: `flags=0x10000(runtime)`, entitlements `app-sandbox` + `device.audio-input`, Info.plist `LSUIElement`/utilities/`1.0(1)`, mic usage string correct
- [x] Code signing: **Developer ID Application** (for notarisation) **or** **Apple Distribution** (for direct App Store)
- [x] Hardened Runtime enabled (`ENABLE_HARDENED_RUNTIME = YES` in pbxproj — re-verify in archive's `codesign -d --entitlements - <app>` output)
- [x] Sandbox enabled with `com.apple.security.app-sandbox` + `com.apple.security.device.audio-input` (verified in `Mewt/Mewt.entitlements`). Signed bundle also includes `com.apple.security.files.user-selected.read-only` injected by Xcode as a sandbox default — benign, not a rejection cause

## 2. Info.plist Audit

Info.plist is generated (`GENERATE_INFOPLIST_FILE = YES`); source of truth is `INFOPLIST_KEY_*` in `Mewt.xcodeproj/project.pbxproj`. Re-verify post-archive with `plutil -p <Mewt Mic.app>/Contents/Info.plist`.

- [x] `LSUIElement = YES` (menu-bar accessory, no Dock icon) — `INFOPLIST_KEY_LSUIElement = YES`
- [x] `LSApplicationCategoryType = "public.app-category.utilities"` — `INFOPLIST_KEY_LSApplicationCategoryType`
- [x] `NSMicrophoneUsageDescription` matches current behavior — **no mention of "talk-while-muted detection"**. Current copy in pbxproj:
  > Mewt uses your microphone to mute it system-wide and show the input level on the menu bar. Audio is processed locally and never recorded, stored, or transmitted.
- [x] `CFBundleShortVersionString` matches `MARKETING_VERSION` (both `1.0`, generated automatically)
- [x] `CFBundleVersion` set (`CURRENT_PROJECT_VERSION = 1`) — first submission, no prior build to bump from

## 3. Privacy Manifest

Source: `Mewt/PrivacyInfo.xcprivacy`. Re-verify post-archive with `plutil -p <app>/Contents/Resources/PrivacyInfo.xcprivacy`.

- [x] `Mewt/PrivacyInfo.xcprivacy` present in source — confirm in archived bundle (`<app>/Contents/Resources/PrivacyInfo.xcprivacy`)
- [x] `NSPrivacyTracking` = `false`
- [x] `NSPrivacyCollectedDataTypes` = empty array
- [x] `NSPrivacyAccessedAPITypes` declares `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`
- [x] SPM privacy manifests — checked archived bundle: `KeyboardShortcuts_KeyboardShortcuts.bundle` ships **only** `Info.plist` + localized `.strings` (no `PrivacyInfo.xcprivacy`). KeyboardShortcuts 2.4.0 declares no manifest and uses no required-reason APIs, so its absence is benign. If a reviewer flags it, note: "KeyboardShortcuts 2.4.0 accesses no privacy-relevant APIs; the app-level PrivacyInfo.xcprivacy covers all declared usage."

## 4. Fresh-Install Permission Flow (manual smoke test)

Tested against archived `Mewt Mic.app` after `tccutil reset Microphone com.chaninlaw.Mewt` + `defaults delete com.chaninlaw.Mewt`. All 11 checkpoints passed.

- [x] Launch app → cat icon appears in menu bar, **no Dock icon**
- [x] Click menu-bar icon → welcome card appears (NOT the main page)
- [x] Welcome card explains: what Mewt does + privacy guarantees (local only, no network, no account)
- [x] **System mic dialog has not fired yet** at this point
- [x] Click "Grant Microphone Access" → system dialog appears with the new usage string
- [x] Tap **Allow** → welcome dismisses, main page shows input-level bar, mute button works
- [x] Quit & relaunch → welcome card **does NOT** show again
- [x] Toggle mute via menu-bar (right-click) and hotkey (⌥M) — both work
- [x] PTT (hold ⌥Space) — temporary unmute while held, mic re-mutes on release

Repeat with **Deny** at the system dialog:

- [x] Welcome dismisses, main page shows "Mic permission needed"
- [x] Mute still works via menu-bar click / hotkey (CoreAudio path is separate from level monitor)

## 5. App Store Connect Metadata

- [ ] **Primary Category**: Utilities (matches `LSApplicationCategoryType`)
- [ ] **Secondary Category**: Entertainment (per `MARKETING.md`)
- [ ] **Privacy Practices** answered: **Data Not Collected** (no analytics, no network)
- [x] **Support URL** — `https://mewt.nin-070.workers.dev/` (Cloudflare Workers, source in `site/`)
- [x] **Privacy Policy URL** — `https://mewt.nin-070.workers.dev/privacy.html`
- [x] **Screenshots**: 5 branded artboards built + verified in `tasks/screenshots/` (`01-hero-unmuted` … `05-menu-bar-states`), all 2880×1800 PNG/sRGB/no-alpha. Real app UI captured via CLI, composited on brand background with baked captions. The retired "Talk-while-muted alert" shot is **not** included. Ready to upload from disk
- [ ] **App description** — do **NOT** mention "Mewt Plus $4.99/year" or any paid tier. 1.0 is free with optional tips (see §8) — call them "tips" / "Support Mewt", never "donations"
- [ ] **Keywords** — from `MARKETING.md`: mute mic, virtual microphone, meeting companion, desk pet, animated mic indicator

## 6. App Review Notes (paste into App Store Connect)

```
Mewt is a menu-bar utility that mutes your microphone system-wide and
shows live input level. There is no account, no network, and no data
collection.

Support Mewt includes 3 optional consumable in-app purchases (tips) under
guideline 3.1.1. Tips unlock no functionality or digital content; all
features of the app remain 100% free. The app makes no direct network
calls and does not require the outgoing network entitlement. To find the
tips: open the popover and click the heart icon in the footer.

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

Privacy policy: https://mewt.nin-070.workers.dev/privacy.html
Support: https://mewt.nin-070.workers.dev/
```

## 7. Final Sanity

- [x] No `print(...)` statements in source (`grep -rn "print(" Mewt/` clean — uses `Logger`)
- [x] No TODO/FIXME comments in source (`grep -rn "TODO\|FIXME" Mewt/` clean)
- [x] Bundle name in Finder reads **"Mewt Mic"** (current `PRODUCT_NAME`) — decision: keep `Mewt Mic` for App Store discoverability ("Mic" in app name helps users searching for "mute mic"/"microphone")
- [x] `MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION = 1` — first submission, no prior build to clash with

## 8. Support Mewt (tips) — 1.0 scope

Spec: `docs/specs/2026-10-19-mewt-support-and-feedback-design.md`. First IAP must ship together with the 1.0 version in the same submission.

- [x] **Implementation** — `Mewt/Support/` (`TipStore`, `StoreKitTipBackend`, `SupportPage`), heart in popover footer, popover pinned during purchase, `Transaction.updates` listener from launch, repo-root `Tips.storekit` (not bundled), `TipStoreTests` + `StoreKitTipBackendTests`
  - [ ] Click through the Support page by hand in a Debug run (scheme → Run → Options → StoreKit Configuration = `Tips.storekit`)
- [x] **Report a Bug** — Email / GitHub Issues buttons in Settings with sanitized diagnostics (spec §6), plus `.github/ISSUE_TEMPLATE/bug_report.yml` + `config.yml` — `AppDiagnostics` + `ReportBugSection`, `AppDiagnosticsTests`
  - [ ] Click Email… and GitHub Issues… by hand once — draft opens with diagnostics; GitHub form's Diagnostics field is prefilled (needs the templates pushed to `main`)
- [ ] **Paid Applications Agreement** active in App Store Connect, with banking + tax info filled — IAPs can't go live without it, even in a free app
- [ ] **Create 3 consumables in ASC** — `com.chaninlaw.Mewt.tip.treat` (฿35), `.tuna` (฿99), `.tower` (฿349); each with reference name, en-US display name, description containing "Tip", and a 2880×1800 no-alpha review screenshot of the Support page
- [ ] **Attach the 3 IAPs to the 1.0 version page** before pressing Submit for Review
- [x] **`site/privacy.html`** — keep "Data Not Collected"; add the payments line: "In-App Purchases (tips) are handled directly by Apple's App Store. Mewt does not receive or store any payment information, billing details, or personal data." — done 2026-11-19, plus a Bug reports section; effective date bumped. Redeploy the site before submitting
- [x] **No "Donate" anywhere** — `grep -rni donat Mewt/ site/ tasks/app-store-listing.md` clean (guideline 3.2.2(iv)) — only hit is the internal "never call them donations" note
- [ ] **Sandbox purchase on a release-like build** — scheme StoreKit Configuration = **None**, dedicated Sandbox Tester (Interrupt Purchases **Off**); buy each tip, confirm thank-you shows and popover stays open, Console shows 0 `deny(1) network-outbound`, then relaunch with Console filtered to `subsystem:com.chaninlaw.Mewt category:TipStore` and expect **no** `Tip delivered via updates` line (proves `finish()` stuck — couldn't be asserted reliably under `SKTestSession`; if it shows, the launch listener finishes it, so worst case is one stale thank-you)
- [x] **Re-run §1** (Release build, tests, archive) after tips land — 2026-11-19: ARCHIVE SUCCEEDED, entitlements unchanged (no `network.client`), `Tips.storekit` not in bundle, 179/179 tests
