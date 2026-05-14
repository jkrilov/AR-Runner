# ActiveLook Config-Generator

## Purpose
Python-based tool for building custom ActiveLook configurations (graphics, layouts, animations, fonts, images) that can be uploaded to glasses at app initialization.

## Platform & License
- **Language/Platform:** Python 3; uses OpenCV, pyserial, bleak, heatshrink2, colormath
- **License:** Creative Commons Attribution-NonCommercial-NoDerivatives 4.0 (CC BY-NC-ND 4.0)
- **Last Activity:** Stable tool; maintained alongside API updates

## Activity Signal
**Active** — Supported tool for developers building custom visual configurations. Updates align with new glasses models and firmware.

## Key Folders/Files
- `configGenerator.py` — Main script; interactive menu: "Save in file" (binary export) or "USB live test" (direct glasses upload)
- `cfgDescriptor/` — Template directories; each subdirectory defines one config:
  - `demo/` — Example to duplicate
  - `anim/` — GIF/PNG/BMP/JPEG images for animations
  - `img/` — GIF/PNG/BMP/JPEG for static images
  - `config.json` — Metadata: config name, version, key, fonts, layouts, images, animations, pages
- `README.md` — Setup and usage guide

## What We'd Lift/Reference/Learn
- **Asset pipeline** — Convert GIF/PNG to bitmaps, apply Heatshrink compression, assign IDs (must be unique within config)
- **Layout definition** — JSON syntax for composing layouts from shapes (circle, line, rect, point), text, images, animations
- **Config distribution** — Two upload paths:
  - Binary file (built with "Save in file") → app loads via SDK and uploads over BLE at first connection
  - USB/BLE live test (built in with "USB live test" → direct glasses upload)
- **Font generation** — Specify font size and ASCII subset; tool generates font bitmaps for download
- **Color & contrast** — White on black advised for best contrast on monochrome display

## Constraints & Architecture Notes
- **Python + external dependencies** — Requires pip install of OpenCV, bleak, heatshrink2, etc.; Windows-specific setup instructions
- **One-time upload per app session** — Config sent during first glasses connection; changes require restart + re-upload
- **Config size matters** — Larger configs take longer to upload; recommendations to crop images, avoid duplication
- **Heatshrink compression** — Large bitmaps auto-compressed to reduce upload bandwidth; decompression on glasses side is automatic
- **Licensing constraint** — CC BY-NC-ND on the tool itself; custom configs inheriting this license may have legal implications for commercial use
- **Binary format** — Output is Heatshrink-compressed binary; SDK handles decompression when uploading

## Integration Path Recommendations
- **Build-time vs. Runtime config**:
  - *Option A*: Embed config binary in app bundle, load at startup (simple, version-controlled)
  - *Option B*: Authoring UI in phone app + Config-Generator at runtime (flexibility, complexity)
- **For AR-Runner**:
  - Likely want custom layouts tailored to workout metrics (HR, cadence, pace, elevation)
  - Consider asset toolchain: how to integrate Config-Generator into CI/CD to build config from source (Figma/SVG → PNG → config binary)

## Open Questions for AR-Runner
- Should config be static (baked at app build time) or generated/customizable at runtime?
- How to integrate Config-Generator with existing CI/CD pipeline (GitHub Actions)?
- What's the process for adding sport-specific layouts (running, cycling, climbing)?
