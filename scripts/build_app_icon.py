#!/usr/bin/env python3
"""Generate macOS AppIcon.appiconset images from the brand cat mascot.

Source: assets/CatMascot/rotations/south.png (92x92 pixel-art cat).
Output: 10 PNGs sized for the macOS app icon idioms in Contents.json.

Design:
- Squircle-style rounded square background, warm cream→peach gradient
  (matches `metadata.json`'s "warm cream/beige fur" brand note).
- Cat upscaled with NEAREST neighbour to preserve crisp pixel art.
- Cat occupies ~72% of the icon area, leaving the system-mask safe zone.

Run from repo root: `python3 scripts/build_app_icon.py`.
"""
from pathlib import Path
from PIL import Image, ImageDraw

REPO = Path(__file__).resolve().parent.parent
CAT_SRC = REPO / "assets" / "CatMascot" / "rotations" / "south.png"
OUT_DIR = REPO / "Mewt" / "Assets.xcassets" / "AppIcon.appiconset"

# (base_pt, scale, filename) — matches the existing Contents.json declarations.
SIZES = [
    (16, 1, "icon_16x16.png"),
    (16, 2, "icon_16x16@2x.png"),
    (32, 1, "icon_32x32.png"),
    (32, 2, "icon_32x32@2x.png"),
    (128, 1, "icon_128x128.png"),
    (128, 2, "icon_128x128@2x.png"),
    (256, 1, "icon_256x256.png"),
    (256, 2, "icon_256x256@2x.png"),
    (512, 1, "icon_512x512.png"),
    (512, 2, "icon_512x512@2x.png"),
]

BG_TOP = (255, 244, 230)   # warm cream
BG_BOT = (255, 215, 175)   # peach / beige


def gradient_bg(size: int) -> Image.Image:
    """Vertical cream→peach gradient via 1-column resize (fast)."""
    column = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / max(1, size - 1)
        r = int(BG_TOP[0] * (1 - t) + BG_BOT[0] * t)
        g = int(BG_TOP[1] * (1 - t) + BG_BOT[1] * t)
        b = int(BG_TOP[2] * (1 - t) + BG_BOT[2] * t)
        column.putpixel((0, y), (r, g, b))
    return column.resize((size, size))


def squircle_mask(size: int, radius_ratio: float = 0.225) -> Image.Image:
    """Apple-style rounded square (radius ~22.5% of the canvas)."""
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    r = int(size * radius_ratio)
    draw.rounded_rectangle((0, 0, size, size), radius=r, fill=255)
    return mask


def make_icon(size: int, cat: Image.Image) -> Image.Image:
    canvas = gradient_bg(size).convert("RGBA")
    canvas.putalpha(squircle_mask(size))

    # Crop transparent padding around the cat so the mascot fills the
    # active area instead of swimming in empty space. The source PNG has
    # ~20–30% transparent margin baked in for sprite positioning.
    bbox = cat.getbbox()
    if bbox:
        cat = cat.crop(bbox)

    # Cat occupies a generous fraction of the icon — smaller at micro
    # sizes where antialiasing destroys pixel-art detail.
    fraction = 0.82 if size <= 64 else 0.78
    target = int(size * fraction)
    # Snap to an integer multiple of the source dim so the pixel grid
    # stays aligned for the NEAREST upscale (no half-pixel blur).
    src_w = cat.width
    if size >= 128:
        scale_factor = max(1, round(target / src_w))
        target = scale_factor * src_w
    scaled = cat.resize((target, target), Image.NEAREST)

    offset_x = (size - target) // 2
    # Nudge upward 2% so the cat sits visually centred (mascot's
    # head-heavy silhouette pulls the optical centre below geometric).
    offset_y = (size - target) // 2 - int(size * 0.02)
    canvas.alpha_composite(scaled, dest=(offset_x, offset_y))
    return canvas


def main() -> None:
    if not CAT_SRC.exists():
        raise SystemExit(f"missing source: {CAT_SRC}")
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    cat = Image.open(CAT_SRC).convert("RGBA")
    for base, scale, fname in SIZES:
        size = base * scale
        icon = make_icon(size, cat)
        icon.save(OUT_DIR / fname, optimize=True)
        print(f"  {fname:32s} {size}x{size}")


if __name__ == "__main__":
    main()
