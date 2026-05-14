# ActiveLook Visual Assets

## Purpose
Catalog of pre-built graphical objects (animations, images, fonts, layouts) included in the default `ALooK` system configuration (v11). Serves as reference for available assets and design guidelines.

## Platform & License
- **Language/Platform:** Asset library (GIF, PNG, BMP, JPEG formats); configuration metadata (JSON)
- **License:** Creative Commons Attribution-NonCommercial-NoDerivatives 4.0 (CC BY-NC-ND 4.0)
- **Last Activity:** Stable reference; updates accompany firmware releases

## Activity Signal
**Active** — Maintained as the official asset catalog. No rapid iteration; updates when new firmware adds animations or images.

## Key Folders/Files
- `anim/` — 14 pre-built animations (splash, dancing dots, ready, success, BT-lost, countdown, overlays for low battery/pause/session end)
- `images/` — 50+ icon/indicator bitmaps (battery, altitude, cadence, distance, HR, pace, calories, etc.); 28×28 px typical
- `config.json` — Descriptor for layout templates, font selections (SourceSansPro at 24/38/64/75/82 px), animation/image IDs
- `README.md` — Asset ID reference and usage notes

## What We'd Lift/Reference/Learn
- **Predefined layout templates** — Checkout available layouts in `config.json` for workout HUD patterns
- **Icon library** — 50+ sport-relevant icons (cadence, HR, distance, pace) ready to use; reduces custom asset creation burden
- **Font sizes** — Five SourceSansPro variants (24–82 px); font selection tied to layout at render time
- **Animation patterns** — "Ready" (loop), "Success" (one-shot), "Low Battery" (loop overlay) provide UX templates
- **Layout constraint model** — Layouts defined in `config.json`; use `cfgSet("ALooK")` to load, then reference layout by ID in commands

## Constraints & Architecture Notes
- **Fixed asset set** — Default `ALooK` config includes specific animations and images; custom assets require Config-Generator to build a custom config
- **Licensing caveat** — CC BY-NC-ND means visual assets are **non-commercial use only**; custom AR-Runner assets may need separate licensing if commercial
- **Layout templating** — Layouts defined once per config; live updates change *content* of slots (e.g., HR number in a text slot), not structure
- **Bitmap format** — 1-bit and 4-bit per pixel images supported; 4-bit allows 16 grey levels matching display capability
- **Asset IDs are config-specific** — If AR-Runner uses a custom config, IDs in this catalog won't be valid (must regenerate with Config-Generator)

## Open Questions for AR-Runner
- Are the default `ALooK` layouts sufficient for a workout HUD, or do we need a custom config?
- Can we legally use these assets given CC BY-NC-ND? Does "commercial use" apply to a fitness app with optional monetization?
