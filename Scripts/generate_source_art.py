#!/usr/bin/env python3
"""
Authoring pipeline for the Focus Garden top-down tileset (32px logical grid, "HD").

HYBRID, all original / CC0:
  - Characterful sprites (companion moods, cottage) are generated UNIQUELY with the
    OpenAI Images API (gpt-image-1.5), then downscaled to 32/64px keeping their shading.
  - Base tiles, crops, fences and FX are drawn programmatically at 32px on a cozy,
    gentle-contrast palette with shading ramps (calm on the eyes, Stardew-level detail;
    no Stardew assets are used).

Outputs -> ThirdParty/garden-pixel-src/
  - one 1x master PNG per tile (32x32, prop_home 64x64)
  - manifest.json  (name -> {w, h, file})
  - _preview.png   (contact sheet)

Raw AI generations are cached under ThirdParty/garden-pixel-src/_ai_raw/ (gitignored)
so reruns are free and deterministic. Requires OPENAI_API_KEY (loaded from .env).

Run:  ./.venv/bin/python Scripts/generate_source_art.py
"""
import base64
import io
import json
import math
import os
import time
import urllib.request
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "ThirdParty" / "garden-pixel-src"
AI_CACHE = SRC / "_ai_raw"
TILE = 32

# ---------------------------------------------------------------- palette (RGBA)
# Gentle-contrast cozy farm palette with shading ramps so 32px tiles read calm + detailed.
P = {
    "clear":     (0, 0, 0, 0),
    "ink":       (48, 38, 30, 255),
    # grass ramp (soft, low contrast on the base)
    "g_hi":      (150, 196, 112, 255),
    "g_lt":      (124, 178, 92, 255),
    "g0":        (108, 164, 80, 255),
    "g_dk":      (92, 146, 68, 255),
    "g_sh":      (74, 122, 54, 255),
    "flower_y":  (245, 224, 128, 255),
    "flower_w":  (244, 240, 226, 255),
    # dirt path
    "p_hi":      (200, 168, 124, 255),
    "p0":        (180, 144, 100, 255),
    "p_dk":      (154, 116, 76, 255),
    "p_st":      (126, 100, 70, 255),
    # tilled soil ramps
    "s_sp_hi":   (156, 108, 72, 255), "s_sp": (134, 90, 58, 255), "s_sp_dk": (104, 66, 40, 255),
    "s_su_hi":   (146, 98, 62, 255),  "s_su": (122, 80, 48, 255), "s_su_dk": (94, 58, 34, 255),
    "s_au_hi":   (132, 86, 52, 255),  "s_au": (110, 68, 38, 255), "s_au_dk": (84, 50, 28, 255),
    "snow_hi":   (232, 238, 242, 255),"snow": (208, 218, 226, 255),"snow_dk": (176, 190, 202, 255),
    "leaf_au":   (204, 130, 58, 255),
    # wood ramp (fence / sign)
    "w_hi":      (206, 168, 116, 255),
    "w0":        (176, 134, 88, 255),
    "w_dk":      (136, 100, 62, 255),
    "w_sh":      (104, 74, 46, 255),
    # crops
    "cream":     (238, 224, 168, 255), "cream_dk": (208, 188, 128, 255),
    "cauli":     (240, 238, 224, 255), "cauli_dk": (206, 204, 184, 255),
    "berry":     (214, 72, 84, 255),   "berry_hi": (238, 128, 128, 255), "berry_dk": (168, 48, 60, 255),
    # fx
    "rain":      (182, 216, 244, 210), "rain_dk": (140, 186, 226, 210),
    "spark":     (255, 248, 198, 255), "spark_dk": (255, 226, 122, 255),
    "hl":        (255, 214, 120, 255),
    # river water (calm blue ramp + foam)
    "wa_hi":     (150, 205, 232, 255), "wa0": (110, 176, 214, 255), "wa_dk": (78, 140, 188, 255),
    "wa_foam":   (214, 238, 246, 255),
    # farmer + barn (used by the programmatic fallbacks when AI is unavailable)
    "skin":      (232, 196, 160, 255), "skin_dk": (196, 156, 120, 255),
    "barn_red":  (176, 66, 60, 255),   "barn_dk": (132, 46, 44, 255),
}

def _new(w=TILE, h=TILE):
    return Image.new("RGBA", (w, h), P["clear"])

def _h(x, y, seed):  # deterministic 0..96
    return (x * 7 + y * 13 + seed * 31) % 97

