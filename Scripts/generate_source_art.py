#!/usr/bin/env python3
"""
Authoring pipeline for the Focus Garden top-down tileset (16px logical grid).

HYBRID, all original / CC0:
  - Characterful sprites (companion moods, cottage) are generated UNIQUELY with the
    OpenAI Images API (gpt-image-1.5), then downscaled + remapped to a shared palette.
  - Base tiles, crops, fences and FX are drawn programmatically for pixel-perfect
    consistency on the same palette.

Outputs -> ThirdParty/garden-pixel-src/
  - one 1x master PNG per tile (16x16, except prop_home 32x32)
  - manifest.json  (name -> {w, h, file})
  - _preview.png   (contact sheet, 8x zoom, for review)

Raw AI generations are cached under ThirdParty/garden-pixel-src/_ai_raw/ (gitignored)
so reruns are free and deterministic. Requires OPENAI_API_KEY (loaded from .env).

Run:  ./.venv/bin/python Scripts/generate_source_art.py
"""
import base64
import io
import json
import math
import os
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "ThirdParty" / "garden-pixel-src"
AI_CACHE = SRC / "_ai_raw"
TILE = 16

# ---------------------------------------------------------------- shared palette
# Cozy, limited palette. Programmatic tiles pick from here by name; AI sprites are
# remapped onto the union of these colors so nothing drifts tonally.
P = {
    "clear":     (0, 0, 0, 0),
    "ink":       (43, 32, 26, 255),      # near-black outline
    "shadow":    (61, 46, 36, 255),
    # grass
    "grass":     (106, 168, 79, 255),
    "grass_lt":  (129, 190, 96, 255),
    "grass_dk":  (86, 138, 61, 255),
    "grass_tuft":(74, 121, 51, 255),
    # dirt / path
    "path":      (185, 137, 90, 255),
    "path_lt":   (205, 160, 112, 255),
    "path_dk":   (150, 106, 66, 255),
    # tilled soil (seasonal base)
    "soil_sp":   (138, 90, 58, 255),
    "soil_su":   (125, 79, 48, 255),
    "soil_au":   (111, 69, 38, 255),
    "soil_wi":   (205, 214, 220, 255),
    "soil_dk":   (92, 58, 36, 255),
    "leaf_au":   (196, 122, 54, 255),
    # wood (fence / sign)
    "wood_lt":   (202, 160, 106, 255),
    "wood":      (169, 126, 78, 255),
    "wood_dk":   (124, 90, 52, 255),
    # fox companion (also the AI remap anchors)
    "fox":       (232, 118, 58, 255),
    "fox_lt":    (246, 163, 90, 255),
    "fox_dk":    (200, 83, 31, 255),
    "cream":     (255, 230, 192, 255),
    "cream_dk":  (222, 191, 150, 255),
    # crops
    "veg_green": (106, 168, 79, 255),
    "veg_dark":  (74, 121, 51, 255),
    "parsnip":   (240, 226, 176, 255),
    "cauli":     (243, 241, 230, 255),
    "berry":     (214, 69, 80, 255),
    "berry_dk":  (168, 48, 60, 255),
    # cottage
    "roof":      (181, 83, 63, 255),
    "roof_dk":   (140, 60, 44, 255),
    "wall":      (216, 180, 131, 255),
    "window":    (143, 208, 232, 255),
    # fx
    "rain":      (168, 208, 240, 255),
    "rain_dk":   (127, 176, 224, 255),
    "spark":     (255, 246, 192, 255),
    "spark_dk":  (255, 226, 122, 255),
    "hl":        (255, 236, 130, 255),
}

def _new():
    return Image.new("RGBA", (TILE, TILE), P["clear"])

def _grid(rows, cmap):
    """Build a tile from a list of 16 strings, each char -> palette key (space=clear)."""
    im = _new()
    px = im.load()
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch != " " and ch in cmap:
                px[x, y] = P[cmap[ch]]
    return im

def _noise_fill(base, spec, seed):
    """Fill 16x16 with `base`, scattering deterministic accent pixels from spec=[(key,mod,rem)]."""
    im = _new()
    px = im.load()
    for y in range(TILE):
        for x in range(TILE):
            c = base
            h = (x * 7 + y * 13 + seed * 31) % 97
            for key, mod, rem in spec:
                if h % mod == rem:
                    c = key
                    break
            px[x, y] = P[c]
    return im

# ---------------------------------------------------------------- base tiles
def grass_a():
    return _noise_fill("grass", [("grass_lt", 11, 0), ("grass_dk", 13, 1)], seed=1)

