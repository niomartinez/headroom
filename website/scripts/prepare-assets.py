#!/usr/bin/env python3
"""Turns Headroom's synthetic renders and app icon into the website's images.

Usage (from website/):
    python3 scripts/prepare-assets.py <headroom-render dir> <hero-render dir>

Inputs, both synthetic data only (see website/README.md):
  - `swift run headroom-render <dir>` (Packages/HeadroomKit): pills and panels on a mid-gray
    canvas. The gray is keyed out here so they sit on the page's own background.
  - `swift run hero-render <dir>` (scripts/hero-render): the hero panel at 3x, already transparent.

Outputs:
  public/images/hero-panel.png           hero panel (3x, transparent)
  public/images/og-pill.png              the pill at 6x, for the social card
  public/images/app-icon.png             app icon cropped to its squircle (512 px)
  public/images/renders/*.png            keyed panels and a composite of pill states (2x)
  src/app/icon.png, apple-icon.png, favicon.ico
"""

from __future__ import annotations

import shutil
import sys
from collections import deque
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
REPO = ROOT.parent
ICON = REPO / "App/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png"

CANVAS = (128, 128, 128)
PANEL_BG = 17  # #111111
PILL_BG = 0  # #000000


def key_out_canvas(path: Path, base: int) -> Image.Image:
    """Makes the flat gray canvas transparent and crops to the pill or panel.

    The edge pixels are blends of `base` (the shape's own fill) and the gray canvas, so their
    alpha comes from how far they sit between the two.
    """
    image = Image.open(path).convert("RGBA")
    width, height = image.size
    px = image.load()

    outside = [[False] * width for _ in range(height)]
    queue: deque[tuple[int, int]] = deque()
    for x in range(width):
        queue.extend([(x, 0), (x, height - 1)])
    for y in range(height):
        queue.extend([(0, y), (width - 1, y)])
    while queue:
        x, y = queue.popleft()
        if not (0 <= x < width and 0 <= y < height) or outside[y][x]:
            continue
        if px[x, y][:3] != CANVAS:
            continue
        outside[y][x] = True
        queue.extend([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])

    # Distance (up to 3 px) from the canvas, for the anti-aliased band.
    band = 3
    near = [[band + 1] * width for _ in range(height)]
    frontier = deque((x, y) for y in range(height) for x in range(width) if outside[y][x])
    for x, y in frontier:
        near[y][x] = 0
    while frontier:
        x, y = frontier.popleft()
        d = near[y][x]
        if d >= band:
            continue
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1), (x + 1, y + 1), (x - 1, y - 1), (x + 1, y - 1), (x - 1, y + 1)):
            if 0 <= nx < width and 0 <= ny < height and near[ny][nx] > d + 1:
                near[ny][nx] = d + 1
                frontier.append((nx, ny))

    for y in range(height):
        for x in range(width):
            if outside[y][x]:
                px[x, y] = (0, 0, 0, 0)
            elif near[y][x] <= band:
                r, g, b, _ = px[x, y]
                value = (r + g + b) / 3
                alpha = max(0.0, min(1.0, (CANVAS[0] - value) / (CANVAS[0] - base)))
                if alpha >= 0.98:
                    continue
                px[x, y] = (base, base, base, round(alpha * 255))

    return image.crop(image.getchannel("A").getbbox())


def pill_states(render_dir: Path, out: Path) -> None:
    """A composite of pill states: status on the left, moments on the right (2x)."""
    left = ["pill-working", "pill-waiting", "pill-near-limit", "pill-critical"]
    right = ["pill-moment-finished", "pill-moment-input", "pill-moment-limit", "pill-stale"]
    columns = [[key_out_canvas(render_dir / f"{name}.png", PILL_BG) for name in column] for column in (left, right)]
    gap_y, gap_x, margin = 40, 96, 64
    col_widths = [max(p.width for p in column) for column in columns]
    row_height = max(p.height for column in columns for p in column)
    rows = max(len(column) for column in columns)
    width = margin * 2 + sum(col_widths) + gap_x
    height = margin * 2 + rows * row_height + (rows - 1) * gap_y
    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    x = margin
    for column, col_width in zip(columns, col_widths):
        for index, pill in enumerate(column):
            y = margin + index * (row_height + gap_y) + (row_height - pill.height) // 2
            # Right-align the status pills and left-align the moments, so they meet in the middle.
            px = x + (col_width - pill.width if column is columns[0] else 0)
            canvas.alpha_composite(pill, (px, y))
        x += col_width + gap_x
    canvas.save(out, optimize=True)


def icons() -> None:
    icon = Image.open(ICON).convert("RGBA")
    squircle = icon.crop((100, 100, 924, 924))  # the opaque shape, without the drop shadow

    squircle.resize((512, 512), Image.LANCZOS).save(ROOT / "public/images/app-icon.png", optimize=True)
    squircle.resize((512, 512), Image.LANCZOS).save(ROOT / "src/app/icon.png", optimize=True)

    # iOS draws its own rounded corners and turns transparency black: fill the corners.
    flat = Image.new("RGBA", squircle.size, (17, 17, 16, 255))
    flat.alpha_composite(squircle)
    flat.convert("RGB").resize((180, 180), Image.LANCZOS).save(ROOT / "src/app/apple-icon.png", optimize=True)

    squircle.save(ROOT / "src/app/favicon.ico", sizes=[(16, 16), (32, 32), (48, 48)])


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    render_dir, hero_dir = Path(sys.argv[1]), Path(sys.argv[2])
    renders = ROOT / "public/images/renders"
    renders.mkdir(parents=True, exist_ok=True)

    shutil.copyfile(hero_dir / "hero-panel@3x.png", ROOT / "public/images/hero-panel.png")
    shutil.copyfile(hero_dir / "pill@6x.png", ROOT / "public/images/og-pill.png")

    for name in ["panel-full", "panel-stale", "panel-assumed-window", "panel-no-access"]:
        key_out_canvas(render_dir / f"{name}.png", PANEL_BG).save(renders / f"{name}.png", optimize=True)
    pill_states(render_dir, renders / "pill-states.png")
    icons()
    print("done")


if __name__ == "__main__":
    main()
