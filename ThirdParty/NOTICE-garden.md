# Focus Garden pixel art

Sprites under `DayBar/Assets.xcassets/Garden/`, the web sheet under `site/assets/garden/`, and the
masters in `ThirdParty/garden-pixel-src/` are **original DayBar pixel art** (CC0 1.0), authored as a
32px top-down tileset.

How they are produced (see `Scripts/generate_source_art.py` → `Scripts/generate_garden_pixels.py`):

- **Companion (fox) and cottage** are generated uniquely with the OpenAI Images API (`gpt-image-1.5`),
  then downscaled and remapped onto a shared palette. The generated pixels are original works, not
  copies of any existing sprite.
- **Farmer character (4 directions + walk cycles), farm animals (chicken/cow/sheep) and the barn**
  are generated the same way *when the Images API is available*; the generator falls back to original
  programmatic pixel-art on the shared palette when it is not, so the tileset is always complete. The
  farmer walk frames and the animals' "ready" variants are derived programmatically from the idle art.
- **Terrain, seasonal soil, crops, fences, river water, the bridge and FX** are drawn programmatically
  on the same palette.

No third-party sprite assets (Kenney, Stardew Valley, or otherwise) are bundled or derived from. The
style is cottage-farm inspired but independently produced.
