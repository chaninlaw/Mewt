# Mewt Plus Tier — Design Spec

- **Date:** 2026-04-26
- **Phase:** 4 step 2 (depends on foundation engine — see [`2026-04-26-mascot-engine-design.md`](./2026-04-26-mascot-engine-design.md))
- **Status:** Forward design — not yet active. Refined when this phase opens.

## 1. Goal

Ship the paid **Mewt Plus** tier: StoreKit 2 entitlement, additional bundled animal pets (dog, bird, rabbit per [`MARKETING.md`](../../MARKETING.md)), character picker UI in Settings, and an upsell moment that converts free users.

Foundation already ships `CharacterCatalog` + `PackSource`, plus a manifest schema with a reserved `tier` field — this phase adds (a) more `.mewtpet` packs in the app bundle, (b) a paywall that gates them via `tier`, and (c) a UI for the user to choose which pet is active. **No foundation refactor required** — Plus is purely additive.

## 2. Non-goals

- User-imported characters — Step 3 (Studio).
- In-app pixel editor — much later.
- Public marketplace.
- Cross-device sync of selected pet (no server-side state at all).
- Multiple pets on screen at once.
- Per-pet sound effects, accessories — separate concerns; out of this spec.

## 3. Pricing

**Decision:** $4.99 one-time (non-consumable). Owner sign-off required before implementation.

