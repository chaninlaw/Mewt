# Mewt — Task Log

## Now — Retire talkWhileMuted feature (2026-05-07)

User-tested wired USB with macOS 26.4.1: alarm no longer fires. Code path is **identical** to Phase 3 (`0c0f30e`) where verification passed on 2026-04-26 — diff between then and HEAD on `MicMuteController.mute()`, `AudioLevelMonitor`, `TalkingDebouncer`, `AppState.isTalkingWhileMuted` shows no behavioural change. Conclusion: macOS 26.4 → 26.4.1 dot release tightened HAL-mute enforcement so `kAudioDevicePropertyMute = 1` now silences the AVAudioEngine tap on wired devices too. There is no longer a transport on which the feature works (Bluetooth was already off; built-in / USB now match). Aggregate-Device path is the only architectural escape and is too costly relative to the value (target user just wants their mic muted reliably; macOS itself shows the orange-dot indicator). **Decision: rip the feature out cleanly.**

### Scope of removal
- **Delete files:** `Mewt/State/TalkDetectionStatus.swift`, `Mewt/Audio/TalkingDebouncer.swift`, `MewtTests/TalkDetectionStatusTests.swift`, `MewtTests/TalkingDebouncerTests.swift`
- **`MicStatus`:** drop `.talkingWhileMuted` case + label/emoji/badge entries; keep `.talking` (mascot reaction is independent and works fine)
- **`PoseTag`:** drop `.talkingWhileMuted` case (sprite engine simplifies; `Mewt-Default.mewtpet` cat pack will need re-rasterise — gated dark-launch flag is off so no user impact today)
- **`AppState`:** drop `isSpeechDetected`, `talkDetection`, `isTalkingWhileMuted`, `refreshTalkDetectionOnly`; remove permissionDenied / engineStartFailed → talkDetection state mapping; keep amplitude/`isTalkingNow` path (drives mascot)
- **`AudioLevelMonitor`:** simplify `onLevelUpdate` to `(Float) -> Void` (drop debounced-talking second arg); remove `debouncer` field
- **UI:** remove `TalkDetectionRow` from `ContentView`; remove `Section("Talk-while-muted Detection")` from `SettingsView`; remove `talkingWhileMuted` cell from `VectorPoseView` / `SymbolPackSource` / `TrayController.composeMenuBarImage`; clean `ContentView` ProgressView tint (drop `appState.isTalkingWhileMuted` ternary)
- **Tests:** delete the 2 test files; trim references in `AppStateTests`, `MicStatusTests`, `SymbolPackSourceTests`, `PoseTagMappingTests`, `CharacterPackCodableTests`, `FrameSelectorTests`, `CharacterLoaderTests`, `MewtpetFixtures`

### Checklist
- [x] Update `tasks/todo.md` (this section)
- [x] Delete the 2 source files + 2 test files
- [x] Edit `MicStatus.swift`, `AppState.swift`, `AudioLevelMonitor.swift`
- [x] Edit `PackEnums.swift`, `PoseTagMapping.swift`, `SymbolPackSource.swift`, `VectorPoseView.swift`, `TrayController.swift`, `PoseRenderer.swift`, `CharacterLoader.swift`, `AmplitudeGate.swift`
- [x] Edit `ContentView.swift`, `SettingsView.swift`
- [x] Trim references in remaining test files
- [x] `xcodebuild build` + `xcodebuild test` green — **154/154 pass** (was 183, –29 covering the retired feature)
- [x] Add lesson to `tasks/lessons.md`
- [x] Mark Stage 1 line about alarm-triangle obsolete; remove backlog item about USB drivers