# ---------------------------------------------------------------- base tiles
def grass(variant):
    im = _new(); px = im.load()
    seed = 1 if variant == "a" else 2
    for y in range(TILE):
        for x in range(TILE):
            h = _h(x, y, seed)
            c = "g0"
            if h % 17 == 0: c = "g_lt"
            elif h % 23 == 5: c = "g_dk"
            px[x, y] = P[c]
    d = ImageDraw.Draw(im)
    # sparse blades (short strokes), gentle
    blades = [(5, 22), (11, 8), (18, 26), (24, 14), (28, 24), (8, 28), (21, 5)]
    if variant == "b":
        blades = [(6, 10), (14, 24), (23, 9), (27, 27), (10, 20), (19, 18)]
    for (bx, by) in blades:
        d.line([(bx, by), (bx, by - 2)], fill=P["g_sh"])
        im.putpixel((bx + 1, by - 1), P["g_hi"])
    if variant == "b":
        # a tiny flower
        im.putpixel((14, 14), P["flower_y"])
        for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
            im.putpixel((14 + dx, 14 + dy), P["flower_w"])
    return im

def path():
    im = _new(); px = im.load()
    for y in range(TILE):
        for x in range(TILE):
            h = _h(x, y, 3)
            c = "p0"
            if h % 13 == 0: c = "p_hi"
            elif h % 15 == 4: c = "p_dk"
            px[x, y] = P[c]
    d = ImageDraw.Draw(im)
    for (sx, sy) in [(8, 10), (20, 22), (25, 8), (12, 25)]:
        d.ellipse([sx, sy, sx + 2, sy + 1], fill=P["p_st"])
        im.putpixel((sx, sy), P["p_hi"])
    return im

def soil(season):
    im = _new(); d = ImageDraw.Draw(im)
    ramp = {
        "spring": ("s_sp_hi", "s_sp", "s_sp_dk"),
        "summer": ("s_su_hi", "s_su", "s_su_dk"),
        "autumn": ("s_au_hi", "s_au", "s_au_dk"),
        "winter": ("snow_hi", "snow", "snow_dk"),
    }[season]
    hi, mid, dk = (P[c] for c in ramp)
    d.rectangle([0, 0, 31, 31], fill=mid)
    # tilled furrows: dark trough + highlight lip
    for y in (6, 14, 22):
        d.rectangle([2, y, 29, y + 2], fill=dk)
        d.line([(2, y - 1), (29, y - 1)], fill=hi)
    if season == "autumn":
        for (x, y) in [(6, 10), (22, 18), (15, 26), (26, 8)]:
            im.putpixel((x, y), P["leaf_au"])
    if season == "winter":
        for (x, y) in [(5, 3), (12, 4), (20, 2), (27, 4), (9, 12), (24, 20)]:
            im.putpixel((x, y), P["snow_hi"])
    d.rectangle([0, 0, 31, 31], outline=dk)
    d.line([(1, 1), (30, 1)], fill=hi)
    return im

# ---------------------------------------------------------------- fences (wood, grain)
def _post(d, x, y0, y1):
    d.rectangle([x, y0, x + 3, y1], fill=P["w0"])
    d.line([(x, y0), (x, y1)], fill=P["w_hi"])
    d.line([(x + 3, y0), (x + 3, y1)], fill=P["w_sh"])
    for gy in range(y0 + 2, y1, 4):
        d.line([(x + 1, gy), (x + 2, gy)], fill=P["w_dk"])

def _rail_h(d, y):
    d.rectangle([0, y, 31, y + 4], fill=P["w0"])
    d.line([(0, y), (31, y)], fill=P["w_hi"])
    d.line([(0, y + 4), (31, y + 4)], fill=P["w_sh"])
    for gx in range(2, 31, 6):
        d.line([(gx, y + 1), (gx, y + 3)], fill=P["w_dk"])

def _rail_v(d, x):
    d.rectangle([x, 0, x + 4, 31], fill=P["w0"])
    d.line([(x, 0), (x, 31)], fill=P["w_hi"])
    d.line([(x + 4, 0), (x + 4, 31)], fill=P["w_sh"])
    for gy in range(2, 31, 6):
        d.line([(x + 1, gy), (x + 3, gy)], fill=P["w_dk"])

