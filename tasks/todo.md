# Mewt — Task Log

## Now — Phase 4 foundation: closing-out checks

The engine + Default cat pack ship; remaining work is manual verification before merge.

- [ ] Cycle all 5 `MicStatus` states in the running app:
  - [ ] `unmuted` → idle breathes (~6 fps loop, blinks once)
  - [ ] `muted` → calm breath ~3 fps + Z bobbing accent + desaturate tint
  - [ ] `talking` → speak animation while unmuted; speaking louder visibly speeds the loop; soft "mm" near threshold doesn't flicker (hysteresis)
  - [ ] `talkingWhileMuted` → wide-eyes alarm + red tint + bounce/shake
  - [ ] `pushToTalk` → currently shares `talking` frames (radial accent glow still applies); replace with distinct art when sourced
- [ ] Toggle System Settings → Accessibility → Reduce Motion → confirm frames freeze + overlay motion stops
- [ ] Idle CPU < 0.5% delta from baseline `f9a020c` (Instruments → Time Profiler attached to menu-bar process)
- [ ] (Optional) Refine PixelLab art — `talkingWhileMuted` could read more "panicked" (PixelLab inpaint or Aseprite touch-up); rerun `scripts/build_default_pack.py` after

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