### Review (2026-05-07)
- 4 files deleted, ~700 LOC net reduction across src + tests; no app-build breakage along the way (only SourceKit indexer noise that resolved at `xcodebuild` time, matching the lesson on transient SourceKit errors).
- `MicStatus` is now 4 states; `PoseTag` 5 (preserves `.idle` distinction). `AmplitudeGate` doc updated; `AmplitudeSmoother` untouched.
- `Mewt-Default.mewtpet` cat pack still ships in `Resources/` (gated by `bundledPackEnabled = false`). Its sprite sheet had a `talkingWhileMuted` row — when the flag flips back on someday, `scripts/build_default_pack.py`'s `TAG_ORDER` will need a corresponding edit. Left a TODO in the backlog rather than re-baking the pack now (it's dormant).
- `TrayController.composeMenuBarImage` keeps the `badge:` parameter signature even though every `MicStatus.menuBarBadgeSymbol` now returns `nil`. Cheap optionality for the next badge-bearing state, and the function keeps a stable canvas size which (per the existing comment) prevents menu-bar reflow on transitions. No-cost insurance.
- One test (`Status walks through real events end-to-end`) initially failed because I added a "level=0 → unmuted" closing assertion that the EMA can't satisfy synchronously; the existing comment about `AmplitudeSmoother` decaying on wall-clock time predicted exactly this. Removed the assertion (the gate-close path is covered by `AmplitudeGateTests.closesAtExit`).

---

## Earlier — Cat-themed Symbol pack + tray/Settings redesign (2026-05-06)

User accepted Symbol pack but wants the symbols to feel like **Mewt the cat app** + the popover/Settings copy refreshed to modern Apple style. Three stages — Stage 1 first, check in before Stage 2.

### Stage 1 — Cat-themed composite SF Symbols ✅
SF Symbols only ships 4 cat variants (`cat`, `cat.fill`, `cat.circle`, `cat.circle.fill`) — not enough for the unique states we needed. Use composite pattern (Apple Mail/Messages badge style): `cat.fill` as identity + small state badge bottom-right.

- [x] Refactored `SymbolPackSource.symbolDescriptor` → main + optional badge + colors per state. Per-state badges: muted=zzz, talking=waveform, pushToTalk=radio waves (accent), unmuted=none. (The `talkingWhileMuted=alarm triangle` mapping was retired in 2026-05-07 with the feature itself.)
- [x] Render composite per cell — `drawTintedSymbol` helper + `SymbolAnchor.center/.bottomRight` keeps anchoring testable.
- [x] `MicStatus`: dropped `menuBarSymbol`; added `menuBarMainSymbol` (always cat.fill) + `menuBarBadgeSymbol` (optional state badge).
- [x] `TrayController.composeMenuBarImage` builds template NSImage stacking main + badge at standard 18pt menu-bar size.
- [x] Tests 182/182 green. `MicStatusTests` rewritten to test new composite contract.

### Stage 1.5 — SVG cat + paw-print + live SwiftUI animations ✅ (2026-05-06)
User flagged that SF-Symbol composite shifted layout + alarm cell rendered empty on macOS 26. Brought in custom SVGs and switched to a live SwiftUI render path with whole-image animations (Framer-Motion-style scale/rotate from a single TimelineView).

- [x] `Mewt/Assets.xcassets/cat.imageset/` + `paw-print.imageset/` — template + preserves-vector-representation
- [x] `VectorPoseView` — TimelineView-driven, per-state formulas for breathing / shake / jitter / amplitude pulse / paw tap; respects `accessibilityReduceMotion`
- [x] `MascotView` — single dispatch point: SymbolPackSource → VectorPoseView, otherwise PoseRenderer (sprite engine for `.mewtpet`)
- [x] `TrayController.composeMenuBarImage` — main glyph now `NSImage(named: "cat")` template; badge stays SF Symbol
- [x] Tests 183/183 green

### Stage 1.6 — Static composition + paw-print as muted badge ✅ (2026-05-06)
User swapped to fill-style SVGs with tighter viewBox (rendering looks better) and decided animations weren't worth it. Also re-cast the paw-print to mark `.muted` (a paw print signals "the cat's here, just resting" which fits cat-themed identity better than zzz).