Rationale: subscriptions are heavier ops (renewal, grace period, family sharing nuance, lapsed-state UI) and the LTV economics of a $4-5 one-time on a menu-bar utility likely beat fighting churn on a $5/yr sub. Equally important — Studio is a $9.99 one-time, so a Plus subscription would create a weird mixed-mode billing state when a Plus subscriber later buys Studio (the App Store doesn't auto-cancel one product when another is bought).

This decision overrides MARKETING.md's "$4.99/yr or $1.99 one-time" wording. **Action:** update MARKETING.md alongside the implementation PR for this phase.

## 4. Architecture

```
SettingsView ──▶ CharacterPickerView (new)
                       │
                       ▼
              CharacterCatalog (from foundation)
                       │
              ┌────────┴───────┐
              ▼                ▼
      BundledPackSource    EntitlementStore (new)
      (auto-discovers      (StoreKit 2 — drives tier filter)
       free + Plus
       .mewtpet folders)

selected pet → @AppStorage("selectedPetId")
```

Plus changes vs foundation:

1. **More packs.** Drop `Mewt-Dog.mewtpet`, `Mewt-Bird.mewtpet`, `Mewt-Rabbit.mewtpet` into `Resources/` as folder references. `BundledPackSource` discovers them automatically — no source-code change.
2. **Entitlement filter.** `CharacterCatalog`'s `currentPack()` resolution gains one step: filter visible packs by `pack.tier <= entitlement.tier`. Selected-but-locked pack falls back to the default cat. Stored `selectedPackId` is preserved (not cleared) so re-purchase restores selection.
3. **Selection.** New `@AppStorage("selectedPetId")` wired into `CharacterCatalog.selectedPackId`.

## 5. EntitlementStore

```swift
@MainActor
@Observable
final class EntitlementStore {
    private(set) var isPlusEntitled: Bool         // owns Plus product
    private(set) var isStudioEntitled: Bool       // owns Studio product (always false this phase; reserved)

    var isPlus: Bool { isPlusEntitled || isStudioEntitled }   // Studio implies Plus access
    var isStudio: Bool { isStudioEntitled }                   // for Studio phase

    /// Effective tier for catalog filter.
    var tier: PackTier {
        if isStudio { return .studio }
        if isPlus   { return .plus }
        return .free
    }

    func observeTransactions() async              // Transaction.updates loop
    func currentEntitlements() async              // hydrate from Transaction.currentEntitlements
    func purchase(productId: String) async throws -> Transaction
    func restore() async throws
}
```

The two-flag shape lands in this phase even though `isStudioEntitled` is always `false` until step 3 — this avoids refactoring consumer code (catalog filter, picker UI) when Studio ships. The `tier` derived property gives the catalog filter a single point of comparison.

`EntitlementStore` is injected into `CharacterCatalog` (or wrapped via a closure passed at init) so `currentPack()` can read `tier` synchronously. Tests use a `StubEntitlementStore` driven by manual flags.

## 6. StoreKit 2 surface

- One non-consumable product: `com.chaninlaw.Mewt.plus` ($4.99).
- `Transaction.updates` async stream observed from app launch → drives `EntitlementStore.isPlusEntitled`.
- "Restore Purchases" button in Settings (App Store policy requirement).
- No server validation — local `Transaction.currentEntitlements` is signed by StoreKit and trusted on-device.
- StoreKit Configuration file in Xcode project for sandbox testing.
- **Family Sharing:** enabled (default for non-consumables). Same policy will apply to Studio.

## 7. Bundled packs (Plus tier)

Per `MARKETING.md`: cat (free), dog, bird, rabbit (Plus). All in `.mewtpet` format from foundation, with `tier` set in `manifest.json`.

```
Mewt.app/Contents/Resources/
  Mewt-Default.mewtpet/       # tier: free   (ships in foundation)
  Mewt-Dog.mewtpet/           # tier: plus
  Mewt-Bird.mewtpet/          # tier: plus
  Mewt-Rabbit.mewtpet/        # tier: plus
```

Foundation already reserves `tier` in the manifest schema, so no parser change is needed — Plus simply emits `"tier": "plus"` in the new packs and the catalog's filter rule (single line: `pack.tier <= entitlement.tier`) gates them. All four packs continue to be discovered by `BundledPackSource` automatically.

Art delivery follows the same AI Designer agent workstream pattern as foundation. Each pack: sprite sheet + Aseprite JSON, 4 pose tags + `idle`, ~6 idle frames, ~300 KB on disk. **The PR for this phase is gated on AI Designer delivery for all 3 Plus packs.**

## 8. `selectedPetId` lifecycle

`@AppStorage("selectedPetId")` is introduced in this phase (foundation has no concept of selection — only one pack exists). `CharacterCatalog.selectedPackId` is a thin wrapper that reads/writes this key.

| Situation                                          | Behavior                                                                                            |
| -------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| First launch post-Plus-update                      | Defaults to `com.chaninlaw.mewt.default`. Written lazily on first picker interaction.               |
| Selected pack id no longer present in catalog      | Fall back to default. Don't overwrite the stored id (re-installing the pack restores selection).    |
| User selects Plus pack, then entitlement lapses    | `currentPack()` returns default. Stored id preserved — re-purchase restores selection.              |
| Restore on a fresh device                          | Entitlement returns; selected pet does NOT (UserDefaults isn't synced). User picks again.           |

The "stored id preserved across lapse" behavior is the key UX rule — don't clear it on lapse. Captured in tests.

## 9. Character picker UI

In Settings, replacing the existing static "Mascot" stub:

- 2-column grid of cells.
- Each cell:
  - 96 pt preview thumbnail (`preview.png` from pack).
  - Pet name below.
  - Lock icon overlay if `pack.tier > entitlement.tier`.
  - Accent-color check overlay on the active pet.
- Tap free cell (or owned Plus cell) → selects, persists to `@AppStorage("selectedPetId")`.
- Tap locked cell → presents paywall sheet in-flow with feature list and "Buy Mewt Plus — $4.99" button.

Live preview (animated `PoseRenderer` thumbnails) is a stretch goal — static `preview.png` is the baseline.

## 10. Upsell moment (per MARKETING.md)

> "Want me to dance to your voice? Try Mewt Plus"

**Mechanic:** when the user is unmuted and actively talking (debounced > 2 s) and has not been shown the upsell in the past 7 days:

- Show a tooltip near the mascot: 1.5 s fade-in, 4 s visible, 1 s fade-out.
- "Don't show again" link in tooltip → permanent suppression in `UserDefaults`.
- Throttle key: `lastUpsellShownAt` timestamp.
- Suppressed entirely if `isPlus` (which already includes Studio owners — no upsell to entitled users).

Lives in a small `UpsellController` observed by `OverlayContentView`. The throttle math is a pure value type → unit-testable.

> **Studio upsell:** deferred to step 3. The Plus → Studio upsell mechanic (e.g. surfacing import after N picker visits) is re-evaluated after Plus traction.

## 11. Error handling

| Failure                              | Behavior                                                                  |
| ------------------------------------ | ------------------------------------------------------------------------- |
| Product fetch fails (network down)   | Picker still shows packs; locked ones unbuyable, retry on next tap        |
| Purchase verification fails          | Show generic error, log details at `.error`, do not grant entitlement     |
| Subscription expired                 | N/A — Plus is one-time. Nothing to expire.                                |
| StoreKit unavailable in test env     | `EntitlementStore` injectable via DI; tests use `StubEntitlementStore`    |
| Pack file present but `tier` missing | Treat as `free` (foundation default — no change needed) and log at `.fault` |

## 12. Testing strategy

| Layer                       | Test type | Notes                                                                                       |
| --------------------------- | --------- | ------------------------------------------------------------------------------------------- |
| `EntitlementStore`          | Unit      | Stub StoreKit, verify state transitions on `Transaction` events; `tier` derivation correct  |
| Catalog tier filter         | Unit      | Plus packs visible iff `isPlus`; downgrade falls back to default; `selectedPackId` preserved |
| `selectedPetId` persistence | Unit      | `@AppStorage` round-trip, fallback when selected pet not found, preservation across entitlement lapse |
| `UpsellController`          | Unit      | Throttle math, suppression flag, debounce window                                            |
| Paywall buy → entitlement   | Manual    | Sandbox account, verify all 3 Plus pets unlock                                              |
| Restore Purchases           | Manual    | Sandbox account, verify on fresh install                                                    |
| Family Sharing eligibility  | Manual    | Verify shared family member sees Plus packs unlocked                                        |

**Target:** ~20–25 new unit tests on top of the foundation suite.

## 13. Open questions for implementation plan

- Picker preview: static `preview.png` or live `PoseRenderer` thumbnails? — ship static, evaluate live as polish.
- Paywall sheet location: inside Settings or top-level modal? — Settings, in-flow on lock-tap (decided).
- Free user trying to select a Plus pet → show paywall (decided) vs no-op? **Decision:** show paywall in-flow.
- Owner sign-off on $4.99 one-time pricing.

## 14. Acceptance criteria (forward)

- [ ] `EntitlementStore` exposes `isPlusEntitled`, `isStudioEntitled` (always false this phase), derived `isPlus` / `isStudio`, and `tier`.
- [ ] StoreKit Configuration file in Xcode project.
- [ ] Sandbox purchase + restore verified end-to-end.
- [ ] Catalog filter rule (`pack.tier <= entitlement.tier`) covered by tests.
- [ ] Picker shows correct lock state per entitlement.
- [ ] `selectedPackId` persists across launches AND across entitlement lapse + re-purchase.
- [ ] App handles offline gracefully (cached entitlement; no false locks).
- [ ] Upsell tooltip respects 7-day throttle and `isPlus` suppression.
- [ ] Free user sees default cat unconditionally.
- [ ] All 3 new bundled packs (dog, bird, rabbit) load + render correctly via `PoseRenderer`.
- [ ] AI Designer agent has delivered art for all 3 Plus packs at merge time.
- [ ] Family Sharing confirmed enabled on the Plus product.
- [ ] MARKETING.md updated to reflect $4.99 one-time pricing.
