#!/usr/bin/env python3
"""Compose the raw panel captures into images sized for social posts.

    ./scripts/make-social-images.py

Reads Assets/screenshots/*.png (see capture-screenshots.sh) and writes
Assets/social/. The panel is 360pt wide, which is tiny in a feed, so each
capture is placed on a background with a caption at a size the platforms
actually want.

Needs Pillow:  python3 -m pip install --user Pillow
"""
import os
import sys

try:
    from PIL import Image, ImageDraw, ImageFilter, ImageFont
except ImportError:
    sys.exit("Pillow is required: python3 -m pip install --user Pillow")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHOTS = os.path.join(ROOT, "Assets", "screenshots")
OUT = os.path.join(ROOT, "Assets", "social")

# Same violet-to-cyan accent the app uses, so the frame matches the UI in it.
VIOLET = (107, 92, 250)
CYAN = (61, 184, 240)
WHITE = (243, 245, 250)
MUTED = (150, 160, 184)
# Corners of the background wash, clockwise from top left.
CORNERS = [(11, 18, 38), (19, 26, 54), (26, 17, 64), (9, 13, 28)]

LINK = "github.com/mehedi891/clipstack"

PORTRAIT = (1080, 1350)
SQUARE = (1200, 1200)
LANDSCAPE = (1200, 630)

# (source capture, output name, headline, subline)
CARDS = [
    ("clipboard", "01-clipboard",
     "Everything you copied.",
     "One shortcut away. Press ⇧⌘V anywhere."),
    ("pinned", "02-pinned",
     "Pin what you reuse.",
     "The snippets you paste ten times a day, always on top."),
    ("emoji", "03-emoji",
     "Emoji, in the same panel.",
     "Search by name. No character viewer, no browser tab."),
    # Kaomoji themselves are left out of the caption: the box-drawing glyphs
    # they are built from are missing from the system font Pillow loads, and
    # render as blocks.
    ("kaomoji", "04-kaomoji",
     "Kaomoji too.",
     "The table flip is one click away."),
    ("symbols", "05-symbols",
     "And the symbols you can never type.",
     "Arrows, maths, currency, punctuation."),
]

BULLETS = [
    "Text, images and rich text — all searchable",
    "Pin what you paste every day",
    "Emoji, kaomoji and symbol pickers",
    "Menu bar only. No Dock icon in the way",
    "Fully offline. No account, no analytics",
]


def font(size, weight="Regular"):
    """SF, the system font, with a Helvetica Neue fallback."""
    try:
        f = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", size)
        try:
            f.set_variation_by_name(weight)
        except Exception:
            pass
        return f
    except OSError:
        index = {"Bold": 1, "Semibold": 1, "Regular": 0}.get(weight, 0)
        return ImageFont.truetype("/System/Library/Fonts/HelveticaNeue.ttc", size, index=index)


def background(size):
    """A four-corner wash with two soft accent glows over it."""
    width, height = size
    corners = Image.new("RGB", (2, 2))
    corners.putpixel((0, 0), CORNERS[0])
    corners.putpixel((1, 0), CORNERS[1])
    corners.putpixel((1, 1), CORNERS[2])
    corners.putpixel((0, 1), CORNERS[3])
    canvas = corners.resize(size, Image.BICUBIC).convert("RGBA")

    for colour, centre, radius, strength in [
        (VIOLET, (width * 0.28, height * 0.30), max(size) * 0.42, 0.30),
        (CYAN, (width * 0.80, height * 0.78), max(size) * 0.34, 0.16),
    ]:
        mask = Image.new("L", size, 0)
        ImageDraw.Draw(mask).ellipse(
            [centre[0] - radius, centre[1] - radius,
             centre[0] + radius, centre[1] + radius],
            fill=int(255 * strength),
        )
        mask = mask.filter(ImageFilter.GaussianBlur(radius * 0.55))
        canvas.alpha_composite(Image.composite(
            Image.new("RGBA", size, colour + (255,)),
            Image.new("RGBA", size, colour + (0,)),
            mask,
        ))
    return canvas


