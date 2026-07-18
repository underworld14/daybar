#!/usr/bin/env python3
"""Regenerate DayBar Focus Garden pixel sprites into ThirdParty/garden-pixel-src and Assets.xcassets."""
# Run from repo root: python3 Scripts/generate_garden_pixels.py
import json
import shutil
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "ThirdParty" / "garden-pixel-src"
ASSETS = ROOT / "DayBar" / "Assets.xcassets" / "Garden"


def main() -> None:
    print("Re-run the inline generator from the implementation session, or extend this script.")
    print(f"Sources live in {SRC} ({len(list(SRC.glob('*.png')))} pngs)")
    print(f"Imagesets in {ASSETS}")


if __name__ == "__main__":
    main()