def fence(kind):
    im = _new(); d = ImageDraw.Draw(im)
    if kind in ("n", "s"):
        y = 6 if kind == "n" else 22
        _rail_h(d, y)
        for px_ in (4, 16, 27):
            _post(d, px_, y - 2, y + 7)
    elif kind in ("w", "e"):
        x = 6 if kind == "w" else 22
        _rail_v(d, x)
        for py_ in (4, 16, 27):
            _post(d, x - 1, py_ - 1, py_ + 1)  # small nubs read as cross-slats
            d.rectangle([x - 1, py_, x + 5, py_ + 1], fill=P["w_dk"])
    else:  # corner
        cy, cx = kind[0], kind[1]
        y = 6 if cy == "n" else 22
        x = 6 if cx == "w" else 22
        if cx == "w": d.rectangle([x, y, 31, y + 4], fill=P["w0"])
        else: d.rectangle([0, y, x + 4, y + 4], fill=P["w0"])
        if cy == "n": d.rectangle([x, y, x + 4, 31], fill=P["w0"])
        else: d.rectangle([x, 0, x + 4, y + 4], fill=P["w0"])
        _post(d, x, y - 2, min(31, y + 10))
        d.line([(x, y), (x + 3, y)], fill=P["w_hi"])
    return im

# ---------------------------------------------------------------- crops (32px, shaded)
def _bush(d, cx, cy, R, lobes):
    """A lumpy leafy bush: dark base disc + mid lobes around the rim + a highlight cap."""
    d.ellipse([cx - R, cy - R, cx + R, cy + R], fill=P["g_dk"])
    lr = R * 0.52
    for i in range(lobes):
        ang = 2 * math.pi * i / lobes - math.pi / 2
        lx = cx + math.cos(ang) * R * 0.55
        ly = cy + math.sin(ang) * R * 0.55
        d.ellipse([lx - lr, ly - lr, lx + lr, ly + lr], fill=P["g0"], outline=P["g_sh"])
    d.ellipse([cx - lr, cy - lr, cx + lr, cy + lr], fill=P["g0"])
    # highlight cap (top-left light)
    d.ellipse([cx - R * 0.5, cy - R * 0.75, cx + R * 0.15, cy - R * 0.05], fill=P["g_lt"])

def crop(stage, kind):
    im = _new(); d = ImageDraw.Draw(im)
    cx, cy = 16, 16
    if stage == 1:  # sprout: stem + two seed-leaves
        d.line([(cx, cy + 4), (cx, cy - 2)], fill=P["g_dk"])
        d.ellipse([cx - 4, cy - 3, cx, cy + 1], fill=P["g0"], outline=P["g_sh"])
        d.ellipse([cx, cy - 3, cx + 4, cy + 1], fill=P["g_lt"], outline=P["g_sh"])
        return im
    R = {2: 8, 3: 11, 4: 13}[stage]
    _bush(d, cx, cy, R, {2: 5, 3: 6, 4: 7}[stage])
    if stage == 4:
        if kind == "parsnip":  # leafy top + cream root crown peeking at the base
            d.ellipse([cx - 4, cy + 6, cx + 4, cy + 13], fill=P["cream"], outline=P["cream_dk"])
            d.line([(cx - 2, cy + 9), (cx + 2, cy + 11)], fill=P["cream_dk"])
            d.point([(cx - 1, cy + 8)], fill=P["g_lt"])
        elif kind == "cauliflower":  # bumpy white head filling the center
            d.ellipse([cx - 7, cy - 6, cx + 7, cy + 6], fill=P["cauli"], outline=P["cauli_dk"])
            for (dx, dy) in [(-3, -2), (3, -2), (0, 0), (-4, 2), (4, 2), (-1, 4), (2, 4)]:
                d.ellipse([cx + dx - 1, cy + dy - 1, cx + dx + 1, cy + dy + 1], fill=P["cauli_dk"])
            d.ellipse([cx - 5, cy - 5, cx - 1, cy - 1], fill=P["snow_hi"])
        else:  # berries scattered over the bush
            for (dx, dy) in [(-6, -2), (5, -4), (-2, 5), (6, 3), (1, -6), (-5, 3), (2, 1)]:
                bx, by = cx + dx, cy + dy
                d.ellipse([bx - 2, by - 2, bx + 2, by + 2], fill=P["berry"], outline=P["berry_dk"])
                im.putpixel((bx, by - 1), P["berry_hi"])
    return im

# ---------------------------------------------------------------- water (autotile) + bridge
def _water_base(im, d):
    for y in range(TILE):
        for x in range(TILE):
            h = _h(x, y, 7)
            c = "wa0"
            if h % 19 == 0: c = "wa_hi"
            elif h % 13 == 3: c = "wa_dk"
            im.putpixel((x, y), P[c])
    for (rx, ry) in [(6, 8), (18, 14), (10, 22), (24, 26), (14, 5)]:
        d.line([(rx, ry), (rx + 4, ry)], fill=P["wa_hi"])
        d.line([(rx + 1, ry + 1), (rx + 5, ry + 1)], fill=P["wa_dk"])

