# Focus Garden pixel art

Sprites under `DayBar/Assets.xcassets/Garden/`, the web sheet under `site/assets/garden/`, and the
masters in `ThirdParty/garden-pixel-src/` are **original DayBar pixel art** (CC0 1.0), authored as a
32px top-down tileset.

How they are produced (see `Scripts/generate_source_art.py` → `Scripts/generate_garden_pixels.py`):

- **AI-generated sprites** — the companion fox, the cottage, the **farmer (4 directions)**, the
  **farm animals (chicken / cow / sheep)** and the **barn** are generated uniquely with the OpenAI
  Images API (`gpt-image-1` / `gpt-image-1.5`), routed through **OpenRouter** (`openai/gpt-image-1`)
  when direct access is billing-limited. Each is then downscaled and remapped onto a shared palette;
  the generated pixels are original works, not copies of any existing sprite. The farmer's walk frames
  and the animals' "ready" (product) variants are derived programmatically from the idle art. If no
  image API is reachable, the generator falls back to original programmatic pixel-art so the tileset is
  always complete.
- **Terrain, seasonal soil, crops, fences, river water, the bridge and FX** are drawn programmatically
  on the same palette.

No third-party sprite assets (Kenney, Stardew Valley, or otherwise) are bundled or derived from. The
style is cottage-farm inspired but independently produced.
