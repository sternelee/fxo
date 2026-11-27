#!/usr/bin/env python3
"""Draws fx desktop's app icon and writes AppIcon.icns beside this file.

A rounded square in fx's warm charcoal with the braille fx mark in amber,
matching the wordmark the app draws on its home and About screens.

Needs Pillow and macOS's iconutil. Usage: python3 macos/make-icon.py
"""
import os
import subprocess
import tempfile

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
S = 1024

# The braille wordmark from src/art.zig, reduced to its solid cells. Each
# character is a 2x4 dot grid; the code points below map to those dots.
WORD = [
    "  ⠀⠀⠀⠀⠀⠀⣠⣾⣿⣿⣿⠀⠀⠀⠀⠀⠀⠀⠀",
    " ⠀⠀⠀⠀⠀⢰⣿⡿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀",
    " ⠀⠀⠀⣠⣶⣿⣿⣷⣶⡶⣶⣶⣆⠀⠀⠀⣴⣶⣶⠆",
    " ⠀⠀⠀⠉⢹⣿⣿⠉⠉⠀⠘⢿⣿⣧⣀⣾⣿⡿⠃⠀",
    " ⠀⠀⠀⠀⣼⣿⡏⠀⠀⠀⠀⠀⠀⠻⣿⣿⣿⠟⠀⠀⠀",
    " ⠀⠀⠀⢀⣿⣿⠃⠀⠀⠀⠀⢠⣦⠘⢿⣿⣷⡀⠀⠀",
    " ⠀⠀⠀⣸⣿⡟⠀⠀⠀⠀⣰⣿⣿⠗⠀⠻⣿⣿⣄⠀",
    " ⠀⠀⠀⣿⣿⠇⠀⠀⠀⠾⠿⠿⠋⠀⠀⠀⠘⠿⠿⠦",
    "  ⠀⣸⣿⡿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀",
    " ⣿⣿⣿⠟⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀",
]

# Apple Symbols has the braille block; draw the wordmark with the real glyphs
# rather than trying to map Unicode braille to dots by hand.
FONT = "/System/Library/Fonts/Supplemental/Apple Symbols.ttf"


def base():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    box = (100, 100, 924, 924)
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, 185, fill=255)
    fill = Image.new("RGBA", (S, S))
    fd = ImageDraw.Draw(fill)
    top, bottom = (0x2a, 0x26, 0x1e), (0x16, 0x14, 0x0f)
    for y in range(S):
        t = min(1, max(0, (y - 100) / 824))
        fd.line([(0, y), (S, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)) + (255,))
    img.paste(fill, (0, 0), mask)
    ImageDraw.Draw(img).rounded_rectangle(box, 185, outline=(0x3a, 0x35, 0x2b, 255), width=4)
    return img


def draw_mark(img):
    d = ImageDraw.Draw(img)
    amber = (0xe8, 0xa3, 0x3d, 255)
    rows = len(WORD)
    cols = max(len(line) for line in WORD)
    # Fit the block glyph to the target width, then set the line height from
    # the font's real ascent/descent so the ten rows fill the icon's middle.
    probe = ImageFont.truetype(FONT, 100)
    glyph_w = probe.getbbox("⣿")[2] / 100
    size = int(720 / (glyph_w * cols))
    font = ImageFont.truetype(FONT, size)
    ascent, descent = font.getmetrics()
    line_h = ascent + descent
    # Scale the vertical spacing to use the available height.
    if line_h * rows > 620:
        line_h = 620 / rows
    x0 = (S - font.getbbox("⣿")[2] * cols) / 2
    y0 = (S - line_h * rows) / 2
    for row, line in enumerate(WORD):
        d.text((x0, y0 + row * line_h), line, font=font, fill=amber)


def icns(img, name):
    with tempfile.TemporaryDirectory() as tmp:
        iconset = os.path.join(tmp, "AppIcon.iconset")
        os.mkdir(iconset)
        for size in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                px = size * scale
                suffix = "" if scale == 1 else "@2x"
                img.resize((px, px), Image.LANCZOS).save(
                    os.path.join(iconset, f"icon_{size}x{size}{suffix}.png"))
        subprocess.run(["iconutil", "-c", "icns", iconset,
                        "-o", os.path.join(HERE, name)], check=True)


if __name__ == "__main__":
    img = base()
    draw_mark(img)
    img.save(os.path.join(HERE, "icon-preview.png"))
    icns(img, "AppIcon.icns")
