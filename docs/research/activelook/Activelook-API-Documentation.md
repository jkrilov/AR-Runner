# ActiveLook API Documentation

## Purpose
Authoritative specification of the BLE GATT protocol, frame format, command syntax, and UI design guidelines for implementing custom ActiveLook applications.

## Platform & License
- **Language/Platform:** Markdown documentation; protocol-agnostic (BLE GATT)
- **License:** Open source
- **Last Activity:** Repository is stable and maintained; primary reference for SDK implementations

## Activity Signal
**Active** — Core protocol reference. Updated when new firmware or API versions require documentation. No rapid iteration; stable spec.

## Key Folders/Files
- `ActiveLook_API.md` — 1000+ line specification covering:
  - BLE GATT architecture (Services/Characteristics UUIDs)
  - Command syntax (Graphics, Images, Layouts, Gauges, Animations, Pages, Configuration)
  - UI design best practices (erasing, text alignment, BLE transfer budgets)
  - Frame rate and rendering guidelines
- `resources/` — Diagrams (components, microdisplay, architecture)

## What We'd Lift/Reference/Learn
- **BLE protocol UUIDs & characteristics** — Custom service `0783B03E-8535-B5A0-7140-A304D2495CB7` with TX/RX/Control/Gesture/Touch endpoints
- **Bandwidth model** — Layouts & pre-configured objects minimize per-frame bytes; text updates ~20–100 bytes vs. full screen redraw
- **Rendering budget** — 304×256 pixels, 16 grey levels; frame updates must account for BLE packet sizes (~20 byte MTU chunks)
- **Layout system** — Pre-baked UI templates loaded at config time; live updates only change slot contents (efficient for workout HUD)
- **Gesture & sensor events** — Capacitive touch, gesture detection, ambient light available over BLE notifications

## Constraints & Architecture Notes
- **Frame format**: Fixed GATT characteristics (no streaming bandwidth guarantee); layout-based architecture favors static templates + dynamic text/images
- **Advertising & connection**:
  - 25ms advertising interval at startup; 250ms after 30s idle; power off after 3min
  - Manufacturer ID filter: devices ending in `0x08F2` are ActiveLook
  - Connection interval: 15–30ms preferred
- **Layout/Config Pipeline**: Configurations upload once at first connection; subsequent updates via commands reference pre-stored IDs
- **Heatshrink compression** available for large images (reduces bandwidth overhead)
- **Firmware version-dependent features** — Docs reference firmware compatibility (e.g., "≥ 4.2.X")

## Open Questions for AR-Runner
- Which pre-loaded layouts from the default `ALooK` config (v11) are suitable for workout metrics? Do we need custom layouts?
- What is the real-world BLE latency for 30+ updates/sec (e.g., live HR, cadence, pace)?