def grass_b():
    im = _noise_fill("grass", [("grass_lt", 17, 0), ("grass_dk", 19, 2)], seed=2)
    d = ImageDraw.Draw(im)
    # a little tuft of taller grass
    for (x, y) in [(6, 11), (7, 10), (7, 12), (8, 9), (8, 11), (9, 11), (5, 12)]:
        im.putpixel((x, y), P["grass_tuft"])
    im.putpixel((8, 8), P["grass_dk"])
    return im

def path():
    im = _noise_fill("path", [("path_lt", 9, 0), ("path_dk", 12, 1)], seed=3)
    for (x, y) in [(4, 5), (11, 9), (7, 12), (12, 4)]:
        im.putpixel((x, y), P["path_dk"])
        im.putpixel((x + 1, y), P["path_lt"])
    return im

def soil(season_key):
    im = _new()
    d = ImageDraw.Draw(im)
    base = {"spring": "soil_sp", "summer": "soil_su", "autumn": "soil_au", "winter": "soil_wi"}[season_key]
    d.rectangle([0, 0, 15, 15], fill=P[base])
    # tilled furrows
    for y in (3, 7, 11):
        d.line([(1, y), (14, y)], fill=P["soil_dk"])
        d.line([(1, y - 1), (14, y - 1)], fill=P[base if season_key != "winter" else "soil_au"])
    if season_key == "winter":
        for x in range(0, 16, 2):
            im.putpixel((x, 1), P["cauli"])
    if season_key == "autumn":
        for (x, y) in [(3, 5), (12, 9), (8, 13)]:
            im.putpixel((x, y), P["leaf_au"])
    # rim
    d.rectangle([0, 0, 15, 15], outline=P["soil_dk"])
    return im

# ---------------------------------------------------------------- fences
def _fence_rail(orient):
    """orient in {n,s,w,e}. Wooden rail hugging that edge, transparent elsewhere."""
    im = _new()
    d = ImageDraw.Draw(im)
    if orient in ("n", "s"):
        y = 2 if orient == "n" else 11
        d.rectangle([0, y, 15, y + 2], fill=P["wood"])
        d.line([(0, y), (15, y)], fill=P["wood_lt"])
        d.line([(0, y + 2), (15, y + 2)], fill=P["wood_dk"])
        for px_ in (2, 8, 13):
            d.rectangle([px_, y - 1, px_ + 1, y + 3], fill=P["wood_dk"])
            im.putpixel((px_, y - 1), P["wood_lt"])
    else:
        x = 2 if orient == "w" else 11
        d.rectangle([x, 0, x + 2, 15], fill=P["wood"])
        d.line([(x, 0), (x, 15)], fill=P["wood_lt"])
        d.line([(x + 2, 0), (x + 2, 15)], fill=P["wood_dk"])
        for py_ in (2, 8, 13):
            d.rectangle([x - 1, py_, x + 3, py_ + 1], fill=P["wood_dk"])
    return im

def _fence_corner(cy, cx):
    """cy in {n,s}, cx in {w,e}: L rail meeting a corner post."""
    im = _new()
    d = ImageDraw.Draw(im)
    y = 2 if cy == "n" else 11
    x = 2 if cx == "w" else 11
    # rails
    if cx == "w":
        d.rectangle([x, y, 15, y + 2], fill=P["wood"])
    else:
        d.rectangle([0, y, x + 2, y + 2], fill=P["wood"])
    if cy == "n":
        d.rectangle([x, y, x + 2, 15], fill=P["wood"])
    else:
        d.rectangle([x, 0, x + 2, y + 2], fill=P["wood"])
    # corner post
    d.rectangle([x - 1, y - 1, x + 3, y + 3], fill=P["wood_dk"])
    im.putpixel((x, y), P["wood_lt"])
    return im

# ---------------------------------------------------------------- crops
def crop(stage, leaf, leaf_dark, fruit=None, fruit_style="dots"):
    im = _new()
    d = ImageDraw.Draw(im)
    cx, cy = 7.5, 9.0
    r = {1: 1.6, 2: 3.0, 3: 4.4, 4: 5.4}[stage]
    box = [cx - r, cy - r, cx + r, cy + r]
    d.ellipse(box, fill=P[leaf], outline=P[leaf_dark])
    # a few darker leaf speckles for texture
    for (dx, dy) in [(-1, -1), (2, 1), (-2, 2), (1, -2)]:
        x, y = int(cx + dx), int(cy + dy)
        if (x - cx) ** 2 + (y - cy) ** 2 <= r * r and stage >= 2:
            im.putpixel((x, y), P[leaf_dark])
    if stage == 4 and fruit:
        if fruit_style == "head":  # cauliflower: white head center
            d.ellipse([cx - 2.4, cy - 2.4, cx + 2.4, cy + 2.4], fill=P[fruit], outline=P["cream_dk"])
        elif fruit_style == "root":  # parsnip: cream root at base
            for (x, y) in [(7, 12), (8, 12), (7, 13), (8, 13)]:
                im.putpixel((x, y), P[fruit])
            im.putpixel((7, 13), P["cream_dk"])
        else:  # berries: scattered dots
            for (x, y) in [(6, 8), (9, 9), (7, 11), (10, 7)]:
                im.putpixel((x, y), P[fruit])
    return im