- [x] `VectorPoseView` — stripped TimelineView / `accessibilityReduceMotion` / animation curves; static composition only. Dropped unused `amplitude` param. Muted badge: zzz → `Image("paw-print")`.
- [x] `MascotView` — drop `amplitude:` from VectorPoseView call site (engine path still gets it).
- [x] `MicStatus.menuBarBadgeSymbol` — muted: `"zzz"` → `"paw-print"`. Comment notes asset-then-symbol resolution.
- [x] `TrayController.composeMenuBarImage` — badge resolves asset-catalog first, falls back to SF Symbol. Both end up at ~55% canvas.
- [x] `MicStatusTests.mutedBadgeIsZzz` → `mutedBadgeIsPawPrint`. Tests 183/183 green.

### Stage 2 — Tray popover redesign + copy ✅ (2026-05-07)
- [x] Hero status card — surfaced VStack (`.quaternary` fill, 12pt corner) with mascot 80pt + status `.title3.weight(.semibold)` + optional caption message, center-aligned
- [x] Mascot state-change transition — `.id(status)` + `.opacity.combined(with: .scale(0.92))` + `.smooth(0.25)` on `VectorPoseView`. Note: dropped `symbolEffect(.replace)` from original wording — it's SF-Symbol-only and our mascot is custom SVG since Stage 1.6, so the modifier would be a no-op. The opacity+scale transition achieves the same intent on vector assets.
- [x] Mute button: `Label(systemImage: mic.fill / mic.slash.fill)` + `.borderedProminent` + `.controlSize(.large)`. Accessibility strings preserved.
- [x] Input Level demoted: `.caption2` label, slim ProgressView, no surrounding divider — tight rhythm under the mute button.
- [x] Hotkey hints moved below input level + `Divider()`, just above Settings/Quit row. Pill design unchanged (already compact).
- [x] Copy fix: `MicStatus.pushToTalk.label` "Talking (PTT)" → "Push-to-Talk". Internal symbols (`pushToTalk`, `onPTTDown`, hotkey-name `"pushToTalk"`) untouched — not user-visible.
- [x] `xcodebuild build` + `xcodebuild test` green — 154/154 pass.

#### Review (2026-05-07)
- ContentView grew from 93 → 109 lines net; the hero card extracted into its own private `HeroStatusCard` view to keep the body scannable.
- No tests broke. `MicStatusTests.nonEmptyLabels` covered the pushToTalk copy change implicitly (no string-pinning assertion existed). No new tests added — Stage 2 is layout/copy, both visible-only changes.
- SourceKit indexer reported transient "Cannot find 'MicStatus'" / "No such module 'KeyboardShortcuts'" diagnostics during the edit; resolved at xcodebuild time per the existing lesson on SourceKit transient noise.
- Sprite-engine path (`PoseRenderer`) untouched — its render dispatch is via `MascotView`, and the hero card just sets `size: 80` instead of `size: 64`. When the cat pack flag flips back on, the bigger sprite blits at 80pt automatically.

### Stage 3 — Settings polish (waiting on Stage 2 sign-off)
- `Label` + system-icon section headers
- Replace verbose paragraphs with help popovers (`?`)
- Decide single Form vs tabs

### Stage 2.5 — In-popover Settings + dark-launch overlay ✅ (2026-05-07)

User decided floating mascot is clutter (menu-bar icon already conveys mute), and Settings should live inside the popover so the separate Settings window goes away. Settings reduced to ~3 rows after dropping the mascot toggle, so a state-based page swap is enough — no `NavigationStack` chrome needed.

- [x] **`MewtFeatureFlags.overlayEnabled = false`** — new compile-time flag, mirrors `bundledPackEnabled` pattern. Off → `OverlayWindowController` is never installed; `OverlayWindow` + `OverlayWindowController` + `AppState.overlayVisible` stay compiled but dormant. Flip on to restore the panel.
- [x] **`MewtApp.swift`** — gate overlay install on the flag in `applicationDidFinishLaunching`. Stub the `Settings` scene to `EmptyView()` (kept so the App protocol has a Scene; nothing in-app calls `openSettings()` anymore). `SettingsView.swift` deleted earlier by the user — reference removed.
- [x] **`ContentView.swift`** — split into `MainPage` + `SettingsPage` with `@State Page` driving a switch. Settings button on `MainPage` flips `page = .settings` (preserves ⌘, shortcut). `SettingsPage` shows back-chevron header + 2 `KeyboardShortcuts.Recorder`s + info caption; ⎋ also returns. Asymmetric `.move(.leading)` / `.move(.trailing)` transitions give a subtle slide between pages, animated with `.smooth(0.22)`.
- [x] `xcodebuild build` + `xcodebuild test` green — 154/154 pass.