def water(kind):
    """Orthogonal autotile. `kind` in center | edge_{n,s,w,e} | corner_{nw,ne,sw,se}.
    Foam is drawn on the land side(s) so banks read cleanly against grass."""
    im = _new(); d = ImageDraw.Draw(im)
    _water_base(im, d)
    if kind == "center":
        sides = set()
    elif kind.startswith("edge_"):
        sides = {kind.split("_")[1]}
    else:  # corner_xx
        sides = set(kind.split("_")[1])  # "nw" -> {"n","w"}
    if "n" in sides:
        d.rectangle([0, 0, 31, 1], fill=P["wa_foam"]); d.line([(0, 2), (31, 2)], fill=P["wa_hi"])
    if "s" in sides:
        d.rectangle([0, 30, 31, 31], fill=P["wa_foam"]); d.line([(0, 29), (31, 29)], fill=P["wa_hi"])
    if "w" in sides:
        d.rectangle([0, 0, 1, 31], fill=P["wa_foam"]); d.line([(2, 0), (2, 31)], fill=P["wa_hi"])
    if "e" in sides:
        d.rectangle([30, 0, 31, 31], fill=P["wa_foam"]); d.line([(29, 0), (29, 31)], fill=P["wa_hi"])
    return im

def bridge(orient):
    """Wooden plank deck drawn over the water. `h` spans east-west (over a N-S river)."""
    im = _new(); d = ImageDraw.Draw(im)
    if orient == "h":
        d.rectangle([0, 5, 31, 26], fill=P["w0"])
        d.line([(0, 5), (31, 5)], fill=P["w_hi"]); d.line([(0, 26), (31, 26)], fill=P["w_sh"])
        for x in range(2, 31, 4):
            d.line([(x, 6), (x, 25)], fill=P["w_dk"])
        d.rectangle([0, 3, 31, 4], fill=P["w_dk"]); d.rectangle([0, 27, 31, 28], fill=P["w_dk"])
    else:
        d.rectangle([5, 0, 26, 31], fill=P["w0"])
        d.line([(5, 0), (5, 31)], fill=P["w_hi"]); d.line([(26, 0), (26, 31)], fill=P["w_sh"])
        for y in range(2, 31, 4):
            d.line([(6, y), (25, y)], fill=P["w_dk"])
        d.rectangle([3, 0, 4, 31], fill=P["w_dk"]); d.rectangle([27, 0, 28, 31], fill=P["w_dk"])
    return im

# ---------------------------------------------------------------- programmatic fallbacks (char/animals/barn)
# Used when the AI Images API is unavailable so the tileset is always complete + cohesive.
def char(direction):
    im = _new(); d = ImageDraw.Draw(im)
    # legs + boots
    d.rectangle([12, 24, 15, 29], fill=P["w_sh"]); d.rectangle([17, 24, 20, 29], fill=P["w_sh"])
    d.rectangle([12, 29, 15, 31], fill=P["ink"]); d.rectangle([17, 29, 20, 31], fill=P["ink"])
    # torso (green shirt) + arms
    d.rounded_rectangle([10, 15, 22, 25], radius=3, fill=P["g_dk"], outline=P["g_sh"])
    d.rectangle([8, 16, 10, 23], fill=P["g_dk"]); d.rectangle([22, 16, 24, 23], fill=P["g_dk"])
    # head
    d.ellipse([11, 6, 21, 16], fill=P["skin"], outline=P["skin_dk"])
    # straw hat (brim + crown)
    d.ellipse([8, 4, 24, 11], fill=P["cream"], outline=P["cream_dk"])
    d.ellipse([12, 2, 20, 8], fill=P["cream"], outline=P["cream_dk"])
    # face by facing
    if direction == "down":
        d.point([(14, 11)], fill=P["ink"]); d.point([(18, 11)], fill=P["ink"])
    elif direction == "left":
        d.point([(13, 11)], fill=P["ink"])
    elif direction == "right":
        d.point([(18, 11)], fill=P["ink"])
    else:  # up — back of head
        d.rectangle([12, 12, 20, 15], fill=P["w_sh"])
    return im