# ---------------------------------------------------------------- props (programmatic sign) + fx
def prop_sign():
    im = _new()
    d = ImageDraw.Draw(im)
    d.rectangle([7, 8, 8, 15], fill=P["wood_dk"])          # post
    d.rectangle([3, 4, 12, 9], fill=P["wood_lt"], outline=P["wood_dk"])  # board
    d.line([(4, 6), (11, 6)], fill=P["wood"])
    d.line([(4, 8), (10, 8)], fill=P["wood"])
    return im

def fx_rain():
    im = _new()
    for i in range(-16, 16, 5):
        for j in range(6):
            x = i + j
            y = j * 2 + (i % 3)
            if 0 <= x < 16 and 0 <= y < 16:
                im.putpixel((x, y), P["rain"])
            if 0 <= x + 1 < 16 and 0 <= y + 1 < 16:
                im.putpixel((x + 1, y + 1), P["rain_dk"])
    return im

def fx_highlight():
    im = _new()
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, 15, 15], outline=P["hl"])
    d.rectangle([1, 1, 14, 14], outline=P["hl"])
    # dashed inner to read as selectable
    for i in range(0, 16, 3):
        im.putpixel((i, 0), P["clear"])
        im.putpixel((0, i), P["clear"])
    return im

def fx_sparkle():
    im = _new()
    for (x, y, c) in [(8, 4, "spark"), (8, 5, "spark"), (8, 6, "spark_dk"),
                      (8, 8, "spark"), (8, 9, "spark"), (8, 10, "spark"), (8, 11, "spark"),
                      (6, 8, "spark"), (7, 8, "spark"), (9, 8, "spark"), (10, 8, "spark"),
                      (5, 8, "spark_dk"), (11, 8, "spark_dk"), (8, 3, "spark_dk"), (8, 12, "spark_dk"),
                      (12, 3, "spark"), (3, 12, "spark"), (12, 12, "spark_dk"), (3, 3, "spark_dk")]:
        im.putpixel((x, y), P[c])
    return im

# ---------------------------------------------------------------- AI sprites
_PAL_IMG = None
def _palette_image():
    global _PAL_IMG
    if _PAL_IMG is None:
        cols = [c for c in P.values() if c[3] == 255]
        flat = []
        for (r, g, b, _a) in cols:
            flat += [r, g, b]
        flat += [0, 0, 0] * (256 - len(cols))
        pim = Image.new("P", (1, 1))
        pim.putpalette(flat)
        _PAL_IMG = pim
    return _PAL_IMG

def _trim_alpha(im):
    bbox = im.getchannel("A").point(lambda a: 255 if a > 24 else 0).getbbox()
    return im.crop(bbox) if bbox else im

