#!/usr/bin/env python3
"""Generate macOS AppIcon.appiconset images from the brand cat silhouette.

Source: assets/cat.svg (flat single-path silhouette, fill="currentColor").
Output: 10 PNGs sized for the macOS app icon idioms in Contents.json.

Design:
- Squircle-style rounded square background, warm cream→peach gradient
  (matches `metadata.json`'s "warm cream/beige fur" brand note).
- Silhouette rasterised at each target size with `rsvg-convert` so the
  curves stay crisp at every idiom (no nearest-neighbour artefacts).
- Cat occupies ~72% of the icon area, leaving the system-mask safe zone.

Run from repo root: `python3 scripts/build_app_icon.py`.
Requires `rsvg-convert` (brew install librsvg).
"""
import shutil
import subprocess
import tempfile
from io import BytesIO
from pathlib import Path
from PIL import Image, ImageDraw

REPO = Path(__file__).resolve().parent.parent
CAT_SRC = REPO / "assets" / "cat.svg"
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

BG_TOP = (255, 255, 255)   # pure white
BG_BOT = (244, 241, 234)   # soft cream
CAT_FILL = "#2a2d33"       # cool ash black (blue undertone)


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


def rasterize_cat(svg_text: str, size: int) -> Image.Image:
    """Render the cat SVG to an RGBA bitmap of exactly `size`x`size`."""
    with tempfile.NamedTemporaryFile("w", suffix=".svg", delete=False) as f:
        f.write(svg_text)
        tmp_path = f.name
    try:
        out = subprocess.run(
            ["rsvg-convert", "-w", str(size), "-h", str(size), tmp_path],
            check=True,
            capture_output=True,
        )
    finally:
        Path(tmp_path).unlink(missing_ok=True)
    return Image.open(BytesIO(out.stdout)).convert("RGBA")


def make_icon(size: int, svg_text: str) -> Image.Image:
    canvas = gradient_bg(size).convert("RGBA")
    canvas.putalpha(squircle_mask(size))

    # Cat occupies a generous fraction of the icon. Slightly smaller at
    # tiny sizes so antialiased edges don't smear into the squircle edge.
    fraction = 0.72 if size <= 64 else 0.78
    cat_size = int(size * fraction)

    # Render the silhouette at its display size for crisp edges, then
    # crop transparent margin so the visual centre matches the geometric
    # centre of the bbox rather than the SVG viewBox.
    cat = rasterize_cat(svg_text, cat_size)
    bbox = cat.getbbox()
    if bbox:
        cat = cat.crop(bbox)

    offset_x = (size - cat.width) // 2
    # Nudge upward ~1.5% so the ear-heavy silhouette sits visually centred.
    offset_y = (size - cat.height) // 2 - int(size * 0.015)
    canvas.alpha_composite(cat, dest=(offset_x, offset_y))
    return canvas


def main() -> None:
    if shutil.which("rsvg-convert") is None:
        raise SystemExit("rsvg-convert not found — `brew install librsvg`")
    if not CAT_SRC.exists():
        raise SystemExit(f"missing source: {CAT_SRC}")
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    svg_text = CAT_SRC.read_text().replace("currentColor", CAT_FILL)

    for base, scale, fname in SIZES:
        size = base * scale
        icon = make_icon(size, svg_text)
        icon.save(OUT_DIR / fname, optimize=True)
        print(f"  {fname:32s} {size}x{size}")


if __name__ == "__main__":
    main()