def paste_panel(canvas, shot, box_top, target_height, centre_x=None):
    """Drop a capture on the canvas at a given height, with a soft shadow."""
    scale = target_height / shot.height
    panel = shot.resize(
        (round(shot.width * scale), target_height), Image.LANCZOS
    )
    x = round((canvas.width - panel.width) / 2) if centre_x is None else centre_x

    # The capture's corners are transparent, so its own alpha makes the shadow.
    spread = 34
    shadow = Image.new("RGBA", (panel.width + spread * 2, panel.height + spread * 2), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 190), (spread, spread), panel.split()[3])
    shadow = shadow.filter(ImageFilter.GaussianBlur(spread * 0.6))
    canvas.alpha_composite(shadow, (x - spread, box_top - spread + 12))
    canvas.alpha_composite(panel, (x, box_top))
    return panel.width


def text(draw, xy, body, size, weight="Regular", colour=WHITE, anchor="la"):
    draw.text(xy, body, font=font(size, weight), fill=colour, anchor=anchor)


def portrait_card(name, source, headline, subline):
    canvas = background(PORTRAIT)
    draw = ImageDraw.Draw(canvas)
    centre = PORTRAIT[0] // 2

    text(draw, (centre, 128), headline, 62, "Bold", WHITE, "ma")
    text(draw, (centre, 214), subline, 34, "Regular", MUTED, "ma")

    shot = Image.open(os.path.join(SHOTS, f"{source}.png")).convert("RGBA")
    paste_panel(canvas, shot, 300, 1000)

    out = os.path.join(OUT, f"{name}.png")
    canvas.convert("RGB").save(out, optimize=True)
    print(f"  ✓ {os.path.basename(out)}  {canvas.width}x{canvas.height}")


def square_card():
    canvas = background(SQUARE)
    draw = ImageDraw.Draw(canvas)
    centre = SQUARE[0] // 2

    text(draw, (centre, 96), "Clipboard history for macOS", 64, "Bold", WHITE, "ma")
    text(draw, (centre, 182), "Press ⇧⌘V. Paste anything you have copied.",
         34, "Regular", MUTED, "ma")

    shot = Image.open(os.path.join(SHOTS, "clipboard.png")).convert("RGBA")
    paste_panel(canvas, shot, 258, 806)

    text(draw, (centre, 1136), LINK, 30, "Semibold", MUTED, "md")

    out = os.path.join(OUT, "hero-square.png")
    canvas.convert("RGB").save(out, optimize=True)
    print(f"  ✓ {os.path.basename(out)}  {canvas.width}x{canvas.height}")


def landscape_card():
    """Panel on the right, copy on the left."""
    canvas = background(LANDSCAPE)
    draw = ImageDraw.Draw(canvas)

    shot = Image.open(os.path.join(SHOTS, "clipboard.png")).convert("RGBA")
    panel_height = 546
    panel_width = round(shot.width * panel_height / shot.height)
    panel_x = LANDSCAPE[0] - panel_width - 64
    paste_panel(canvas, shot, 42, panel_height, centre_x=panel_x)

    left = 76
    text(draw, (left, 64), "Clipstack", 64, "Bold")
    text(draw, (left, 146), "Clipboard history for macOS.", 30, "Regular", MUTED)
    text(draw, (left, 184), "Free and open source.", 30, "Regular", MUTED)

    y = 262
    for line in BULLETS:
        draw.ellipse([left + 3, y + 11, left + 13, y + 21], fill=VIOLET)
        text(draw, (left + 30, y), line, 25, "Regular", WHITE)
        y += 48

    text(draw, (left, 528), LINK, 27, "Semibold", CYAN)

    out = os.path.join(OUT, "hero-landscape.png")
    canvas.convert("RGB").save(out, optimize=True)
    print(f"  ✓ {os.path.basename(out)}  {canvas.width}x{canvas.height}")


def main():
    os.makedirs(OUT, exist_ok=True)
    for source, name, headline, subline in CARDS:
        portrait_card(name, source, headline, subline)
    square_card()
    landscape_card()
    print(f"\nSaved to {OUT}")


if __name__ == "__main__":
    main()
