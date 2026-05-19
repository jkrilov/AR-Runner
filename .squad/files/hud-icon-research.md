# HUD Icon Research — rc15 scoping outcome (SUPERSEDED by rc16)

> **Status: SUPERSEDED.** The rc15 deferral analysis below was correct
> for *custom* user-supplied artwork — but rc16 (Amber, 2026-05-19)
> discovered that the 4 icons the live HUD actually needs (chrono,
> heart-beat, distance, pace-avg) are **already preloaded** in the
> stock ALooK configuration and can be displayed via `imgDisplay`
> (cmdID 0x42) without any of the `cfgWrite`/`imgSave` upload
> plumbing this doc describes.
>
> **The flash ID of each preloaded icon is the leading number in
> its asset filename in the `ActiveLook/Activelook-Visual-Assets`
> repo.** Concretely for rc16:
> | Asset                  | Flash ID | Used for           |
> |------------------------|---------:|--------------------|
> | `40_chrono_40x40`      |     40   | Time (line 1)      |
> | `12_heart-beat_28x28`  |     12   | HR (line 1 right)  |
> | `9_distance_28x28`     |      9   | Distance (line 2)  |
> | `17_pace-avg_28x28`    |     17   | Avg Pace (line 3)  |
>
> The whole iceberg below remains accurate for future custom artwork
> (battery indicator with our own glyph, trophy animation, etc.) —
> if/when we need icons that ALooK doesn't ship, we'll have to do
> the `cfgWrite` + chunked upload work. But for icons that match
> the ALooK catalog, the path is: `cfgSet("ALooK")` (already in
> `connectFrames()` per rc8 PR #60) + `imgDisplay(id, x, y)`. Done.
>
> See `.squad/agents/amber/history.md` rc16 entry and
> `.squad/skills/activelook-hud-rendering/SKILL.md` rc16 section for
> the simplified path. The original rc15 deferral analysis is
> preserved below for completeness and for the future custom-asset
> work.
>
> --- ORIGINAL rc15 DEFERRAL ANALYSIS BELOW ---

# HUD Icon Research — rc15 scoping outcome

Source: Amber · 2026-05-19 · per rc15 task brief Phase 0 directive.

## TL;DR

**Icons are deferred to rc16+. rc15 ships layout-only fixes (mixed
fonts, 3-line redesign) that solve Joe's exact bench complaint
("fonts too large; text overlapping") without the icon pipeline.**

The icon upload pipeline (`imgSave` / `imgDisplay` / `imgList`) on
modern ActiveLook firmware (≥ 4.0.0) is a substantially larger
undertaking than the rc15 brief estimated, and trips the brief's
own escape hatch: *"If asset upload chunking turns out to be a
large undertaking (multi-MTU bitmap fragmentation with sequence
numbers), STOP and report — we'd want to consider deferring to
rc16 with just rc15 = layout-only fixes (no icons)."*

## Ground-truth from spec §4.7 and §5.5 (corrects the rc15 brief)

The brief's command IDs were wrong; the canonical modern IDs are:

| Brief        | Spec §4.7 (active) | Status                                  |
|--------------|--------------------|-----------------------------------------|
| `imgList` `0x42` | `imgList` `0x47` | brief used the wrong ID                 |
| `imgSave` `0x41` | `imgSave` `0x41` | ✓ ID matches, but **deprecated 0x41 also exists** at §4.16 — easy to mis-implement |
| `imgDisplay` `0x44` | `imgDisplay` `0x42` | brief used `imgStream`'s ID by mistake |

Active modern commands per spec §4.7:

| ID    | Command     | Notes                                                                 |
|-------|-------------|-----------------------------------------------------------------------|
| 0x41  | imgSave     | `u8 id; u32 size; u16 width; u8 format` (8 bytes for **first chunk**) |
| 0x42  | imgDisplay  | `u8 id; s16 x; s16 y`                                                 |
| 0x44  | imgStream   | one-shot display without saving                                       |
| 0x46  | imgDelete   | `u8 id` (0xFF = wipe all)                                             |
| 0x47  | imgList     | returns `u8 id, u16 h, u16 w` per image                               |

## What the brief understated

1. **`cfgWrite` is a HARD PREREQUISITE.** Spec §5.5 prelude:
   *"⚠ The `cfgWrite` command is required before images upload."*
   `imgSave` cannot land into the stock "ALooK" system config without
   `cfgWrite`-ing first. cfgWrite needs a 12-byte name, u32 version,
   u32 password, and battery > 5%. The stock ALooK config is marked
   `isSystem` (§4.14, `cfgList` response) and **cannot be deleted**;
   modifying it from a third party is unsupported.

2. **Either we overwrite ALooK (risky) or we install our own user
   config.** A new "ARRunner" user config gets its OWN namespace —
   which means **our app would lose access to the stock fonts 1–5**
   the moment we `cfgSet("ARRunner")` to display our icons. We'd
   need to copy fonts into our config too, which means the
   font-upload protocol (`fontSave` 0x50 — also chunked, also
   deprecated/replaced) becomes part of the work.

3. **Chunked binary upload over BLE.** Spec §5.5: *"The image data
   is sent in chunks with a maximum of 512 bytes. When sending
   images through BLE it is highly recommended to use the WRITE
   WITH RESPONSE Bluetooth protocol to make sure all data is
   properly saved."* Our adapter's `write(_:)` path uses
   `peripheral.writeValue(_:for:type:)` — we'd need to verify the
   `type:` is `.withResponse` for image chunks and add chunk-split
   logic. First-chunk-vs-continuation framing has different
   semantics; current encoder pattern doesn't model that.

4. **4bpp pixel packing.** Spec §5.5.1 ships a Python compression
   loop showing pixel-pair byte packing (`pixel[0]` in low nibble,
   `pixel[1]` in high nibble per byte, with dummy padding for odd
   widths). PNG-to-4bpp conversion requires either a build-time
   script (Python/Pillow → blob) or runtime CoreGraphics work in
   the watch target — neither exists today.

5. **`imgList` response parsing requires TX-notification infra.**
   Variable-length response (5 bytes per image) arrives on the
   `0xCB8` notify characteristic. Our adapter subscribes but
   doesn't currently parse application-command responses
   (battery is the only TX path consumed today, and only as a
   single-byte read). Wiring a queryID-correlated response demux
   is its own architectural surface.

6. **Rotation strategy is downstream of all of the above.** Per
   §4.7 `imgDisplay` accepts ONLY `id; x; y` — no rotation flag.
   The Engo 2 lens applies the same 180° point-symmetric flip to
   image-display as to text, so icons drawn from a "natural"
   bitmap will appear upside-down to the wearer. ActiveLook's
   demo-app pre-rotates assets at upload time
   (`Activelook-Visual-Assets` ships PNGs in lens-corrected
   orientation per the repo README). Recommendation when rc16
   lands: **option A** — pre-rotate PNGs 180° at build time via
   a `scripts/prepare-glasses-icons.py`; commit the rotated PNG
   to `ARRunnerWatch/Resources/GlassesIcons/`. Keeps runtime
   path simple.

## Why rc15 ships LAYOUT-ONLY and what it changes

rc14 bench feedback (Joe, verbatim): *"the fonts are too large and
text on each line is overlapping."* The overlap is a layout problem
solvable without icons by **mixing font sizes**:

| Line | Content              | Font | Why                                |
|------|----------------------|------|------------------------------------|
| 1    | Time (left) + HR (right) | 2 (38 px) | Two metrics share a line; font 2 widths fit both |
| 2    | Distance             | 3 (49 px) | Single metric — keep readability   |
| 3    | Avg Pace             | 3 (49 px) | Single metric — keep readability   |

Three lines instead of rc14's four leaves comfortable vertical
breathing room (≈ 30 px gaps wearer-space). No metric is dropped
from the field set Joe specified — only the icons are deferred.

The Time/HR shared line uses TWO `txt` commands at the same
`y_fb` but different `x_fb`: Time anchors at `x_fb = leftMargin`
(284, wearer-left ≈ 20); HR anchors at a new `liveHRX` (133,
wearer-left ≈ 170). Both topLR rotation=4, no encoder-surface
change.

## rc16 scoping reminders (for whoever picks up the icon work)

* Read spec §5.4 (configurations) end-to-end BEFORE writing code —
  the `cfgWrite` / `cfgFreeSpace` / `cfgList` / `cfgDelete`
  sequence is non-obvious and the wrong order will brick the
  device's view of our config.
* Decide ALooK-overwrite vs. new-user-config (and therefore font
  re-upload) up front. Recommend: prototype with `imgStream`
  (0x44 — one-shot, no `cfgWrite` needed) first to validate
  pixel packing + rotation visually, THEN take on the persistent
  `imgSave` path.
* Adapter changes: add `writeWithResponse` mode to `write(_:)`;
  add chunk-split helper bounded at 512 bytes; add TX-notification
  demux for response correlation.
* Build-time pipeline: `scripts/prepare-glasses-icons.py` →
  PNG → 180° rotate → 4bpp blob → ship as Swift `[UInt8]` literal
  in `GlassesIconAssets.swift`. Keeps adapter code free of PNG
  decoding.
* Asset source: <https://github.com/ActiveLook/Activelook-Visual-Assets>.
  Confirm asset orientation in the repo README before committing
  to the pre-rotate vs. ship-as-is decision.
* Battery indicator (v0.4.x), trophy animation (v0.4.0-rc2),
  gesture switcher all share the same upload-once-then-display
  pattern — the rc16 plumbing pays for itself across multiple
  future cards.

## Sources

* `ActiveLook/Activelook-API-Documentation` @ main —
  `ActiveLook_API.md` §4.7 (Images), §4.14 (Configurations),
  §5.4 (Configurations guide), §5.5 (Images guide), §4.16
  (Deprecated commands)
* `ActiveLook/Activelook-Visual-Assets` repo README — orientation
  convention for shipped PNGs
* AR-Runner — `RunningHUDFrame.swift`,
  `ActiveLookGlassesAdapter.swift` (current encoder + adapter
  surface)
* rc15 task brief (Joe, 2026-05-19) — explicit escape hatch for
  defer-icons-to-rc16
