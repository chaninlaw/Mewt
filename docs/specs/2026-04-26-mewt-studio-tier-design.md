# Mewt Studio Tier — Design Spec

- **Date:** 2026-04-26
- **Phase:** 4 step 3 (depends on Plus tier — see [`2026-04-26-mewt-plus-tier-design.md`](./2026-04-26-mewt-plus-tier-design.md))
- **Status:** Forward design — not yet active. Refined when this phase opens.

## 1. Goal

Ship the **Mewt Studio** tier: drag-drop import of custom character packs in multiple formats, pack management UI, and `.mewtpet` export for sharing. Studio is the "bring your own / share with friends" tier per [`MARKETING.md`](../../MARKETING.md).

The foundation engine and Plus tier already render any `.mewtpet` and gate access by `tier`. Studio's job is everything around the engine: ingestion from non-native formats, on-disk persistence outside the app bundle, validation, and an export round-trip. Like Plus, Studio is purely additive — it adds a new `PackSource` and new converters but does not refactor anything upstream.

## 2. Non-goals

- In-app pixel editor — separate, much-larger project.
- Cloud sync / iCloud Drive of imported packs.
- Public marketplace (may follow Studio if traction warrants).
- Modify or remix imported packs (read-only — user re-imports edited version).
- Animated GIF parsing edge cases (palette-with-alpha quirks etc.) — ship best-effort, document limits.
- Lottie / Rive / Spine import — vector animation is out of scope; pixel art only.

## 3. Pricing

**$9.99 one-time** per `MARKETING.md`. Non-consumable.

Studio entitlement is **additive but supersedes Plus** — owning Studio implicitly grants Plus access. The mechanic was designed into `EntitlementStore` in step 2: `isPlus = isPlusEntitled || isStudioEntitled`, and `tier == .studio` when Studio is owned. No additional refactor required this phase.

