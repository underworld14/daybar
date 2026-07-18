#!/usr/bin/env python3
"""
Slice/export pipeline for the Focus Garden tileset.

Consumes the masters + manifest.json produced by generate_source_art.py in
ThirdParty/garden-pixel-src/ and emits, from that single source of truth:

  1. Xcode imagesets  -> DayBar/Assets.xcassets/Garden/<name>.imageset/
       (1x master + @2x nearest-neighbor + Contents.json)
  2. Web sprite sheet -> site/assets/garden/garden-sheet.png
     + frame map       -> site/assets/garden/garden-frames.json

Dimensions are validated against the manifest so a stray master fails loudly.
This keeps the app and the landing site pixel-identical (no drift).

Run:  ./.venv/bin/python Scripts/generate_garden_pixels.py
"""
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "ThirdParty" / "garden-pixel-src"
ASSETS = ROOT / "DayBar" / "Assets.xcassets" / "Garden"
WEB = ROOT / "site" / "assets" / "garden"

CONTENTS_TMPL = {
    "images": [
        {"filename": "", "idiom": "universal", "scale": "1x"},
        {"filename": "", "idiom": "universal", "scale": "2x"},
        {"idiom": "universal", "scale": "3x"},
    ],
    "info": {"author": "xcode", "version": 1},
    "properties": {"template-rendering-intent": "original"},
}


def load_manifest():
    manifest = json.loads((SRC / "manifest.json").read_text())
    sprites = manifest["sprites"]
    imgs = {}
    for name, meta in sprites.items():
        im = Image.open(SRC / meta["file"]).convert("RGBA")
        if (im.width, im.height) != (meta["w"], meta["h"]):
            raise SystemExit(
                f"dimension mismatch for {name}: master is {im.size}, manifest says "
                f"({meta['w']},{meta['h']})"
            )
        imgs[name] = im
    return manifest, imgs


def emit_imagesets(imgs):
    ASSETS.mkdir(parents=True, exist_ok=True)
    for name, im in imgs.items():
        d = ASSETS / f"{name}.imageset"
        d.mkdir(parents=True, exist_ok=True)
        im.save(d / f"{name}.png")
        im.resize((im.width * 2, im.height * 2), Image.NEAREST).save(d / f"{name}@2x.png")
        contents = json.loads(json.dumps(CONTENTS_TMPL))
        contents["images"][0]["filename"] = f"{name}.png"
        contents["images"][1]["filename"] = f"{name}@2x.png"
        (d / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
    print(f"  wrote {len(imgs)} imagesets -> {ASSETS.relative_to(ROOT)}")


def emit_web_sheet(imgs, scale=4, sheet_w=256, pad=1):
    """Shelf-pack into a sheet at `scale` (nearest) and record logical-px frames."""
    WEB.mkdir(parents=True, exist_ok=True)
    order = sorted(imgs.keys(), key=lambda n: (-imgs[n].height, n))
    frames, x, y, shelf_h = {}, pad, pad, 0
    placed = []
    for name in order:
        im = imgs[name]
        w, h = im.width, im.height
        if x + w + pad > sheet_w:
            x = pad
            y += shelf_h + pad
            shelf_h = 0
        frames[name] = {"x": x, "y": y, "w": w, "h": h}
        placed.append((name, x, y))
        x += w + pad
        shelf_h = max(shelf_h, h)
    sheet_h = y + shelf_h + pad

    sheet = Image.new("RGBA", (sheet_w, sheet_h), (0, 0, 0, 0))
    for name, px, py in placed:
        sheet.alpha_composite(imgs[name], (px, py))
    sheet.resize((sheet_w * scale, sheet_h * scale), Image.NEAREST).save(WEB / "garden-sheet.png")

    (WEB / "garden-frames.json").write_text(
        json.dumps({"scale": scale, "tile": 16, "sheet": [sheet_w, sheet_h], "frames": frames},
                   indent=2, sort_keys=True) + "\n"
    )
    print(f"  wrote garden-sheet.png ({sheet_w*scale}x{sheet_h*scale}) + garden-frames.json -> {WEB.relative_to(ROOT)}")


if __name__ == "__main__":
    manifest, imgs = load_manifest()
    print(f"Loaded {len(imgs)} validated masters (tile={manifest['tile']}px)")
    emit_imagesets(imgs)
    emit_web_sheet(imgs)
    print("done.")