#### Review (2026-05-07)

- The popover's NSPopover is persistent (`TrayController` mounts the `NSHostingController` once at install) — `@State page` survives across show/hide of the popover, so reopening returns to whichever page the user left on. That's the intended behavior; if a "always reset to main on reopen" call is wanted later, wire it through `TrayController.popoverWillShow`.
- Kept `AppState.overlayVisible` + UserDefaults key alive (no churn) since `OverlayWindowController.observeVisibility` reads it and we wanted minimal blast radius. When `overlayEnabled` flips back on, the property + persistence work as before with no thaw cost.
- The `Settings { EmptyView() }` stub looks dead but is load-bearing: SwiftUI's `App.body` requires a Scene, and `.accessory` apps without one have surprising failure modes (no application menu, occasional `init` ordering issues). Cheap to keep.
- Stage 3 (Settings polish) becomes simpler now — there's no separate Settings window to redesign, just the in-popover `SettingsPage`. Help popovers / section headers can drop in there directly.

---

## Earlier work — Step back from cat assets: ship Symbol pack as default, dark-launch cat pack

User doesn't have real pixel art yet. Keep all of Phase 4 foundation engine work (156 tests) intact, but replace the user-visible default with a rasterized SF-Symbol pack. Cat pack stays in repo + binary but is gated behind a compile-time flag (no UI, no UserDefaults) — flip one constant when art lands.

Design choice locked in: **rasterize SF Symbols → NSImage** (drops into existing sprite engine, preserves all 156 tests). Revisit native `.symbolEffect` SwiftUI render path only if rasterized version isn't expressive enough.

- [x] **`MewtFeatureFlags.swift`** — single `enum MewtFeatureFlags { static let bundledPackEnabled = false }`. One-line comment explains it's intentionally off until pixel art is sourced.
- [x] **`SymbolPackSource.swift`** — new `PackSource` mirroring `SafePackSource` shape:
  - One pack id `com.chaninlaw.mewt.symbol`, tier `.free`, name "Mewt (symbols)"
  - Rasterizes 6 SF Symbols into one `NSImage` sprite sheet (6×64 wide, 64 tall, one frame per pose tag)
  - Mapping: idle/unmuted → `mic.fill`; muted → `mic.slash.fill`; talking → `waveform`; talkingWhileMuted → `exclamationmark.bubble.fill` (red); pushToTalk → `mic.fill` (accent)
  - `tintPolicy: .none` so engine doesn't desaturate (no-op on monochrome) or stack `EffectOverlay` (the icons already convey state)
  - All 6 `PoseTag`s in `poses` map, `loopMode: .freeze`, `fpsMultiplier: 1.0`
- [x] **Wire `AppState.makeProductionCatalog`** — always add `SymbolPackSource()`; conditionally add `BundledPackSource()` when flag is on. `defaultPackId` switches based on flag.
- [x] **Tests** (`MewtTests/SymbolPackSourceTests.swift`) — 9 tests, all green. 180/180 across the suite.
- [x] **Manual verification** — Symbol pack reads OK in app; user-confirmed 2026-05-06.

## Review (2026-05-06)

