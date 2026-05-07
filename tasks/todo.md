# Mewt — Task Log

## Now — Cat-themed Symbol pack + tray/Settings redesign (2026-05-06)

User accepted Symbol pack but wants the symbols to feel like **Mewt the cat app** + the popover/Settings copy refreshed to modern Apple style. Three stages — Stage 1 first, check in before Stage 2.

### Stage 1 — Cat-themed composite SF Symbols ✅
SF Symbols only ships 4 cat variants (`cat`, `cat.fill`, `cat.circle`, `cat.circle.fill`) — not enough for 5 unique states. Use composite pattern (Apple Mail/Messages badge style): `cat.fill` as identity + small state badge bottom-right.

- [x] Refactored `SymbolPackSource.symbolDescriptor` → main + optional badge + colors per state. Per-state badges: muted=zzz, talking=waveform, talkingWhileMuted=alarm triangle (red), pushToTalk=radio waves (accent), unmuted=none.
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

### Stage 2 — Tray popover redesign + copy (waiting on Stage 1 sign-off)
- Hero status card with `.contentTransition(.symbolEffect(.replace))` on mascot/badge
- Mute button: icon-bearing, color shifts on alarm state (red "I'm Muted!" when talkingWhileMuted)
- Hotkey hints + Input Level + TalkDetection collapsed to compact footer
- Copy fixes: "Talking (PTT)" → "Push-to-Talk", "Talk-while-muted Detection" → "Mute leak alarm"

### Stage 3 — Settings polish (waiting on Stage 2 sign-off)
- `Label` + system-icon section headers
- Replace verbose paragraphs with help popovers (`?`)
- Decide single Form vs tabs

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

- Cycle 5 states against cat pack art
- Refine PixelLab art (`talkingWhileMuted` panic read)
- Rerun `scripts/build_default_pack.py` after touch-ups

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
- **Talk-while-muted alarm on external USB mics** — some USB drivers apply volume scaling pre-tap stage; HAL mute silences the tap. Investigate Aggregate Device routing or `AVCaptureSession` path.
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
