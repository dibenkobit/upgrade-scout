"""Draws the textures of the Upgrades tab into UpgradeScout/Media.

    uv run --no-project --python 3.12 --with numpy --with pillow python scripts/make-textures.py

Everything is drawn from shapes and gradients in this file, at two texture pixels per window
unit, so the art stays sharp on a 4K screen. Frames are made to be cut in nine (corners keep
their size, edges and middle stretch); UI.lua lists the corner size it cuts each one with.
Pass a folder as the second argument to also get PNG copies for looking at.
"""
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "UpgradeScout", "Media")
PNG = sys.argv[2] if len(sys.argv) > 2 else None

GOLD_HI, GOLD, GOLD_LO = (1.00, 0.91, 0.60), (0.84, 0.62, 0.21), (0.36, 0.23, 0.06)
BRONZE_HI, BRONZE, BRONZE_LO = (0.74, 0.57, 0.31), (0.46, 0.33, 0.15), (0.17, 0.11, 0.04)
LIGHT = np.array([-0.50, -0.866])       # where the light comes from: above, a little to the left


def grid(w, h):
    y, x = np.mgrid[0:h, 0:w]
    return x + 0.5, y + 0.5


def smooth(a, b, v):
    t = np.clip((v - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def mix(a, b, t):
    a, b = np.asarray(a, float), np.asarray(b, float)
    t = np.asarray(t, float)[..., None]
    return a * (1 - t) + b * t


def box(x, y, x0, y0, x1, y1, r):
    """Signed distance to a rounded box: negative inside."""
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    qx = np.abs(x - cx) - ((x1 - x0) / 2 - r)
    qy = np.abs(y - cy) - ((y1 - y0) / 2 - r)
    return np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - r


def segment(x, y, ax, ay, bx, by):
    """Distance to the line from a to b."""
    px, py, dx, dy = x - ax, y - ay, bx - ax, by - ay
    t = np.clip((px * dx + py * dy) / (dx * dx + dy * dy), 0, 1)
    return np.hypot(px - dx * t, py - dy * t)


def cover(d):
    """How much of a pixel a shape covers, from its signed distance."""
    return np.clip(0.5 - d, 0, 1)


def band(d, outer, inner):
    """The ring between two distances inside a shape (outer nearer the edge)."""
    return cover(d - outer) * (1 - cover(d - inner))


def lit(d, hi, mid, lo, flip=False):
    """Metal: every point of an edge is as bright as it faces the light."""
    gy, gx = np.gradient(d)
    size = np.maximum(np.hypot(gx, gy), 1e-6)
    s = (gx * LIGHT[0] + gy * LIGHT[1]) / size
    if flip:
        s = -s
    return np.where((s > 0)[..., None], mix(mid, hi, np.clip(s, 0, 1)), mix(mid, lo, np.clip(-s, 0, 1)))


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.rgb = np.zeros((h, w, 3))
        self.a = np.zeros((h, w))

    def over(self, rgb, alpha):
        rgb = np.broadcast_to(np.asarray(rgb, float), self.rgb.shape)
        alpha = np.broadcast_to(np.asarray(alpha, float), self.a.shape)
        out = alpha + self.a * (1 - alpha)
        num = rgb * alpha[..., None] + self.rgb * (self.a * (1 - alpha))[..., None]
        self.rgb = np.where(out[..., None] > 1e-6, num / np.maximum(out, 1e-6)[..., None], self.rgb)
        self.a = out

    def bleed(self, passes=6):
        """Gives see-through pixels the colour next to them, so that the game's smoothing
        does not pull black into the edges."""
        rgb, known = self.rgb.copy(), self.a > 1 / 255
        for _ in range(passes):
            total, count = np.zeros_like(rgb), np.zeros(known.shape)
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    k = np.roll(np.roll(known, dy, 0), dx, 1)
                    total += np.roll(np.roll(rgb, dy, 0), dx, 1) * k[..., None]
                    count += k
            fresh = ~known & (count > 0)
            rgb[fresh] = total[fresh] / count[fresh][..., None]
            known = known | fresh
        self.rgb = rgb

    def save(self, name, white=False):
        if white:
            self.rgb = np.ones_like(self.rgb)
        else:
            self.bleed()
        data = np.dstack([np.clip(self.rgb, 0, 1), np.clip(self.a, 0, 1)])
        image = Image.fromarray((data * 255 + 0.5).astype(np.uint8), "RGBA")
        image.save(os.path.join(OUT, name + ".tga"))
        if PNG:
            image.save(os.path.join(PNG, name + ".png"))


def noise(n, seed, waves=7):
    """A smooth uneven line of n values around zero, the same on every run."""
    rng = np.random.RandomState(seed)
    x = np.arange(n) / n
    out = np.zeros(n)
    for k in range(1, waves + 1):
        out += np.sin(2 * np.pi * (k * x + rng.rand())) * rng.rand() / k
    return out / np.abs(out).max()


# ---------------------------------------------------------------------------
# Panel: the dark plate the list lies on. A fine gold edge, a second line that
# only shows in the corners, a faint warm light along the inside of the edge.
# ---------------------------------------------------------------------------
def panel():
    c = Canvas(64, 64)
    x, y = grid(64, 64)
    d = box(x, y, 3, 3, 61, 61, 8)
    c.over((0, 0, 0), 0.60 * (1 - smooth(0, 3.2, d)) * (d > -1))
    c.over((0.050, 0.039, 0.031), 0.97 * cover(d))
    c.over((0.62, 0.40, 0.13), 0.13 * np.exp(-np.maximum(-d - 3, 0) / 5.0) * cover(d + 3))
    # The corner line: 5 px inside the edge, gone before the corner piece ends.
    near = np.maximum(np.minimum(x - 3, 61 - x), np.minimum(y - 3, 61 - y))
    corner = 1 - smooth(9, 18, near)
    c.over(lit(d + 6, GOLD_HI, GOLD, GOLD_LO), 0.62 * band(d, -5.6, -6.8) * corner)
    c.over((0, 0, 0), 0.90 * band(d, -1.9, -3.1))
    c.over(lit(d, GOLD_HI, GOLD, GOLD_LO), band(d, 0, -2.0))
    c.save("Panel")


# ---------------------------------------------------------------------------
# Buttons: a face in a gold rim. Red for the one that matters, dark for the rest.
# ---------------------------------------------------------------------------
def button(name, top, bottom, rim):
    c = Canvas(64, 64)
    x, y = grid(64, 64)
    d = box(x, y, 2, 2, 62, 62, 7)
    c.over((0, 0, 0), 0.65 * (1 - smooth(0, 2.2, d)) * (d > -1))
    face = mix(top, bottom, smooth(6, 58, y))
    c.over(face, cover(d + 2))
    c.over((1, 1, 1), 0.075 * (1 - smooth(24, 34, y)) * cover(d + 4))             # the gloss on the top half
    c.over((0, 0, 0), 0.38 * np.exp(-np.maximum(-d - 3, 0) / 4.5) * cover(d + 3))  # darker towards the rim
    gy, gx = np.gradient(d)
    up = np.clip(-gy / np.maximum(np.hypot(gx, gy), 1e-6), 0, 1)
    c.over(mix(top, (1, 0.86, 0.70), 0.45), 0.55 * band(d, -3.2, -4.3) * up)        # a lit lip under the top rim
    c.over((0, 0, 0), 0.92 * band(d, -2.0, -3.2))
    c.over(lit(d, *rim), band(d, 0, -2.2))
    c.save(name)


def button_glow():
    c = Canvas(64, 64)
    x, y = grid(64, 64)
    d = box(x, y, 4.5, 4.5, 59.5, 59.5, 5)
    c.over((1, 1, 1), (0.20 - 0.14 * smooth(6, 58, y)) * cover(d))
    c.save("ButtonGlow", white=True)


# ---------------------------------------------------------------------------
# Inset: a recess (the scale field, a tick box, the trough of a bar). Lit from
# above, so its top edge is in shadow and its bottom edge catches the light.
# ---------------------------------------------------------------------------
def inset():
    c = Canvas(64, 64)
    x, y = grid(64, 64)
    d = box(x, y, 1, 1, 63, 63, 6)
    c.over((0.026, 0.020, 0.016), 0.96 * cover(d))
    c.over((0, 0, 0), 0.55 * np.exp(-np.maximum(y - 3, 0) / 3.5) * cover(d + 2))
    c.over(lit(d, BRONZE_HI, BRONZE, BRONZE_LO, flip=True), band(d, 0, -1.7))
    c.save("Inset")


def bar():
    c = Canvas(128, 16)
    x, y = grid(128, 16)
    t = y / 16
    colour = np.where((t < 0.38)[..., None],
                      mix((1.00, 0.95, 0.62), (0.99, 0.78, 0.22), smooth(0.0, 0.38, t)),
                      mix((0.99, 0.78, 0.22), (0.70, 0.43, 0.07), smooth(0.38, 1.0, t)))
    grain = 1 + 0.085 * noise(128, 11)[None, :] + 0.035 * noise(128, 5, 15)[None, :]
    c.over(np.clip(colour * grain[..., None], 0, 1), np.ones((16, 128)))
    c.save("Bar")


# ---------------------------------------------------------------------------
# Small marks
# ---------------------------------------------------------------------------
def check():
    c = Canvas(32, 32)
    x, y = grid(32, 32)
    d = np.minimum(segment(x, y, 7.5, 16.5, 13.5, 22.5), segment(x, y, 13.5, 22.5, 25, 8.5))
    c.over((0, 0, 0), 0.75 * cover(d - 3.6))
    c.over(mix((1.00, 0.93, 0.62), (0.88, 0.62, 0.16), smooth(8, 24, y)), cover(d - 2.1))
    c.save("Check")


def chevron():
    x, y = grid(32, 32)
    # Pointing down: an open slot, the scale field. Pointing right: a folded slot.
    for name, d in (
        ("Chevron", np.minimum(segment(x, y, 8, 12.5, 16, 20.5), segment(x, y, 16, 20.5, 24, 12.5))),
        ("ChevronRight", np.minimum(segment(x, y, 12.5, 8, 20.5, 16), segment(x, y, 20.5, 16, 12.5, 24))),
    ):
        c = Canvas(32, 32)
        c.over((1, 1, 1), cover(d - 1.7))
        c.save(name, white=True)


def diamond():
    c = Canvas(32, 32)
    x, y = grid(32, 32)
    d = (np.abs(x - 16) + np.abs(y - 16) - 9.5) / np.sqrt(2)
    c.over((0, 0, 0), 0.70 * cover(d - 1.4))
    c.over(lit(d, GOLD_HI, GOLD, GOLD_LO), cover(d))
    c.over((1, 0.97, 0.80), 0.55 * cover(d + 4.2) * smooth(18, 10, x + y) * 0.9)
    c.save("Diamond")


def glow():
    c = Canvas(64, 64)
    x, y = grid(64, 64)
    r = np.hypot(x - 32, y - 32)
    c.over((1, 1, 1), (1 - smooth(0, 31, r)) ** 2)
    c.save("Glow", white=True)


def row_glow():
    c = Canvas(256, 32)
    x, y = grid(256, 32)
    across = smooth(0, 28, x) * smooth(0, 28, 256 - x)
    down = 0.72 + 0.28 * np.sin(np.pi * y / 32)
    c.over((1, 1, 1), across * down)
    c.save("RowGlow", white=True)


def line():
    c = Canvas(256, 2)
    x, y = grid(256, 2)
    c.over((1, 1, 1), smooth(0, 40, x) * smooth(0, 40, 256 - x))
    c.save("Line", white=True)


# The band a slot's name stands on: amber that fades to the right between two gold lines.
def header_band():
    c = Canvas(256, 32)
    x, y = grid(256, 32)
    plate = 0.42 * (1 - smooth(0, 215, x)) * (0.80 + 0.20 * np.sin(np.pi * y / 32))
    c.over(mix((0.64, 0.40, 0.09), (0.36, 0.20, 0.04), smooth(0, 32, y)), plate)
    edge = ((y < 1) | (y > 31)) * (1 - smooth(10, 250, x))
    c.over((0.98, 0.78, 0.32), 0.85 * edge)
    c.save("HeaderBand")


def chip():
    x, y = grid(32, 32)
    d = box(x, y, 1, 1, 31, 31, 6)
    c = Canvas(32, 32)
    c.over((1, 1, 1), cover(d) * (1.0 - 0.22 * smooth(4, 28, y)))
    c.save("Chip", white=True)
    c = Canvas(32, 32)
    c.over((1, 1, 1), band(d, 0, -1.6))
    c.save("ChipEdge", white=True)


# The rim of an item icon: tinted with the item's quality colour; the dark line inside it
# stays dark and sets the icon apart.
def icon_rim():
    c = Canvas(64, 64)
    x, y = grid(64, 64)
    d = box(x, y, 1, 1, 63, 63, 7)
    c.over((0, 0, 0), 0.85 * band(d, -2.6, -5.0))
    gy, gx = np.gradient(d)
    s = (gx * LIGHT[0] + gy * LIGHT[1]) / np.maximum(np.hypot(gx, gy), 1e-6)
    shade = 0.80 + 0.20 * np.clip(s, -1, 1)
    c.over(np.dstack([shade, shade, shade]), band(d, 0, -2.8))
    c.save("IconRim")


def main():
    os.makedirs(OUT, exist_ok=True)
    if PNG:
        os.makedirs(PNG, exist_ok=True)
    panel()
    button("ButtonRed", (0.56, 0.075, 0.050), (0.27, 0.028, 0.022), (GOLD_HI, GOLD, GOLD_LO))
    button("ButtonDark", (0.185, 0.140, 0.100), (0.080, 0.060, 0.044), (GOLD_HI, (0.74, 0.55, 0.20), GOLD_LO))
    button_glow()
    inset()
    bar()
    check()
    chevron()
    diamond()
    glow()
    row_glow()
    line()
    header_band()
    chip()
    icon_rim()
    print("textures written to", OUT)


if __name__ == "__main__":
    main()
