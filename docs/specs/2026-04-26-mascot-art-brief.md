# Mewt-Default Mascot — Art Brief

- **Date:** 2026-04-26
- **For:** AI Designer agent (first iteration) + pixel artist (parallel hire)
- **Engineering spec:** [`2026-04-26-mascot-engine-design.md`](./2026-04-26-mascot-engine-design.md) — read §4 and §7 for the format contract
- **Status:** Engineering blocks on this art for the foundation PR merge (not for development — fixtures cover that)

## 1. Mission

Mewt is a macOS menu-bar / floating overlay mascot that reflects microphone state. Its **only job** is to be charming and instantly readable at small sizes. The current version is rendered with hand-coded SwiftUI shapes; this brief is for the **first asset-driven version** that replaces that placeholder. We want a clear quality jump — not a like-for-like reproduction.

> **Inspiration:** [Runcat](https://kyome.io/runcat/) for the variable-FPS sprite-sheet shape (they animate by CPU; we animate by mic amplitude). Look at their cat for the energy level we're aiming for.

## 2. Character

**Mewt is a cat.** Round, cute, friendly. Reads as a single silhouette at 32×32 px and stays recognizable when scaled to 64–96 pt on a Retina display.

The current placeholder cat (built from circles + triangles in SwiftUI) is described below for reference — feel free to evolve the design, but keep the cat-ness.

| Element | Current placeholder (reference only) |
|---|---|
| Head | Circle, neutral fill |
| Ears | Two small triangles, top of head |
| Eyes | Dots (open) / capsule slits (closed) / circle-with-pupil (wide) / vertical sparkle (excited) |
| Mouth | Quad-curve smile / capsule zip / oval open / rounded-rect shouting |
| Accents | "z" for sleeping, ⚠️ bubble for alarm, waveform for excited — ALL handled by engine programmatically; **artist does not draw these** |

Color: neutral / warm tones recommended. Avoid pure red, pure green, pure yellow in the base sprite — engine applies tints (red for alarm, desaturate for muted) and we want them to read.

## 3. Deliverables

Bundle these inside a folder named **`Mewt-Default.mewtpet/`** (literal name, with the `.mewtpet` extension):

| File | Required | Spec |
|---|---|---|
| `sprite.png` | ✅ | Sprite sheet PNG, transparent background, PNG-32 |
| `sprite.json` | ✅ | Aseprite JSON export (Hash format — Aseprite's default) |
| `preview.png` | ✅ | 128×128 px preview thumbnail (single hero pose, idle frame 0 is fine) |
| `manifest.json` | ⚙️ engineering writes | Artist confirms `name` / `author` only |
| `overrides.json` | ⚪ optional | Only if the cat's anchor points differ from defaults — see §6 |

> **Naming is exact.** macOS treats folders ending in `.mewtpet` as our pack format. The folder name on disk must end in `.mewtpet` (not `.zip`, not `Mewt-Default-pack`).

## 4. Sprite sheet specifications

### 4.1 Frame size

**Choose one of: 16, 32, 64, or 128 px square** per frame, native pixel art (no anti-aliasing, no smoothing).

The engine integer-snaps the source frame into its 64pt display box (engine spec §4.6). Sizes from {16, 32, 64, 128} fill the box at a clean integer ratio; {24, 48, 96} render smaller than the box. Anything else is accepted but will rarely fill the box cleanly.

> **Recommendation for Mewt-Default:** 64×64. PixelLab's animation tool baseline is 64×64, and the engine renders it at 1× (no scale, no quality loss). 32×32 also works — the previous brief targeted it for stronger silhouette discipline (Stardew/Celeste run 16–32px characters). Pick what your tool produces natively; the engine doesn't care.

### 4.2 Frame count + tags

Four tags, with these target frame counts (engine tolerates more or fewer — `sprite.json` describes the actual ranges):

| Tag | Target frames | Frame duration | Mood / motion |
|---|---|---|---|
| `idle` | 5–8 | ~100ms each (~600ms loop) | Neutral. Gentle blink + breathe. Eyes open most of cycle, blink once mid-loop. Optional micro-sway of the head (1px shift) |
| `muted` | 1 (freeze) or 4–6 (slow-breath loop) | ~150ms each (freeze if 1 frame) | Eyes closed (calm, not asleep). Mouth zipped or X-shaped. Reads as "intentionally quiet". Engine animates whatever you ship — single-frame stays still automatically; multi-frame loops at the pack's fps multiplier. |
| `talkingWhileMuted` | 4–6 | ~80ms each (faster) | **Alarmed.** Wide-open eyes, mouth opening-closing rapidly. Conveys urgency — engine adds red tint + shake on top |
| `pushToTalk` | 4–6 | ~100ms each | Active speaking. Mouth opens-closes naturally, eyes engaged but not panicked. Confident |

Pack frame totals typically land in the 12–25 range. The engine does not enforce a count per tag — only that `idle` exists and frame ranges are in-bounds.

### 4.3 Layout

Either layout is fine — `sprite.json` describes per-frame `{x, y, w, h}` so the engine doesn't care:

- **Horizontal strip:** 480 × 32 px (15 frames × 32 px wide)
- **Grid:** e.g. 5 × 3 (160 × 96 px) or 8 × 2 (256 × 64 px) with row-major order

Aseprite's default export is horizontal strip — that's the path of least resistance.

### 4.4 Anchor stability

**Critical:** within a single tag, the cat's head and body must not drift between frames. If frame 0 has the head centered at (16, 14), frame 5 must have it within ±1 px of that. Otherwise the mascot wobbles when looped.

Acceptable per-tag exceptions:
- `idle`: ±1 px head sway is fine (looks like breathing)
- `talkingWhileMuted`: tiny side-to-side jitter (±1 px) is fine — the "alarm" feel justifies it
- `pushToTalk`: mouth movement only; head should be steady

## 5. `sprite.json` contract

Aseprite exports this automatically when you tag your frames. The engine consumes the **Hash** format with these fields:

```json
{
  "frames": [
    { "frame": { "x": 0,   "y": 0, "w": 32, "h": 32 }, "duration": 100 },
    { "frame": { "x": 32,  "y": 0, "w": 32, "h": 32 }, "duration": 100 },
    { "frame": { "x": 64,  "y": 0, "w": 32, "h": 32 }, "duration": 100 },
    { "frame": { "x": 96,  "y": 0, "w": 32, "h": 32 }, "duration": 100 },
    { "frame": { "x": 128, "y": 0, "w": 32, "h": 32 }, "duration": 100 },
    { "frame": { "x": 160, "y": 0, "w": 32, "h": 32 }, "duration": 100 },
    { "frame": { "x": 192, "y": 0, "w": 32, "h": 32 }, "duration": 0   },
    { "frame": { "x": 224, "y": 0, "w": 32, "h": 32 }, "duration": 80  },
    { "frame": { "x": 256, "y": 0, "w": 32, "h": 32 }, "duration": 80  },
    { "frame": { "x": 288, "y": 0, "w": 32, "h": 32 }, "duration": 80  },
    { "frame": { "x": 320, "y": 0, "w": 32, "h": 32 }, "duration": 80  },
    { "frame": { "x": 352, "y": 0, "w": 32, "h": 32 }, "duration": 100 },
    { "frame": { "x": 384, "y": 0, "w": 32, "h": 32 }, "duration": 100 },
    { "frame": { "x": 416, "y": 0, "w": 32, "h": 32 }, "duration": 100 },
    { "frame": { "x": 448, "y": 0, "w": 32, "h": 32 }, "duration": 100 }
  ],
  "meta": {
    "frameTags": [
      { "name": "idle",              "from": 0,  "to": 5,  "direction": "forward" },
      { "name": "muted",             "from": 6,  "to": 6,  "direction": "forward" },
      { "name": "talkingWhileMuted", "from": 7,  "to": 10, "direction": "forward" },
      { "name": "pushToTalk",        "from": 11, "to": 14, "direction": "forward" }
    ]
  }
}
```

### Tag name rules (must match exactly — case-sensitive)

| Required name | Why |
|---|---|
| `idle` | Mandatory. Engine throws `missingIdlePose` if absent. |
| `muted` | Optional but recommended (falls back to `idle` frozen) |
| `talkingWhileMuted` | Optional (falls back to `unmuted` then `idle`) |
| `pushToTalk` | Optional (falls back to `unmuted` then `idle`) |

> An `unmuted` tag may also be used as a synonym for `idle` if you prefer that semantic split — engine accepts both.

### Direction options

`forward`, `reverse`, `pingpong`, `pingpong_reverse` are all supported. Default to `forward` unless you have a reason.

## 6. Optional `overrides.json` — anchor tuning

The engine draws **programmatic overlays** on top of the sprite (the artist does **not** draw these):

- `Z` floating above the cat when muted
- `⚠️` exclamation symbol when alarming
- Radial glow when push-to-talk is active

These need anchor points expressed as **normalized coordinates inside the sprite frame** (0…1, where (0,0) is top-left and (1,1) is bottom-right of the 32×32 frame).

Defaults:

```json
{
  "schemaVersion": 1,
  "anchors": {
    "accentTopRight":  { "x": 0.78, "y": 0.18 },
    "accentBottomLeft":{ "x": 0.22, "y": 0.82 },
    "glowCenter":      { "x": 0.50, "y": 0.55 }
  }
}
```

If the cat's head sits at a different position (e.g. lower in the frame, or off-center), submit an `overrides.json` with the correct anchors. Otherwise omit the file — defaults work.

## 7. Style guardrails

| Rule | Why |
|---|---|
| Limited palette (~8–16 colors) | Pixel-art aesthetic; reads cleanly at small size |
| High contrast within sprite | Engine overlays tints (red, desaturate) — needs to read through them |
| Avoid red as primary fill | Conflicts with alarm tint; reserve red for emergencies |
| Transparent background | Sprite composites onto SwiftUI views with arbitrary backgrounds (menu bar, overlay, popover) |
| No drop shadows in sprite | Engine handles elevation via SwiftUI; baked shadows look wrong on dark mode |
| Single character only | No background scenery, no second character |

## 8. Inspiration / mood board (optional pointers)

- **Runcat** (kyome.io/runcat) — the energy and silhouette discipline we want
- **Stardew Valley animals** — small idle loops with personality
- **Celeste** Madeline portrait — readable expression at tiny sizes
- **Pusheen-style chunky cuteness** — but pixel-art, not vector

## 9. Acceptance checklist (artist self-check before handoff)

- [ ] `sprite.png` is exactly 1 PNG, transparent, 32px tall, frame count = 15
- [ ] `sprite.json` includes all 15 frames with `{x,y,w,h,duration}`
- [ ] `sprite.json` includes 4 `frameTags` with names matching §5 exactly (case-sensitive)
- [ ] `idle` tag present (mandatory)
- [ ] No tag overlaps another tag's frame range
- [ ] `preview.png` is 128×128, single frame (recommend idle frame 0)
- [ ] Folder is named exactly `Mewt-Default.mewtpet`
- [ ] Cat character is recognizable as a cat at 32×32 viewed at native size
- [ ] Within each tag, head position is stable (≤1 px drift)
- [ ] No baked shadows, no opaque background, no embedded text

## 10. Handoff

Drop the `Mewt-Default.mewtpet/` folder into `Mewt/Resources/` (engineering will set up the folder reference in Xcode). If you're sending via zip, **don't zip the `.mewtpet` itself** — zip a parent folder containing it, so the `.mewtpet` extension survives extraction.

Engineering uses test fixtures during development, so iterations don't block the build. Submit when confident; we'll do a visual-regression pass against all 4 `MicStatus` states once the engine is wired.