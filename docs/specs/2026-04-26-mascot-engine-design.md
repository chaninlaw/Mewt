# Mascot Engine — Design Spec

- **Date:** 2026-04-26
- **Phase:** 4 foundation (Step 1 of MVP ladder agreed in brainstorm)
- **Status:** Draft for user review

## 1. Goal

Refactor the mascot rendering layer so the built-in cat — and any future paid character — runs through a single asset-driven engine. After this phase ships, the visible behavior of the free mascot is unchanged; what changes is that the cat is described by data on disk (a `.mewtpet` bundle) instead of hand-coded SwiftUI shapes.

This is **foundation only.** No IAP, no character picker UI, no import, no editor. The point of doing this work now (before Phase 4 step 2) is so that adding paid pets, drag-drop import, or a marketplace later does not require rewriting the rendering layer a second time.

Inspiration: [Runcat](https://kyome.io/runcat/) — macOS menu-bar app where a cat animates at a speed proportional to CPU load. We adopt the same shape (sprite sheet + variable frame rate) but driven by mic amplitude instead of CPU.

## 2. Non-goals (explicit)

These are out of scope for this spec and will be separate work:

- StoreKit 2 paywall — Phase 4 step 2.
- Character picker / settings UI for choosing pets — step 2.
- Drag-drop import of external `.mewtpet` / Aseprite / APNG / GIF — step 3.
- In-app pixel editor — much later.
- Per-layer mouth-sync animation — explicitly rejected during brainstorm.
- Marketplace / character sharing — much later.
- Multiple packs loaded concurrently — single-pack runtime is enough for foundation.

## 3. Architecture

### 3.1 Module map

```
[ existing — unchanged ]
MicStatus  ──▶  AppState
                  │
                  └── inputLevel: Float (already populated)

[ new — added in this phase ]
                  │
                  ▼
          CharacterCatalog                     ◀── PackSource(s)
                  │                                 (BundledPackSource only this phase;
                  │                                  Plus / Studio plug in more)
                  ▼
          PoseRenderer (SwiftUI view)
                  │
                  ▼
        CharacterPack (Sendable value type — manifest + sprite metadata)
        PackResources (@MainActor — decoded NSImage)
                  │
        ┌─────────┴─────────┐
        ▼                   ▼
CharacterLoader        EffectOverlay
(parses .mewtpet)     (Z, alarm, tint — programmatic)
```

### 3.2 Data flow

1. `AppState` already produces `MicStatus` and `inputLevel` (RMS, `Float`). New: `smoothedAmplitude: Double` derived value (see §8).
2. `AppState` owns a `CharacterCatalog`. The catalog merges packs from one or more `PackSource`s. In this phase the only source is `BundledPackSource`, which auto-discovers `.mewtpet` folders in `Resources/` (only `Mewt-Default.mewtpet` is shipped) — Plus drops in more pack folders, Studio adds a `UserPackSource`. `AppState`'s contract does not change in either downstream phase.
3. `PoseRenderer` is a SwiftUI view that takes `(MicStatus, smoothedAmplitude, currentPack, packResources)` and emits the current sprite frame plus programmatic overlays.
4. `CharacterPack` is an immutable `Sendable` value type loaded once per pack. `PackResources` (a `@MainActor` reference type) holds the decoded `NSImage`. Splitting them keeps `CharacterPack` Codable + actor-portable while the GUI-bound image stays main-actor-pinned (see §5.1).

### 3.3 What gets removed

- `Mewt/Mascot/MascotFace.swift` — replaced by `PoseRenderer`.
- The `CatHead`, `Triangle`, `EyesView`, `MouthView`, `Smile`, `AccentView` private types inside it.
- `Mewt/Mascot/MascotPose.swift` and `MewtTests/MascotPoseTests.swift` (60 tests) — superseded. The eyes/mouth/accent struct described pre-asset rendering and has no role once frames come from a sprite sheet. Replaced by a small `MicStatus → PoseTag` mapping with ~5 tests (§5.4).

The accessibility label that used to live on `MascotPose.accessibilityLabel` migrates to `MicStatus.label` (already covered by `MicStatusTests`); `OverlayContentView` already uses `MicStatus.label` for its label string, so no view-side change is needed.

## 4. `.mewtpet` format

A folder bundle. (A zipped form may come later when import lands; folder is enough for the bundled built-in pack.)

```
Mewt-Default.mewtpet/
  manifest.json         # see §4.1
  sprite.png            # sprite sheet (Aseprite-compatible layout)
  sprite.json           # Aseprite JSON export
  overrides.json        # Mewt-specific extras (optional)
  preview.png           # 128×128 thumbnail (reserved for future picker)
```

> **Why `manifest.json` and not `Info.plist`:** macOS treats folders containing `Info.plist` as bundle-shaped artifacts (apps, frameworks, plugins). Using a different name avoids Finder mistaking a `.mewtpet` for an app/framework bundle when users share exported packs in step 3, and pairs naturally with the sibling `sprite.json`.

### 4.1 `manifest.json` schema

```json
{
  "packSchemaVersion": 1,
  "id": "com.chaninlaw.mewt.default",
  "name": "Mewt",
  "author": "Mewt",
  "version": "1.0.0",
  "license": "proprietary",
  "tier": "free"
}
```

| Field               | Required | Notes                                                                                       |
| ------------------- | -------- | ------------------------------------------------------------------------------------------- |
| `packSchemaVersion` | yes      | `1` for this release. Unknown values throw `unsupportedSchemaVersion`.                      |
| `id`                | yes      | Reverse-DNS, lowercased. Bundled packs use `com.chaninlaw.mewt.<slug>`.                     |
| `name`              | yes      | Human-readable; localized later.                                                            |
| `author`            | yes      |                                                                                             |
| `version`           | yes      | Semver string.                                                                              |
| `license`           | yes      | Free-form.                                                                                  |
| `tier`              | no       | `free` (default), `plus`, `studio`. Reserved here so Plus/Studio don't have to bump schema. |

**Reserved (forward-compat) keys** the foundation parser preserves into `CharacterPack.extras` but does not interpret:

| Field             | Used by | Purpose                                                |
| ----------------- | ------- | ------------------------------------------------------ |
| `importTimestamp` | Studio  | Set on user-imported packs at ingest time.             |
| `sourceFormat`    | Studio  | `mewtpet`, `aseprite`, `apng`, `gif`, `png`.           |

Unknown manifest keys are read into `CharacterPack.extras` (a side `[String: AnyCodableValue]`) and ignored by the renderer. Rationale: lets Plus and Studio stamp metadata into manifests without touching the foundation parser. `packSchemaVersion` only bumps for *breaking* changes; additive keys are free.

### 4.2 Why Aseprite-compatible

Aseprite's JSON exporter is the de-facto standard for pixel art. By reading its format directly, any pixel artist can author a Mewt pet using their existing tool with zero new learning. Tools like [LibreSprite](https://libresprite.github.io/) (free fork) and many GIF→Aseprite converters output the same shape.

### 4.3 `sprite.json` — fields we consume

```json
{
  "frames": [
    { "frame": { "x": 0,  "y": 0, "w": 32, "h": 32 }, "duration": 100 },
    { "frame": { "x": 32, "y": 0, "w": 32, "h": 32 }, "duration": 100 }
  ],
  "meta": {
    "frameTags": [
      { "name": "idle",              "from": 0, "to": 5,  "direction": "forward" },
      { "name": "muted",             "from": 6, "to": 6,  "direction": "forward" },
      { "name": "talkingWhileMuted", "from": 7, "to": 10, "direction": "forward" },
      { "name": "pushToTalk",        "from": 11,"to": 14, "direction": "forward" }
    ]
  }
}
```

Other Aseprite fields (slices, layers, palette) are ignored.

Tag names map 1:1 to `MicStatus` cases plus the synthetic `idle` tag. Only `idle` is mandatory.

#### Aseprite `direction` → `LoopMode`

Part of the format contract — Studio's APNG/GIF converters need to round-trip these values when wrapping single-file imports into a `.mewtpet`.

| Aseprite `direction`  | Engine `LoopMode`     |
| --------------------- | --------------------- |
| `forward`             | `.forward`            |
| `reverse`             | `.reverse`            |
| `pingpong`            | `.pingPong`           |
| `pingpong_reverse`    | `.pingPongReverse`    |

`.freeze` is an engine-only mode used when `fps == 0` at runtime; it is not produced by the loader.

### 4.4 `overrides.json` — optional Mewt extras

```json
{
  "schemaVersion": 1,
  "anchors": {
    "accentTopRight":  { "x": 0.78, "y": 0.18 },
    "accentBottomLeft":{ "x": 0.22, "y": 0.82 },
    "glowCenter":      { "x": 0.50, "y": 0.55 }
  },
  "frameRate": {
    "amplitudeToFps": [
      { "amp": 0.0,  "fps": 0  },
      { "amp": 0.05, "fps": 4  },
      { "amp": 0.30, "fps": 12 },
      { "amp": 0.60, "fps": 18 }
    ]
  },
  "perPoseFpsMultiplier": {
    "pushToTalk": 1.5
  },
  "tintPolicy": "auto"
}
```

| Key                        | Type   | Default    | Notes                                                                                       |
| -------------------------- | ------ | ---------- | ------------------------------------------------------------------------------------------- |
| `schemaVersion`            | int    | `1`        | Distinct from manifest's `packSchemaVersion`. Bumps independently.                          |
| `anchors.accentTopRight`   | point  | (built-in) | Normalized 0…1 inside sprite frame. Anchor for muted `Z` and alarm symbol.                  |
| `anchors.accentBottomLeft` | point  | (built-in) | Reserved alternate accent slot.                                                             |
| `anchors.glowCenter`       | point  | (built-in) | Anchor for the `pushToTalk` radial glow.                                                    |
| `frameRate.amplitudeToFps` | curve  | (built-in) | Piecewise-linear; samples below first knee clamp to `0`, above last knee clamp to last fps. |
| `perPoseFpsMultiplier.*`   | float  | `1.0`      | Per-`PoseTag` multiplier applied to the curve output.                                       |
| `tintPolicy`               | enum   | `auto`     | `auto` = engine applies built-in tints (§6); `none` = pack opts out and renders sprite as-is. |

All keys optional; engine has built-in defaults. Unknown keys are ignored. Forward-incompatible changes bump `schemaVersion` (independent from `packSchemaVersion`).

### 4.5 Pose fallback chain

If a tag is missing, the renderer resolves it as:

| Requested pose      | Fallback chain                                                  |
| ------------------- | --------------------------------------------------------------- |
| `talking`           | → `unmuted` → `idle`                                            |
| `talkingWhileMuted` | → `unmuted` → `idle`                                            |
| `pushToTalk`        | → `unmuted` → `idle`                                            |
| `muted`             | → single frame from `idle` with `loopMode == .freeze`           |
| `unmuted`           | → `idle`                                                        |

`idle` is mandatory. Loading throws `CharacterLoaderError.missingIdlePose` if absent.

> **Note on `talkingWhileMuted`:** the chain skips `muted` deliberately. The alarm state means the user is *actively* talking — falling back to a frozen muted frame would visually contradict that, even with the red-tint overlay applied. `unmuted` (animated) preserves the talking sense; the alarm overlay (§6) carries the urgency.

### 4.6 Frame size policy

`PoseRenderer.size` is the layout box the mascot fills (default `64`). Source frames are scaled to fit that box at an **integer ratio** with nearest-neighbor sampling. Pixel art looks bad at fractional scales — a 1.39× upscale turns 1 source pixel into a smeared 1.39-pixel block. Snapping to the nearest integer ratio keeps every source pixel a discrete square on screen.

#### Scale rule

For frame side `f` and display side `d`:

| Case      | Scale                             | Rendered size      |
| --------- | --------------------------------- | ------------------ |
| `f ≤ d`   | `max(1, floor(d / f))`            | `f × scale ≤ d`    |
| `f > d`   | `1 / max(1, ceil(f / d))`         | `f × scale ≤ d`    |

The rendered sprite is **centered** in the `d × d` box; leftover space is transparent. The whole sheet is offset so the active frame lands at the center — keeps `SpriteFrameView` a one-pass render with no crop+composite step.

Examples at default `displaySize = 64`:

| Frame side `f` | Scale | Rendered | Notes                                        |
| -------------- | ----- | -------- | -------------------------------------------- |
| 16             | 4×    | 64       | optimal — fills box                          |
| 24             | 2×    | 48       | accepted, smaller than box                   |
| 32             | 2×    | 64       | optimal (Default pack legacy size)           |
| 48             | 1×    | 48       | accepted, smaller                            |
| 64             | 1×    | 64       | optimal (Default pack current size)          |
| 92             | 1/2×  | 46       | accepted, smaller                            |
| 96             | 1/2×  | 48       | accepted, smaller                            |
| 128            | 1/2×  | 64       | optimal — downscale loses 75% of source pixels |

#### Recommended frame sizes

Authors targeting Mewt's 64pt display should pick a side from **{16, 32, 64, 128}** — these scale to a full 64×64 render at integer ratios. **{24, 48, 96}** are accepted but render smaller than the box (mascot looks padded inside the layout). Anything else is accepted and integer-snapped, but will rarely fill the box cleanly.

#### Per-frame size variation

A pack's frames should share one side length across the whole sheet. The renderer will scale each frame independently per its own `rect.width`, so cross-frame variation produces visible mascot-size jumps on pose change. Within a single tag, `rect.width` must be uniform (loader does not enforce, but rendering is undefined if not).

#### Sheet-level limits

Sheet pixel dimensions and per-pack frame counts are capped only at Studio import time (§9 of the Studio spec — sheet ≤ 2048×2048, frames ≤ 64). Bundled and Plus packs ship pre-vetted and skip those checks.

## 5. Public API surface

### 5.1 `CharacterPack` + `PackResources` (concurrency model)

```swift
struct CharacterPack: Equatable, Sendable, Codable {
    let id: String
    let name: String
    let author: String
    let version: String
    let tier: PackTier                              // .free / .plus / .studio
    let frames: [SpriteFrame]                       // ordered, indexed
    let poses: [PoseTag: PoseAnimation]             // resolved (fallbacks applied at load time)
    let overrides: PackOverrides
    let extras: [String: AnyCodableValue]           // unknown manifest keys preserved
}

struct SpriteFrame: Equatable, Sendable, Codable {
    let rect: CGRect
    let duration: TimeInterval                      // ms in source, seconds here
}

struct PoseAnimation: Equatable, Sendable, Codable {
    let frameRange: Range<Int>                      // indices into CharacterPack.frames
    let loopMode: LoopMode                          // .forward / .reverse / .pingPong / .pingPongReverse / .freeze
    let fpsMultiplier: Double                       // resolved from overrides; defaults to 1.0
}

enum PoseTag: String, Equatable, Sendable, Codable, CaseIterable {
    case idle, muted, unmuted, talking, talkingWhileMuted, pushToTalk
}

enum PackTier: String, Equatable, Sendable, Codable, Comparable {
    case free, plus, studio
    // Comparable so the catalog filter can write `pack.tier <= entitlement.tier`.
}

@MainActor
final class PackResources {
    let packId: String
    let spriteImage: NSImage          // decoded once on the main actor
    init(packId: String, spriteImage: NSImage)
}
```

**Why two types.** `NSImage` is not `Sendable`, and `CharacterPack` will cross actor boundaries (StoreKit observers in the Plus phase, fixture caches, tests). Holding the decoded image on a separate `@MainActor` reference lets us:

- Pass `CharacterPack` freely between actors as a value.
- Decode the image on the main actor where SwiftUI draws it anyway.
- Test `CharacterPack` / `CharacterLoader` without spinning up `NSImage` — the loader returns raw PNG `Data`, and a separate `MainActor` factory builds `PackResources`.

`poses` is keyed by **all** `PoseTag` values — fallback chain is resolved at load time so the renderer never has to handle a missing pose at runtime. This keeps the renderer a pure function of `(status, amplitude, t)`.

### 5.2 `PoseRenderer` (SwiftUI view)

```swift
struct PoseRenderer: View {
    let status: MicStatus
    let amplitude: Double           // 0...1 — pass appState.smoothedAmplitude
    let pack: CharacterPack
    let resources: PackResources
    var size: CGFloat = 64

    var body: some View { ... }
}
```

Internally:

- Maps `MicStatus → PoseTag` via `PoseTagMapping.tag(for:)` — replaces the old `MascotPose.from`.
- Uses `TimelineView(.animation)` to drive frame selection, falling back to `.explicit` (single date) when `FrameSelector` reports `fps == 0`, so a frozen pose doesn't burn display ticks.
- Renders the sprite via `Image(nsImage: resources.spriteImage)` cropped to the current frame's `rect`, with `.interpolation(.none)` so pixel art stays crisp at any size.
- Wraps a `ZStack` for programmatic overlays (§6).

Reduce-Motion respected: when `accessibilityReduceMotion` is on, frames freeze at `frameRange.lowerBound` and overlay shake/pulse is disabled.

### 5.3 `CharacterLoader`

```swift
enum CharacterLoaderError: Error, Equatable {
    case bundleNotFound(URL)
    case invalidManifest(reason: String)
    case missingIdlePose
    case spriteImageUnreadable
    case unsupportedSchemaVersion(Int)
}

struct LoadedPack {
    let pack: CharacterPack
    let imagePNGData: Data         // raw PNG bytes; main-actor caller decodes into NSImage
}

enum CharacterLoader {
    static func load(bundleURL: URL) throws -> LoadedPack
    static func loadBuiltin() throws -> LoadedPack
}
```

Pure file → value transform. No SwiftUI / `NSImage` dependency, fully unit-testable with fixture bundles in `MewtTests/Fixtures/`.

### 5.4 Frame selection (pure functions, testable separately)

```swift
enum PoseTagMapping {
    /// Pure mapping from logical mic status to which sprite tag to render.
    static func tag(for status: MicStatus) -> PoseTag {
        switch status {
        case .unmuted:           return .unmuted
        case .muted:             return .muted
        case .talking:           return .talking
        case .talkingWhileMuted: return .talkingWhileMuted
        case .pushToTalk:        return .pushToTalk
        }
    }
}

// MicStatus.talking is derived in AppState by an `AmplitudeGate`
// (hysteresis on `smoothedAmplitude`) and is independent of the VAD
// `isSpeechDetected`. The gate is the friendly visual cue; the VAD
// remains dedicated to the talkingWhileMuted alarm condition.
//
// The build pipeline can emit two frame tags at the same range — used
// today so `pushToTalk` shares `talking` frames until distinct PTT art
// is sourced. The loader keys on tag name, so each pose still resolves
// to its own `PoseAnimation` entry independently.

enum FrameSelector {
    /// Returns the index into `pack.frames` to display at time `t` for a given pose.
    static func index(
        at t: TimeInterval,
        pose: PoseTag,
        amplitude: Double,
        pack: CharacterPack
    ) -> Int
}
```

Algorithm:

1. Look up `animation = pack.poses[pose]!` (always present after load-time fallback resolution).
2. If `animation.loopMode == .freeze` → return `animation.frameRange.lowerBound`. The loader stamps `.freeze` on a synthesized single-frame `muted` fallback when the pack omits a `muted` tag, so packs that intend "muted is still" get freeze for free; packs that ship a multi-frame `muted` range (e.g., a slow calm-breath loop) animate per `loopMode` like any other pose.
3. Compute `fps = piecewiseLinear(amplitude, pack.overrides.amplitudeToFps) * animation.fpsMultiplier`.
4. If `fps == 0` → return `animation.frameRange.lowerBound` (frozen; renderer also drops `TimelineView` to `.explicit`).
5. Else: walk `animation.frameRange` according to `animation.loopMode` (`.forward` / `.reverse` / `.pingPong` / `.pingPongReverse`) using `Int(t * fps)` as the step counter.

Both functions are pure; the renderer just calls them inside `TimelineView`'s `Context.date`-driven body.

### 5.5 `CharacterCatalog` and `PackSource`

```swift
protocol PackSource: Sendable {
    func packs() -> [CharacterPack]                       // metadata only
    @MainActor func resources(for packId: String) -> PackResources?
}

@MainActor
@Observable
final class CharacterCatalog {
    init(sources: [any PackSource], defaultPackId: String)

    func allPacks() -> [CharacterPack]
    func currentPack() -> CharacterPack                   // honors selection (+ entitlement in Plus)
    func currentResources() -> PackResources

    var selectedPackId: String { get set }                // backed by @AppStorage in AppState wrapper
}

struct BundledPackSource: PackSource {
    /// Auto-discovers all `.mewtpet` folder bundles in `Bundle.main.resourceURL`.
    /// In foundation phase only `Mewt-Default.mewtpet` is shipped; Plus drops in
    /// more pack folders without touching this type.
    init() throws
    func packs() -> [CharacterPack]
    @MainActor func resources(for packId: String) -> PackResources?
}
```

This abstraction exists in foundation **even though only one source / one pack ships** because Plus (entitlement-gated bundled packs) and Studio (user-imported packs) extend it as additive sources rather than refactoring `AppState`. Ship the indirection now to avoid revisiting `AppState`'s pack contract twice.

`currentPack()` resolution rule (foundation):

1. If `selectedPackId` resolves to a pack present in any source → return it.
2. Else → return the pack at `defaultPackId`.
3. Loader-failure / missing-pack safe fallback (§9) is one rung below: returns the safe procedural pack.

Plus extends step 1 with an entitlement filter (`pack.tier <= entitlement.tier`); Studio adds a `UserPackSource` to the source list. Neither phase changes this signature.

## 6. Effect overlays (programmatic)

Drawn on top of the sprite. They exist so a pack with only `idle` still produces visibly different states — paid users can ship 1 pose and Mewt fills in the variation.

Applied **only when `overrides.tintPolicy == .auto`**; packs that opt out (`tintPolicy: "none"`) render the raw sprite.

| Pose                | Overlay                                                                                                                             |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `unmuted`           | none                                                                                                                                |
| `muted`             | desaturate sprite by 30% + small `Z` SF Symbol bobbing at `anchors.accentTopRight` (pulse)                                          |
| `talkingWhileMuted` | red tint 20% + `keyframeAnimator` rotation shake (±6°, 0.4s) + `exclamationmark.triangle.fill` symbol with `.symbolEffect(.bounce)` |
| `pushToTalk`        | radial accent-color glow at `anchors.glowCenter` + `perPoseFpsMultiplier.pushToTalk` applied to the curve (default 1.5×)            |

All overlays use `Image(systemName:)` + `.symbolEffect` (macOS 14+) so they're free from the system. Anchor points come from `overrides.json`; defaults match the cat's geometry.

Overlays are gated on `@Environment(\.accessibilityReduceMotion)` — disabled when on.

## 7. Built-in mascot migration

### 7.1 Bundled artifact

Ship `Mewt-Default.mewtpet` in `Mewt.app/Contents/Resources/Mewt-Default.mewtpet/` containing:

| Tag                 | Frames | Notes                                       |
| ------------------- | ------ | ------------------------------------------- |
| `idle`              | 6      | gentle blink + breathe loop, ~600ms total   |
| `muted`             | 1      | eyes closed, mouth zipped (frozen)          |
| `talkingWhileMuted` | 4      | wide-eyed, mouth open, faster cycle         |
| `pushToTalk`        | 4      | open-mouth talking loop                     |

> **Xcode build setup:** add `Mewt-Default.mewtpet` to the Mewt target as a **folder reference** (blue icon), not a group (yellow). Folder references copy the directory verbatim into `Resources/`; groups flatten contents and break the `.mewtpet` layout. Same rule applies to all `.mewtpet` packs added in Plus.

### 7.2 Art sourcing

Sprite sheet production for `Mewt-Default.mewtpet` is delegated to an **AI Designer agent** in a parallel workstream. Engineering and art proceed on independent tracks but ship together — the foundation PR does not merge without production art.

The art brief is fully specified by §4 (sprite sheet + Aseprite JSON contract) and §7.1 (frame count per tag, idle loop ~600 ms). The AI Designer agent works to that brief on its own; engineering proceeds in the meantime against fixture packs (test stubs in `MewtTests/Fixtures/`) for unit and visual-regression coverage. Fixtures are not user-facing and are not shipped.

No SwiftUI-shape-rendered placeholder. The whole point of this refactor is to raise visual quality past what hand-coded primitives produce — shipping a stub that matches the current look would defeat the goal. Engineering blocks on art for the merge, not for development.

### 7.3 `OverlayContentView` change

```swift
// Before
MascotFace(pose: .from(appState.status), size: 64)

// After
PoseRenderer(
    status: appState.status,
    amplitude: appState.smoothedAmplitude,
    pack: appState.catalog.currentPack(),
    resources: appState.catalog.currentResources(),
    size: 64
)
```

`appState.catalog` is constructed once in `AppState.init()` from `BundledPackSource()`. If the bundled source's `init` throws, `AppState` falls back to a hand-built safe catalog (a `SafePackSource` that emits a single colored-circle pack drawn at runtime) so the app still launches. The `.fault`-priority log makes the failure visible in Console.

## 8. AppState integration

Three additions to `AppState`:

1. `let catalog: CharacterCatalog` — constructed once in `init`, immutable reference.
2. `var smoothedAmplitude: Double` — derived from `inputLevel` via a 100ms exponential moving average. Lives in `AppState` so `PoseRenderer` stays presentational. Updated inside `levelMonitor.onLevelUpdate`.
3. Designated init grows one parameter:

```swift
init(
    muteController: any MicMuteControlling,
    levelMonitor: any AudioLevelMonitoring,
    hotkeys: any HotkeyProviding,
    catalog: CharacterCatalog,                       // new
    defaults: UserDefaults = .standard
)
```

Convenience init builds the production catalog:

```swift
let bundled = (try? BundledPackSource()) ?? SafePackSource()
self.init(
    muteController: ...,
    levelMonitor: ...,
    hotkeys: ...,
    catalog: CharacterCatalog(sources: [bundled], defaultPackId: "com.chaninlaw.mewt.default"),
    defaults: .standard
)
```

Tests pass a stub catalog built from a fixture pack. No new audio capture path. No new permissions. The existing 83-test suite is unaffected by the catalog injection — they construct their `AppState` via the designated init already.

## 9. Error handling

| Failure                                | Behavior                                                                                                                  |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| Built-in `.mewtpet` corrupted          | App still launches; `CharacterCatalog` falls back to procedural `SafePackSource` (single colored circle + status label). Logged at `.fault` priority. |
| `idle` pose missing in manifest        | `CharacterLoader.load` throws `missingIdlePose`. Built-in pack guaranteed valid by build-time fixture test.               |
| Sprite PNG fails to decode             | Throw `spriteImageUnreadable`. Same fallback as above.                                                                    |
| Pose tag missing                       | Resolved silently via fallback chain at load time.                                                                        |
| `overrides.json` missing or invalid    | Use built-in defaults. Log at `.info`.                                                                                    |
| Unknown manifest `packSchemaVersion`   | Throw `unsupportedSchemaVersion(n)`. Future-proofs the format.                                                            |
| Unknown `overrides.json schemaVersion` | Throw `unsupportedSchemaVersion(n)`.                                                                                      |
| Unknown manifest keys (additive)       | Preserved into `CharacterPack.extras`; ignored by renderer. No error.                                                     |

## 10. Testing strategy

| Layer                               | Test type      | Notes                                                                               |
| ----------------------------------- | -------------- | ----------------------------------------------------------------------------------- |
| `CharacterPack` Codable             | Unit           | Round-trip JSON, including `extras` preservation                                    |
| `CharacterLoader` happy + sad paths | Unit           | Fixture `.mewtpet` directories under `MewtTests/Fixtures/`                          |
| Pose fallback resolution            | Unit           | All 4 fallback chains, including `talkingWhileMuted` skipping `muted`               |
| `PoseTagMapping.tag(for:)`          | Unit           | All 4 `MicStatus` cases (replaces `MascotPoseTests`)                                |
| `FrameSelector.index`               | Unit           | Boundary (t=0, large t), wraps cleanly, `muted` always returns range's `lowerBound`, all 4 `LoopMode`s |
| Amplitude → fps curve               | Unit           | Monotonic, clamped past last knee, all knees correct                                |
| Per-pose fps multiplier             | Unit           | `pushToTalk` 1.5×, default 1.0× for unset poses                                     |
| Smoothed amplitude EMA              | Unit           | Spike attenuation, decay timing                                                     |
| `CharacterCatalog.currentPack`      | Unit           | Selection resolves; missing id falls back to default                                |
| `BundledPackSource` discovery       | Unit (fixture) | Discovers all `.mewtpet` folders in a fixture Resources dir                         |
| Built-in pack validity              | Unit (fixture) | Loads in CI, has all 4 pose tags, has `idle`                                        |
| `MicStatus` mapping (existing)      | Existing       | Untouched (`MicStatusTests`)                                                        |
| Visual regression                   | Manual         | Run app, exercise all 4 `MicStatus` states, verify parity                           |

**Net test count change:** `MascotPoseTests` (60 tests) is removed; ~25–30 new unit tests are added (loader, catalog, frame selector, fallback, mapping, EMA, source discovery). Final suite count drops from 83 → ~50–55, but coverage shifts from struct-level mapping to load + render contract — a more useful surface.

## 11. Performance budget

| Scenario                    | Target                                                                                                  |
| --------------------------- | ------------------------------------------------------------------------------------------------------- |
| Idle (silent, `muted`)      | ≤ 0.1% CPU. `TimelineView` drops to `.explicit` when `fps == 0` so the body re-evaluates at most on state change. |
| Active talking              | < 1% CPU at 64pt window (parity with current)                                                           |
| Memory per pack             | 200-500 KB (1 sprite sheet + decoded `NSImage`)                                                         |
| App bundle size delta       | ~300 KB (built-in pack)                                                                                 |
| Pack load time at launch    | < 30 ms (single PNG decode + small JSON parse)                                                          |

We measure CPU before/after with Instruments Time Profiler attached to the menu-bar process. Regressions over 0.5% are blockers.

## 12. Acceptance criteria

- [ ] `CharacterPack`, `PoseAnimation`, `SpriteFrame`, `PoseTag`, `PackTier`, `PackOverrides`, `PackResources` exist and compile.
- [ ] `CharacterLoader.load(bundleURL:)` and `loadBuiltin()` work end-to-end with fixture and real built-in pack.
- [ ] `manifest.json` parser preserves unknown keys into `extras` and round-trips via `Codable`.
- [ ] `FrameSelector.index(at:pose:amplitude:pack:)` is pure, tested, and used by `PoseRenderer`. All 4 `LoopMode`s covered.
- [ ] `PoseTagMapping.tag(for:)` is pure, tested, and used by `PoseRenderer`.
- [ ] `CharacterCatalog` + `BundledPackSource` exist and are wired into `AppState`. `BundledPackSource` auto-discovers all `.mewtpet` folders in `Resources/`.
- [ ] `PoseRenderer` renders sprite + overlays for all 4 `MicStatus` states, honoring `tintPolicy`.
- [ ] `Mewt-Default.mewtpet` ships in app bundle as a folder reference, with all 4 pose tags and production AI Designer art.
- [ ] `OverlayContentView` renders via `PoseRenderer`; `MascotFace.swift` and `MascotPose.swift` removed; `MascotPoseTests` removed; preview replaced.
- [ ] `accessibilityReduceMotion` honored — frames freeze + shake disabled.
- [ ] Accessibility label still surfaces via `OverlayContentView` (pose-aware string from `MicStatus.label`).
- [ ] All existing tests outside `MascotPoseTests` still pass.
- [ ] ~25–30 new unit tests pass.
- [ ] No regression in idle CPU (Instruments measurement).
- [ ] i18n state unchanged from current (English-only `MicStatus.label`); deferred to a later phase.

## 13. Open questions deferred to implementation plan

- Should `@2x` sprite variants ship? — decided no for now; pixel art with `.interpolation(.none)` looks correct at any scale.
- Where does the pose-fallback resolution log go? `Logger` subsystem `com.chaninlaw.Mewt`, category `MascotEngine` is the natural choice.
- `SafePackSource` visual fidelity — single colored circle is the floor; should it borrow `MicStatus.menuBarSymbol` for poor-man's parity?
- Distribution channel decision (MAS vs direct DMG vs both) — affects Studio's sandbox path; settle before foundation implementation.

These don't block the design; they get pinned down when the implementation plan is written.
