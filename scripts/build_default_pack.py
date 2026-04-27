#!/usr/bin/env python3
"""Build Mewt-Default.mewtpet from PixelLab-generated assets.

Reads animation frames from assets/CatMascot/animations/<tag-folder>/south/frame_*.png,
center-crops each 92×92 frame to 64×64 (cat occupies ~31×46 — fits easily),
stitches into a horizontal sprite strip, and emits sprite.json + manifest.json
+ preview.png in the standard .mewtpet folder layout.

Source pixel density is 1:1 (no upscaling), so the crop preserves art exactly.
"""
import json
import os
from pathlib import Path
from PIL import Image

REPO = Path(__file__).resolve().parent.parent
SRC  = REPO / "assets" / "CatMascot" / "animations"
DEST = REPO / "Mewt" / "Resources" / "Mewt-Default.mewtpet"

# Source-folder → engine pose tag, in sheet order. Frame count discovered at runtime.
TAG_ORDER = [
    ("idle",              "gentle_breathing_idle_blink_once_mid-cycle_1px_hea-209d82d7", 100),
    ("muted",             "eyes_closed_calmly_mouth_zipped-219b3244",                    150),
    ("talkingWhileMuted", "alarmed_wide_eyes_mouth_opening-closing_rapidly_pa-5f72da6d",  80),
    ("pushToTalk",        "speaking_confidently_natural_mouth_open-close_eyes-21d6817d", 100),
]

FRAME_SIDE = 64       # output frame size (engine §4.6 optimal)
SOURCE_SIDE = 92      # PixelLab native canvas
# Center-crop offset: (92-64)/2 = 14
CROP_OFFSET = (SOURCE_SIDE - FRAME_SIDE) // 2  # = 14
CROP_BOX = (CROP_OFFSET, CROP_OFFSET, CROP_OFFSET + FRAME_SIDE, CROP_OFFSET + FRAME_SIDE)


def collect_tag_frames():
    """Returns [(pose_tag, duration_ms, [PIL.Image, ...])] in sheet order."""
    out = []
    for pose, folder, dur in TAG_ORDER:
        d = SRC / folder / "south"
        frames = sorted(d.glob("frame_*.png"))
        assert frames, f"No frames for {pose} in {d}"
        imgs = [Image.open(f).convert("RGBA") for f in frames]
        for im in imgs:
            assert im.size == (SOURCE_SIDE, SOURCE_SIDE), \
                f"Expected {SOURCE_SIDE}x{SOURCE_SIDE}, got {im.size} in {d}"
        out.append((pose, dur, imgs))
        print(f"  {pose:20s} {len(imgs)} frames @ {dur}ms")
    return out


def build_sprite_sheet(tagged):
    total = sum(len(imgs) for _, _, imgs in tagged)
    sheet = Image.new("RGBA", (FRAME_SIDE * total, FRAME_SIDE), (0, 0, 0, 0))
    frames_meta = []
    pose_ranges = []  # (pose, from_idx, to_idx)
    idx = 0
    for pose, dur, imgs in tagged:
        from_idx = idx
        for im in imgs:
            cropped = im.crop(CROP_BOX)
            sheet.paste(cropped, (FRAME_SIDE * idx, 0))
            frames_meta.append({
                "frame": {"x": FRAME_SIDE * idx, "y": 0, "w": FRAME_SIDE, "h": FRAME_SIDE},
                "duration": dur,
            })
            idx += 1
        pose_ranges.append((pose, from_idx, idx - 1))
    return sheet, frames_meta, pose_ranges


def build_sprite_json(frames_meta, pose_ranges):
    return {
        "frames": frames_meta,
        "meta": {
            "frameTags": [
                {"name": pose, "from": lo, "to": hi, "direction": "forward"}
                for pose, lo, hi in pose_ranges
            ]
        },
    }


def build_manifest():
    return {
        "packSchemaVersion": 1,
        "id": "com.chaninlaw.mewt.default",
        "name": "Mewt",
        "author": "Mewt",
        "version": "1.0.0",
        "license": "proprietary",
        "tier": "free",
    }


def build_overrides():
    # Curve note: default engine curve had fps=0 at amp=0, which freezes
    # idle when the user is silent — fine for hand-coded SwiftUI shapes
    # (which had their own internal blink) but wrong for sprite-driven
    # animation, which needs a baseline tick to breathe. Bump amp=0 to
    # 6 fps so the idle loop (~700ms) plays gently even in silence.
    # Per-pose multipliers nudge the alarm + PTT poses faster to match
    # their "urgent / confident" intent in the art brief.
    return {
        "schemaVersion": 1,
        "frameRate": {
            "amplitudeToFps": [
                {"amp": 0.00, "fps": 6},
                {"amp": 0.05, "fps": 8},
                {"amp": 0.30, "fps": 12},
                {"amp": 0.60, "fps": 18},
            ]
        },
        "perPoseFpsMultiplier": {
            # Slow muted ~50% (calm sleep-breath) → 6 fps × 0.5 = 3 fps × 6 frames = 2s loop.
            # Engine stopped hard-coding muted=freeze, so the pack drives the pace now.
            "muted": 0.5,
            "talkingWhileMuted": 1.4,
            "pushToTalk": 1.2,
        },
    }


def build_preview(sheet):
    # Idle frame 0 = first 64×64 of the sheet, scaled 2× nearest-neighbor → 128×128
    frame0 = sheet.crop((0, 0, FRAME_SIDE, FRAME_SIDE))
    return frame0.resize((128, 128), Image.NEAREST)


def main():
    print(f"SRC:  {SRC}")
    print(f"DEST: {DEST}")
    DEST.mkdir(parents=True, exist_ok=True)

    tagged = collect_tag_frames()
    sheet, frames_meta, pose_ranges = build_sprite_sheet(tagged)
    print(f"\nSheet: {sheet.size[0]}×{sheet.size[1]} px, {len(frames_meta)} frames")
    for pose, lo, hi in pose_ranges:
        print(f"  {pose:20s} frames {lo}–{hi} ({hi - lo + 1})")

    sheet.save(DEST / "sprite.png", optimize=True)

    sprite_json = build_sprite_json(frames_meta, pose_ranges)
    (DEST / "sprite.json").write_text(json.dumps(sprite_json, indent=2) + "\n")

    manifest = build_manifest()
    (DEST / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")

    overrides = build_overrides()
    (DEST / "overrides.json").write_text(json.dumps(overrides, indent=2) + "\n")

    preview = build_preview(sheet)
    preview.save(DEST / "preview.png", optimize=True)

    sizes = {f.name: f.stat().st_size for f in DEST.iterdir() if f.is_file()}
    print(f"\nOutput files:")
    for n, sz in sorted(sizes.items()):
        print(f"  {n:16s} {sz:>6d} bytes")


if __name__ == "__main__":
    main()