def _to_pixel(im, size):
    im = _trim_alpha(im.convert("RGBA"))
    s = max(im.size)
    pad = Image.new("RGBA", (s, s), P["clear"])
    pad.paste(im, ((s - im.width) // 2, (s - im.height) // 2))
    small = pad.resize((size, size), Image.LANCZOS)
    alpha = small.getchannel("A").point(lambda v: 255 if v >= 128 else 0)
    rgb = small.convert("RGB").quantize(palette=_palette_image(), dither=Image.NONE).convert("RGBA")
    rgb.putalpha(alpha)
    return rgb

def ai_sprite(name, prompt, size=16):
    AI_CACHE.mkdir(parents=True, exist_ok=True)
    cache = AI_CACHE / f"{name}.png"
    if cache.exists():
        raw = cache.read_bytes()
    else:
        from openai import OpenAI
        from dotenv import load_dotenv
        load_dotenv(ROOT / ".env")
        client = OpenAI()
        try:
            r = client.images.generate(model="gpt-image-1.5", prompt=prompt, size="1024x1024",
                                        background="transparent", output_format="png", quality="high", n=1)
        except Exception as e:
            print(f"  gpt-image-1.5 failed for {name} ({e}); falling back to gpt-image-1")
            r = client.images.generate(model="gpt-image-1", prompt=prompt, size="1024x1024",
                                        background="transparent", output_format="png", quality="high", n=1)
        raw = base64.b64decode(r.data[0].b64_json)
        cache.write_bytes(raw)
        print(f"  generated {name}")
    return _to_pixel(Image.open(io.BytesIO(raw)), size)

_FOX = ("Top-down pixel-art sprite of a small cozy farm companion: a round chubby orange fox cub "
        "with a cream belly and dark button eyes, seen slightly from above facing the viewer. "
        "16-bit SNES cozy farming game style, flat cel-shaded colors, crisp clean dark outline, "
        "chunky readable silhouette. Centered, fully transparent background, no shadow, no ground, "
        "no border, no text. {mood}")

# ---------------------------------------------------------------- build
def build():
    SRC.mkdir(parents=True, exist_ok=True)
    tiles = {}

    # programmatic base
    tiles["tile_grass_a"] = grass_a()
    tiles["tile_grass_b"] = grass_b()
    tiles["tile_path"] = path()
    for s in ("spring", "summer", "autumn", "winter"):
        tiles[f"plot_soil_{s}"] = soil(s)
    for o in ("n", "s", "w", "e"):
        tiles[f"fence_{o}"] = _fence_rail(o)
    for cy in ("n", "s"):
        for cx in ("w", "e"):
            tiles[f"fence_{cy}{cx}"] = _fence_corner(cy, cx)
    # crops
    for st in (1, 2, 3, 4):
        tiles[f"crop_parsnip_top_{st}"] = crop(st, "veg_green", "veg_dark", "parsnip", "root")
        tiles[f"crop_cauliflower_top_{st}"] = crop(st, "veg_green", "veg_dark", "cauli", "head")
        tiles[f"crop_berry_top_{st}"] = crop(st, "veg_dark", "berry_dk", "berry", "dots")
    # fx + programmatic prop
    tiles["fx_rain_16"] = fx_rain()
    tiles["fx_highlight"] = fx_highlight()
    tiles["fx_sparkle"] = fx_sparkle()
    tiles["prop_sign"] = prop_sign()

    # AI sprites (unique)
    print("AI sprites:")
    tiles["companion_idle_down"] = ai_sprite(
        "companion_idle_down", _FOX.format(mood="Calm neutral expression, sitting upright."))
    tiles["companion_happy_down"] = ai_sprite(
        "companion_happy_down", _FOX.format(mood="Very happy, cheerful smile and bright eyes, ears perked up."))
    tiles["companion_wilted_down"] = ai_sprite(
        "companion_wilted_down", _FOX.format(mood="Sad and droopy, sleepy half-closed eyes, ears down, muted."))
    tiles["prop_home"] = ai_sprite(
        "prop_home",
        "Top-down pixel-art sprite of a tiny cozy cottage with a warm red-brown pitched roof, "
        "cream timber walls, a small round window and a wooden door, cute 16-bit cozy farming game "
        "style, flat cel-shaded colors, crisp dark outline. Centered, fully transparent background, "
        "no ground, no shadow, no border, no text.", size=32)

    # write masters + manifest + preview
    manifest = {"tile": TILE, "sprites": {}}
    for name, im in tiles.items():
        fn = f"{name}.png"
        im.save(SRC / fn)
        manifest["sprites"][name] = {"w": im.width, "h": im.height, "file": fn}
    (SRC / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")

    _contact_sheet(tiles).save(SRC / "_preview.png")
    print(f"\nWrote {len(tiles)} masters + manifest.json + _preview.png to {SRC}")

def _contact_sheet(tiles, zoom=8, cols=8, pad=6, label=10):
    from PIL import ImageFont
    names = list(tiles.keys())
    cell = TILE * zoom + pad * 2 + label
    rows = math.ceil(len(names) / cols)
    sheet = Image.new("RGBA", (cols * cell, rows * cell), (238, 238, 240, 255))
    d = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.load_default()
    except Exception:
        font = None
    for i, name in enumerate(names):
        r, c = divmod(i, cols)
        x0, y0 = c * cell, r * cell
        # checker so transparency is visible
        for yy in range(TILE * zoom):
            for xx in range(TILE * zoom):
                if ((xx // 8) + (yy // 8)) % 2 == 0:
                    sheet.putpixel((x0 + pad + xx, y0 + pad + yy), (210, 210, 214, 255))
        big = tiles[name].resize((TILE * zoom, TILE * zoom), Image.NEAREST)
        sheet.alpha_composite(big, (x0 + pad, y0 + pad))
        d.text((x0 + pad, y0 + pad + TILE * zoom + 1), name, fill=(40, 40, 40, 255), font=font)
    return sheet

if __name__ == "__main__":
    build()