def animal(kind):
    im = _new(); d = ImageDraw.Draw(im)
    if kind == "chicken":
        d.ellipse([9, 12, 23, 27], fill=P["cauli"], outline=P["cauli_dk"])   # body
        d.ellipse([11, 7, 19, 15], fill=P["cauli"], outline=P["cauli_dk"])   # head
        d.polygon([(15, 4), (13, 8), (17, 8)], fill=P["berry"])              # comb
        d.polygon([(19, 10), (23, 11), (19, 12)], fill=P["leaf_au"])         # beak
        d.point([(16, 10)], fill=P["ink"])                                   # eye
        d.line([(13, 27), (13, 30)], fill=P["leaf_au"]); d.line([(19, 27), (19, 30)], fill=P["leaf_au"])
    elif kind == "cow":
        d.ellipse([7, 12, 25, 28], fill=P["snow"], outline=P["ink"])         # body
        d.ellipse([9, 15, 15, 21], fill=P["s_au"]); d.ellipse([18, 18, 23, 24], fill=P["s_au"])
        d.ellipse([11, 7, 21, 16], fill=P["snow"], outline=P["ink"])         # head
        d.ellipse([13, 11, 19, 16], fill=P["berry_hi"])                      # muzzle
        d.point([(14, 10)], fill=P["ink"]); d.point([(18, 10)], fill=P["ink"])
        d.line([(10, 28), (10, 31)], fill=P["ink"]); d.line([(22, 28), (22, 31)], fill=P["ink"])
    else:  # sheep
        d.ellipse([7, 11, 25, 28], fill=P["cauli"], outline=P["cauli_dk"])   # fluffy body
        for (bx, by) in [(10, 13), (15, 11), (20, 13), (9, 20), (22, 20), (15, 25)]:
            d.ellipse([bx - 3, by - 3, bx + 3, by + 3], fill=P["snow_hi"], outline=P["cauli_dk"])
        d.ellipse([12, 15, 20, 23], fill=P["ink"])                           # dark face
        d.point([(14, 18)], fill=P["snow_hi"]); d.point([(18, 18)], fill=P["snow_hi"])
        d.line([(11, 28), (11, 31)], fill=P["ink"]); d.line([(21, 28), (21, 31)], fill=P["ink"])
    return im

def barn():
    im = _new(64, 64); d = ImageDraw.Draw(im)
    d.polygon([(6, 26), (32, 6), (58, 26)], fill=P["w_sh"], outline=P["ink"])   # gable roof
    d.rectangle([6, 26, 58, 30], fill=P["ink"])
    d.rectangle([10, 30, 54, 58], fill=P["barn_red"], outline=P["ink"])         # walls
    d.line([(10, 30), (54, 30)], fill=P["cauli"])                               # trim
    d.rectangle([24, 38, 40, 58], fill=P["w_dk"], outline=P["ink"])             # doors
    d.line([(32, 38), (32, 58)], fill=P["ink"])
    d.line([(24, 38), (40, 58)], fill=P["w_hi"]); d.line([(40, 38), (24, 58)], fill=P["w_hi"])
    d.rectangle([28, 15, 36, 23], fill=P["cream"], outline=P["ink"])            # hayloft window
    d.line([(32, 15), (32, 23)], fill=P["cream_dk"])
    return im

# ---------------------------------------------------------------- fx + programmatic prop
def prop_sign():
    im = _new(); d = ImageDraw.Draw(im)
    _post(d, 14, 14, 30)
    d.rectangle([6, 6, 25, 17], fill=P["w0"], outline=P["w_sh"])
    d.line([(6, 6), (25, 6)], fill=P["w_hi"])
    for gy in (9, 12, 15):
        d.line([(8, gy), (23, gy)], fill=P["w_dk"])
    return im

def fx_rain():
    im = _new()
    for i in range(-32, 32, 6):
        for j in range(11):
            x, y = i + j, j * 3 + (i % 4)
            if 0 <= x < 32 and 0 <= y < 32:
                im.putpixel((x, y), P["rain"])
                if 0 <= x + 1 < 32 and 0 <= y + 1 < 32:
                    im.putpixel((x + 1, y + 1), P["rain_dk"])
    return im

def fx_highlight():
    im = _new(); d = ImageDraw.Draw(im)
    d.rounded_rectangle([1, 1, 30, 30], radius=4, outline=P["hl"], width=2)
    for i in range(3, 30, 5):
        im.putpixel((i, 1), P["clear"]); im.putpixel((1, i), P["clear"])
    return im