Family Sharing: enabled (consistent with Plus's policy).

## 4. Distribution / sandbox prerequisite

This phase assumes Mewt is **sandboxed**. The drag-drop import flow uses security-scoped bookmarks (§7) which require the App Sandbox entitlement; if Mewt ships unsandboxed via direct DMG, the bookmark dance is unnecessary and the import path simplifies.

> **Open: distribution channel decision.** This affects all three phases (foundation, Plus, Studio). Settle before foundation implementation. This spec proceeds on the **MAS / sandboxed** assumption.

## 5. Architecture

```
PackImportView (drag target — Settings)
        │
        ▼
FormatDetector ──▶ Converter (one per format) ──▶ CharacterPack + PackResources
                                                       │
                                                       ▼
                                            PackStorage (App Support dir)
                                                       │
                                                       ▼
                                UserPackSource (new PackSource — registered
                                with foundation's CharacterCatalog alongside
                                BundledPackSource)
```

Foundation's `CharacterCatalog` was designed to merge multiple `PackSource`s. Studio adds `UserPackSource` to the source list. New responsibilities are: format detection, conversion, atomic persistence, and validation. Catalog filtering and rendering are unchanged.

## 6. Multi-format ingest

`FormatDetector` inspects file extension + magic bytes:

| Source                        | Converter logic                                                                                 |
| ----------------------------- | ----------------------------------------------------------------------------------------------- |
| `.mewtpet` folder             | Validate manifest, copy to App Support                                                          |
| `.mewtpet.zip`                | Unzip, validate, copy                                                                           |
| Aseprite JSON + PNG (paired)  | Wrap into `.mewtpet` with synthesized `manifest.json` (name from JSON filename)                 |
| APNG (single file)            | Extract frames via `CGImageSource`. Generate `idle` covering all frames + synthesize `muted` (frame 0 frozen). Wrap. |
| GIF (single file)             | Same as APNG via `ImageIO` (lossy palette acceptable)                                           |
| Single PNG                    | Static frame → 1-frame `idle` pose; other tags fall through engine fallback chain               |

For 1-file formats (APNG/GIF/PNG), user is prompted via a sheet for `name` (mandatory) and `author` (optional). Other pose tags fall through to the engine's fallback chain — same UX as a designer who only authored `idle`.

> **Why APNG/GIF synthesize `muted` instead of letting it fall back:** the engine's fallback chain for `muted` is `→ idle` (animated). On a single-file import where `idle` covers all frames, that means the mascot keeps animating even when muted — which contradicts the "mute = sleeping" semantic. Synthesizing a frozen `muted` (frame 0) enforces the right visual contract. `talkingWhileMuted` and `pushToTalk` still fall through to `unmuted → idle`, which is fine: those states want motion.

## 7. Storage layout

```
~/Library/Application Support/com.chaninlaw.Mewt/
  packs/
    {uuid}/
      manifest.json
      sprite.png
      sprite.json
      [overrides.json]
      [preview.png]
```

UUID directory prevents name collisions. Imports stamp the manifest with:

- `tier: "studio"` — so the foundation catalog's tier filter (`pack.tier <= entitlement.tier`) gates imported packs uniformly with Plus packs. **No second filter mechanism for "imported vs bundled."**
- `importTimestamp` — ISO-8601 string, set at ingest.
- `sourceFormat` — one of `mewtpet`, `aseprite`, `apng`, `gif`, `png`. Drives the badge in the management UI.

All three keys were reserved in foundation's manifest schema; Studio just starts populating them.

Bundled packs continue to live in app bundle; this directory is for user-imported only.

App Sandbox path: file dropped → security-scoped bookmark obtained for the source URL → contents copied into App Support → bookmark released. Mewt owns the data after copy.

## 8. Pack management UI

Settings → "Mascot" section gains a new "Imported" subsection (only visible if `isStudio`):

- Drag-drop zone (large dotted outline) with hint text:
  > Drop a `.mewtpet`, Aseprite export, APNG, GIF, or PNG.
- List of imported packs:
  - Preview thumbnail.
  - Name.
  - Source format badge (read from manifest's `sourceFormat`).
  - "Export as .mewtpet" button → zip + reveal in Finder.
  - "Delete" button → confirm + remove directory.

Imported packs appear in the picker grid (Plus's `CharacterPickerView`) with a small "Custom" badge so the user can tell their imports from bundled packs. Catalog filtering (`tier: studio` + entitlement) governs visibility — no parallel filter logic in the picker.

## 9. Validation

| Rule                                            | Behavior                                                  |
| ----------------------------------------------- | --------------------------------------------------------- |
| Sprite sheet > 2048×2048 px                     | Reject with "Image too large"                              |
| Total pack size > 10 MB                         | Reject with "Pack too large"                               |
| Frame count > 64                                | Reject with "Too many frames"                              |
| `idle` tag missing in Aseprite JSON             | Auto-synthesize covering all frames; warn but accept       |
| Non-image MIME type masquerading                | `CGImageSource` fails → surfaced as "Unreadable image"     |
| Malformed JSON                                  | Surface line number + error from JSONDecoder               |
| `packSchemaVersion` unsupported                 | Reject with "Pack from newer Mewt — please update"         |
| Sprite sheet dimensions ≠ multiple of frame size | Warn but accept (nearest-neighbor renders OK)             |
| Frame side outside {16, 32, 64, 128}            | Warn ("mascot may look padded") but accept — engine integer-snaps per engine §4.6 |

Pack size limit is **10 MB** (raised from earlier 5 MB draft). Animation-heavy GIF imports often exceed 5 MB even after pre-processing; easier to relax up-front than tighten later (users hit limits and complain).

All error messages are user-facing; the underlying error is logged at `.error` priority in `com.chaninlaw.Mewt / MascotImport` for triage.

## 10. Sharing — `.mewtpet` export

Any pack (bundled or imported) can be exported via the picker's context menu:

1. Zip the `.mewtpet` directory into `~/Downloads/{name}.mewtpet.zip` (or use `NSSavePanel` for destination).
2. Reveal in Finder.
3. Recipient drag-drops onto Mewt → goes through the standard import path.

**Export is universal; ingest is gated.** Free and Plus users can export bundled packs (organic marketing per `MARKETING.md`); only Studio users can import received `.mewtpet.zip` files. This is intentional — sharing produces a virally-distributable artifact regardless of entitlement.

## 11. Entitlement gate

- Studio "Imported" subsection hidden in Settings UI if `!isStudio`.
- Drag-drop on the main window or Settings shows tooltip "Mewt Studio required" if `!isStudio`.
- All ingest code paths early-return if `!isStudio` — UI hide is convenience, not the security boundary.
- Already-imported packs from a previous Studio entitlement remain on disk if entitlement lapses, but `CharacterCatalog`'s tier filter hides them (they have `tier: studio`) until re-entitled. Graceful re-ramp on re-purchase.
- **Multi-file drop while `!isStudio`:** paywall sheet appears once for the batch, not per-file. Drop is queued behind the paywall; on purchase, the queue processes serially.

## 12. Error handling

| Failure                          | Behavior                                                       |
| -------------------------------- | -------------------------------------------------------------- |
| Drop unsupported file type       | Reject with "Unsupported format" + list of supported formats   |
| Aseprite JSON missing PNG pair   | Reject with "Drop both files together"                         |
| App Support write fails          | Retry once; if still fails, "Couldn't save — disk full?"       |
| Pack imports but fails to render | Roll back: delete directory, surface error                     |
| `idle` pose missing post-import  | Auto-synthesize from frame 0 of any present tag; warn          |
| User drops 20 files at once      | Process serially, surface a per-file result list                |
| Drop while `!isStudio`           | Show paywall sheet once per drop event (not per-file)          |

## 13. Testing strategy

| Layer                          | Test type | Notes                                                  |
| ------------------------------ | --------- | ------------------------------------------------------ |
| `FormatDetector`               | Unit      | Magic byte + extension matrix                           |
| Each format converter          | Unit      | Fixture files in `MewtTests/Fixtures/Imports/`         |
| APNG/GIF `muted` synthesis     | Unit      | Frame 0 frozen, other tags fall through to engine      |
| `PackStorage` (atomic copy)    | Unit      | UUID generation, rollback on failure                    |
| Validation rules               | Unit      | All limits boundary-tested                              |
| `EntitlementStore` Studio gate | Unit      | Studio implies Plus (`isPlus` + `tier == .studio`)     |
| `tier: studio` catalog filter  | Unit      | Imported packs hidden iff `!isStudio`                   |
| Multi-file drop paywall path   | Unit      | Single sheet, queued processing                         |
| Drag-drop end-to-end           | Manual    | All 6 source formats                                    |
| Export round-trip              | Unit      | Export → re-import → equal `CharacterPack`              |
| Multi-file drop                | Manual    | Drop 5 files of different types simultaneously          |

**Target:** ~25–35 new unit tests on top of the Plus suite.

## 14. Open questions

- iCloud Drive sync of imported packs: ignore now, but worth noting in product decision later.
- Per-pose import workflow: when user has multiple Aseprite files (one per pose), do we support a multi-step wizard or require pre-merging in Aseprite? — defer; ship single-file import first, evaluate.
- Should Studio expose a "create from PNG sequence" workflow (drop a folder of PNGs)? — adoption signal first.
- Bundled-pack export for free users: yes (decided in §10) — re-confirm with product owner.
- Distribution channel decision (MAS vs direct DMG vs both) — see §4.

## 15. Acceptance criteria (forward)

- [ ] All 6 source formats importable end-to-end.
- [ ] `UserPackSource` registered with foundation's `CharacterCatalog`.
- [ ] Imported packs persist across launches.
- [ ] Imported packs stamped with `tier: studio`, `importTimestamp`, and `sourceFormat` in `manifest.json`.
- [ ] Picker (Plus) shows imported packs alongside bundled, with "Custom" badge.
- [ ] APNG/GIF imports synthesize `muted` as frozen frame 0 (visual contract).
- [ ] Bad files rejected with user-clear errors; never silently corrupted.
- [ ] Export round-trips losslessly (`.mewtpet` → re-import → byte-equal sprite, equivalent manifest).
- [ ] Free + Plus users CAN export bundled packs (universal export, gated ingest).
- [ ] Studio gate enforced in UI + import code paths (defense in depth).
- [ ] App Sandbox compliant (no unauthorised reads outside dropped paths).
- [ ] StoreKit purchase + restore verified for `com.chaninlaw.Mewt.studio` product.
- [ ] Studio purchase grants Plus too (verified by selecting a Plus-tier bundled pet without owning Plus separately).
- [ ] Lapsed Studio user retains files on disk; picker hides them; re-purchase restores access.
- [ ] Multi-file drop while `!isStudio` shows paywall once for the batch, not per-file.
- [ ] Family Sharing confirmed enabled on the Studio product.