- Engine and 156 prior tests untouched; symbol pack drops in as a new `PackSource` implementation, total 180 tests passing.
- Rasterised symbols composited per-cell with `.destinationIn` masking scoped inside a per-symbol `NSImage` so cell tints can't bleed.
- `Mewt-Default.mewtpet` still ships in `Resources/` (it's part of the dormant cat work, kept for one-line flip when art lands). When `bundledPackEnabled = false`, `BundledPackSource` is never instantiated, so the folder is inert.
- One-line flip to re-enable cat pack: `MewtFeatureFlags.bundledPackEnabled = true`. Catalog logic re-promotes the cat pack to default; SymbolPackSource stays in the catalog as an alternative.
- If rasterised symbols don't read well in the menu bar / overlay, fall back position is the SwiftUI `.symbolEffect` render path discussed earlier — would need a `PoseRenderer` branch on `pack.id == SymbolPackSource.packId`.

## Backlog of original Phase 4 foundation closing-out (re-runs only when flag flips back on)

- Cycle 4 states against cat pack art
- Drop `talkingWhileMuted` row from `scripts/build_default_pack.py` `TAG_ORDER` and re-rasterise the cat pack (was a 2026-04-26 panic-read row, now unreferenced after the 2026-05-07 feature retirement)

---

## Deferred (waiting on usage data) — 2026-05-06

User wants to ship analytics + collect real signal before picking the next feature. The following are paused, not cancelled:

- **Phase 1 carry-over: ⌥Space PTT key consume** — needs `CGEventTap` + Accessibility permission. Justification gate: PTT hotkey usage is non-trivial in telemetry.
- **Phase 4 step 2: Plus tier (StoreKit + extra packs)** — spec ready (`docs/specs/2026-04-26-mewt-plus-tier-design.md`). Justification gate: enough installs + retention to suggest IAP appetite.
- **Phase 4 step 3: Studio tier (user-imported packs)** — spec ready (`docs/specs/2026-04-26-mewt-studio-tier-design.md`). Justification gate: Plus tier shipped + user requests for custom mascots.

## Next — Phase 4 step 2: Plus tier (StoreKit IAP + extra packs)

Spec: `docs/specs/2026-04-26-mewt-plus-tier-design.md`

Headline scope: StoreKit 2 entitlement, pack picker UI, 1+ bundled Plus packs, `pack.tier <= entitlement.tier` filter on `CharacterCatalog`. Engine + bundle pipeline are already foundation-ready — Plus drops in more `.mewtpet` folders and adds the picker.

## Then — Phase 4 step 3: Studio tier (user-imported packs)

Spec: `docs/specs/2026-04-26-mewt-studio-tier-design.md`

Headline scope: drag-drop import (`.mewtpet`, Aseprite export, APNG, GIF, single PNG), `UserPackSource` over App Support, atomic persistence, validation per §9 (including the new "frame side outside {16,32,64,128} → warn" rule referencing engine §4.6), `.mewtpet` export.

---

## Backlog / deferred

- **Distinct PTT art** — `pushToTalk` is aliased to `talking` frames in `scripts/build_default_pack.py` (`TAG_ALIASES`). Drop the alias and add a real PTT row to `TAG_ORDER` once unique animation is sourced.
- **⌥Space PTT key consume** (carry-over from Phase 1) — currently the keystroke still forwards to the focused app. Needs `CGEventTap` + Accessibility permission.
- **i18n `MicStatus.label`** — English only; deferred per engine spec §12.
- **@2x sprite variants** — explicitly skipped. Pixel art with `.interpolation(.none)` + integer-snap (engine §4.6) scales correctly without `@2x` PNGs.

## Reference

Specs:
- `docs/specs/2026-04-26-mascot-engine-design.md` — engine architecture, format contract, frame-size policy (§4.6)
- `docs/specs/2026-04-26-mascot-art-brief.md` — art deliverables for AI/pixel artist
- `docs/specs/2026-04-26-mewt-plus-tier-design.md`
- `docs/specs/2026-04-26-mewt-studio-tier-design.md`

Plans:
- `docs/plans/phase-1-global-hotkey.md`
- `docs/plans/phase-3-floating-overlay.md`

Lessons: `tasks/lessons.md`

Asset pipeline: `scripts/build_default_pack.py` (reads `assets/CatMascot/animations/` from PixelLab → emits `Mewt/Resources/Mewt-Default.mewtpet/`). Accepts `--src` / `--dest` to build alternate packs from other folders; defaults match the repo layout.