def fx_sparkle():
    im = _new(); d = ImageDraw.Draw(im)
    def star(cx, cy, s):
        d.line([(cx, cy - s), (cx, cy + s)], fill=P["spark"])
        d.line([(cx - s, cy), (cx + s, cy)], fill=P["spark"])
        im.putpixel((cx, cy), P["spark"])
        im.putpixel((cx, cy - s), P["spark_dk"]); im.putpixel((cx, cy + s), P["spark_dk"])
        im.putpixel((cx - s, cy), P["spark_dk"]); im.putpixel((cx + s, cy), P["spark_dk"])
    star(16, 15, 6); star(24, 8, 3); star(8, 22, 3)
    return im

# ---------------------------------------------------------------- AI sprites
def _trim(im):
    b = im.getchannel("A").point(lambda a: 255 if a > 24 else 0).getbbox()
    return im.crop(b) if b else im

def _pixelize(im, size, colors):
    im = _trim(im.convert("RGBA"))
    s = max(im.size)
    pad = Image.new("RGBA", (s, s), P["clear"])
    pad.paste(im, ((s - im.width) // 2, (s - im.height) // 2))
    small = pad.resize((size, size), Image.LANCZOS)
    a = small.getchannel("A").point(lambda v: 255 if v >= 128 else 0)
    rgb = small.convert("RGB").quantize(colors=colors, method=Image.MEDIANCUT).convert("RGBA")
    rgb.putalpha(a)
    return rgb

def _openrouter_image(key, prompt, attempts=4):
    """Generate a transparent PNG via OpenRouter's dedicated image endpoint, routed to gpt-image-1.
    Response shape mirrors OpenAI: {"data": [{"b64_json", "media_type"}], ...}. Retries transient
    network resets with backoff so one blip doesn't sink the whole run."""
    body = {
        "model": "openai/gpt-image-1", "prompt": prompt, "size": "1024x1024",
        "background": "transparent", "quality": "high", "output_format": "png", "stream": False,
    }
    last = None
    for i in range(attempts):
        try:
            req = urllib.request.Request(
                "https://openrouter.ai/api/v1/images",
                data=json.dumps(body).encode(),
                headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json",
                         "HTTP-Referer": "https://github.com/underworld14/daybar", "X-Title": "DayBar"},
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=300) as r:
                obj = json.loads(r.read())
            if "data" not in obj:  # surface API-level errors (billing, bad model) without retrying
                raise RuntimeError(f"openrouter error: {json.dumps(obj)[:200]}")
            return base64.b64decode(obj["data"][0]["b64_json"])
        except RuntimeError:
            raise
        except Exception as e:
            last = e
            wait = 4 * (i + 1)
            print(f"    openrouter attempt {i + 1}/{attempts} failed ({type(e).__name__}); retry in {wait}s")
            time.sleep(wait)
    raise last


def _generate_raw(prompt):
    """Raw PNG bytes for an AI sprite. Prefers OpenRouter (gpt-image-1) when OPENROUTER_API_KEY is set
    — direct OpenAI billing hit its hard limit — else falls back to the direct OpenAI Images API."""
    from dotenv import load_dotenv
    load_dotenv(ROOT / ".env")
    or_key = os.environ.get("OPENROUTER_API_KEY")
    if or_key:
        return _openrouter_image(or_key, prompt)
    from openai import OpenAI
    client = OpenAI()
    try:
        r = client.images.generate(model="gpt-image-1.5", prompt=prompt, size="1024x1024",
                                    background="transparent", output_format="png", quality="high", n=1)
    except Exception as e:
        print(f"  gpt-image-1.5 failed ({e}); falling back to gpt-image-1")
        r = client.images.generate(model="gpt-image-1", prompt=prompt, size="1024x1024",
                                    background="transparent", output_format="png", quality="high", n=1)
    return base64.b64decode(r.data[0].b64_json)


def ai_sprite(name, prompt, size):
    AI_CACHE.mkdir(parents=True, exist_ok=True)
    cache = AI_CACHE / f"{name}.png"
    if cache.exists():
        raw = cache.read_bytes()
    else:
        raw = _generate_raw(prompt)
        cache.write_bytes(raw)
        print(f"  generated {name}")
    return _pixelize(Image.open(io.BytesIO(raw)), size, colors=48)

_AI_OK = True

def ai_or_draw(name, prompt, size, fallback):
    """Try the AI Images API (using the `_ai_raw` cache); if it's unavailable — e.g. a billing
    limit — fall back to a programmatic drawing so the tileset is always complete. Once one call
    fails, later calls skip straight to the fallback (unless a cached raw exists)."""
    global _AI_OK
    cached = (AI_CACHE / f"{name}.png").exists()
    if cached:
        return ai_sprite(name, prompt, size)
    if not _AI_OK:
        return fallback()
    try:
        return ai_sprite(name, prompt, size)
    except Exception as e:
        print(f"  AI unavailable ({type(e).__name__}: {str(e)[:70]}) — drawing programmatic sprites from here")
        _AI_OK = False
        return fallback()

_FOX = ("Top-down pixel-art sprite of a small cozy farm companion: a round chubby orange fox cub "
        "with a cream belly and dark button eyes, seen slightly from above facing the viewer. "
        "16-bit SNES cozy farming game style, soft cel-shading, crisp clean dark outline, chunky "
        "readable silhouette. Centered, fully transparent background, no shadow, no ground, no "
        "border, no text. {mood}")

_FARMER = ("Top-down pixel-art sprite of a cute cozy farmer character: a small round person wearing "
           "a straw sun hat, a moss-green shirt and brown trousers, seen slightly from above, {facing}. "
           "16-bit SNES cozy farming game style, soft cel-shading, crisp clean dark outline, chunky "
           "readable silhouette, standing still with arms at sides. Centered, fully transparent "
           "background, no shadow, no ground, no border, no text.")

_FARMER_FACING = {
    "down":  "facing the viewer (south), face visible under the hat brim",
    "up":    "facing away from the viewer (north), showing the back of the hat and shoulders",
    "left":  "facing to the left (west) in profile",
    "right": "facing to the right (east) in profile",
}

_ANIMAL = {
    "chicken": "a plump little white hen with a red comb, small orange beak and orange feet",
    "cow":     "a small chubby cow with white and soft-brown patches and a gentle face",
    "sheep":   "a round fluffy cream sheep with a woolly coat and a small dark face",
}

def _walk_frames(idle):
    """Derive a 4-frame walk cycle (contact, passing-L, contact, passing-R) from one idle sprite:
    a gentle 1px vertical bob of the torso + an alternating horizontal shuffle of the lower legs."""
    top = idle.crop((0, 0, TILE, 22))
    legs = idle.crop((0, 22, TILE, TILE))
    frames = []
    for phase in (0, 1, 0, 2):
        f = _new()
        if phase == 0:
            f.alpha_composite(idle)
        else:
            f.alpha_composite(top, (0, -1))                       # bob torso up 1px
            f.alpha_composite(legs, (1 if phase == 1 else -1, 22))  # shuffle legs left/right
        frames.append(f)
    return frames

def _animal_ready(idle, kind):
    """Composite a small product glyph (egg / milk pail / wool puff) onto the idle animal."""
    im = idle.copy(); d = ImageDraw.Draw(im)
    if kind == "chicken":       # egg
        d.ellipse([23, 3, 29, 11], fill=P["cream"], outline=P["cream_dk"])
        im.putpixel((25, 5), P["snow_hi"])
    elif kind == "cow":         # milk pail
        d.rectangle([23, 4, 29, 10], fill=P["snow"], outline=P["w_dk"])
        d.rectangle([23, 4, 29, 5], fill=P["snow_hi"])
        d.line([(23, 4), (29, 4)], fill=P["w_dk"])
    else:                       # wool puff
        d.ellipse([22, 3, 30, 11], fill=P["snow_hi"], outline=P["cauli_dk"])
        for (dx, dy) in [(24, 5), (27, 5), (25, 8)]:
            im.putpixel((dx, dy), P["snow"])
    return im

# ---------------------------------------------------------------- build
def build():
    SRC.mkdir(parents=True, exist_ok=True)
    tiles = {}
    tiles["tile_grass_a"] = grass("a")
    tiles["tile_grass_b"] = grass("b")
    tiles["tile_path"] = path()
    for s in ("spring", "summer", "autumn", "winter"):
        tiles[f"plot_soil_{s}"] = soil(s)
    for k in ("n", "s", "w", "e", "nw", "ne", "sw", "se"):
        tiles[f"fence_{k}"] = fence(k)
    for st in (1, 2, 3, 4):
        tiles[f"crop_parsnip_top_{st}"] = crop(st, "parsnip")
        tiles[f"crop_cauliflower_top_{st}"] = crop(st, "cauliflower")
        tiles[f"crop_berry_top_{st}"] = crop(st, "berry")
    tiles["fx_rain_16"] = fx_rain()
    tiles["fx_highlight"] = fx_highlight()
    tiles["fx_sparkle"] = fx_sparkle()
    tiles["prop_sign"] = prop_sign()

    print("AI sprites (32px, from cache when present):")
    tiles["companion_idle_down"] = ai_sprite(
        "companion_idle_down", _FOX.format(mood="Calm neutral expression, sitting upright."), 32)
    tiles["companion_happy_down"] = ai_sprite(
        "companion_happy_down", _FOX.format(mood="Very happy, cheerful smile and bright eyes, ears perked up."), 32)
    tiles["companion_wilted_down"] = ai_sprite(
        "companion_wilted_down", _FOX.format(mood="Sad and droopy, sleepy half-closed eyes, ears down, muted."), 32)
    tiles["prop_home"] = ai_sprite(
        "prop_home",
        "Top-down pixel-art sprite of a tiny cozy cottage with a warm red-brown pitched roof, "
        "cream timber walls, a small round window and a wooden door, cute 16-bit cozy farming game "
        "style, soft cel-shading, crisp dark outline. Centered, fully transparent background, no "
        "ground, no shadow, no border, no text.", 64)

    # --- Farm v2: river water + bridge (programmatic) ---
    for k in ("center", "edge_n", "edge_s", "edge_w", "edge_e",
              "corner_nw", "corner_ne", "corner_sw", "corner_se"):
        tiles[f"water_{k}"] = water(k)
    tiles["prop_bridge_h"] = bridge("h")
    tiles["prop_bridge_v"] = bridge("v")

    # --- Farm v2: farmer character (AI idle x4 dirs -> derived 4-frame walk) ---
    for d in ("down", "up", "left", "right"):
        idle = ai_or_draw(f"char_idle_{d}", _FARMER.format(facing=_FARMER_FACING[d]), 32,
                          lambda d=d: char(d))
        tiles[f"char_idle_{d}"] = idle
        for i, frame in enumerate(_walk_frames(idle), start=1):
            tiles[f"char_walk_{d}_{i}"] = frame

    # --- Farm v2: animals (AI idle x3 -> derived ready variant) ---
    for kind, desc in _ANIMAL.items():
        idle = ai_or_draw(
            f"animal_{kind}_idle",
            f"Top-down pixel-art sprite of {desc}, seen slightly from above. 16-bit SNES cozy farming "
            "game style, soft cel-shading, crisp clean dark outline, chunky readable silhouette. "
            "Centered, fully transparent background, no shadow, no ground, no border, no text.", 32,
            lambda kind=kind: animal(kind))
        tiles[f"animal_{kind}_idle"] = idle
        tiles[f"animal_{kind}_ready"] = _animal_ready(idle, kind)

    # --- Farm v2: barn (AI, 64px 2x2 prop) ---
    tiles["prop_barn"] = ai_or_draw(
        "prop_barn",
        "Top-down pixel-art sprite of a cozy red barn with a dark gabled roof, big double doors and a "
        "small hayloft window, cute 16-bit cozy farming game style, soft cel-shading, crisp dark "
        "outline. Centered, fully transparent background, no ground, no shadow, no border, no text.", 64,
        lambda: barn())

    manifest = {"tile": TILE, "sprites": {}}
    for name, im in tiles.items():
        fn = f"{name}.png"
        im.save(SRC / fn)
        manifest["sprites"][name] = {"w": im.width, "h": im.height, "file": fn}
    (SRC / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    _contact_sheet(tiles).save(SRC / "_preview.png")
    print(f"\nWrote {len(tiles)} masters + manifest.json + _preview.png to {SRC}")

def _contact_sheet(tiles, zoom=5, cols=8, pad=6, label=12):
    from PIL import ImageFont
    names = list(tiles.keys())
    cellsz = 64 * zoom // 8 + pad * 2 + label  # normalize to ~ tile*zoom
    cell = TILE * zoom + pad * 2 + label
    rows = math.ceil(len(names) / cols)
    sheet = Image.new("RGBA", (cols * cell, rows * cell), (238, 234, 226, 255))
    d = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.load_default()
    except Exception:
        font = None
    for i, name in enumerate(names):
        r, c = divmod(i, cols)
        x0, y0 = c * cell, r * cell
        for yy in range(TILE * zoom):
            for xx in range(TILE * zoom):
                if ((xx // 10) + (yy // 10)) % 2 == 0:
                    sheet.putpixel((x0 + pad + xx, y0 + pad + yy), (214, 208, 196, 255))
        big = tiles[name].resize((TILE * zoom, TILE * zoom), Image.NEAREST)
        sheet.alpha_composite(big, (x0 + pad, y0 + pad))
        d.text((x0 + pad, y0 + pad + TILE * zoom + 1), name, fill=(50, 40, 30, 255), font=font)
    return sheet

if __name__ == "__main__":
    build()
