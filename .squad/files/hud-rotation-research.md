# Rotation Forensics — rc12 Fix

Source: forensic research agent (textrotation) · 2026-05-19

## TL;DR

**Use `rotation = 4` (`topLR`) AND change `leftMargin` from 20 to 284 AND adjust all three y-coordinates** (timeY→166, distanceY→86, paceY→6). The rc11 blank was a **coordinate error, not a firmware rejection**: `topLR` places its anchor at the **top-right** of the text block and extends text **leftward**; at x=20 the entire string lands at negative x, off-screen and silently clipped. The spec's own §5.7 example places `rotation=4` at x=152 (center) and ALooK system layout #10 places it at x=238 — both high x values, text growing leftward.

## Key facts (evidence-cited)

- All 8 rotation values (0-7) are in the official SDK enum (`ActiveLookTypes.swift:41-50`) — the prior skill note "only 0 and 4 are documented" was wrong
- `topLR` (4): glyphs rendered 180°-rotated on framebuffer; anchor at top-right; text grows LEFTWARD and DOWNWARD
- Engo 2 lens applies 180° point-symmetric flip → x_wearer = 303 − x_fb, y_wearer = 255 − y_fb
- 180°-flipped glyphs + 180° lens flip = 360° = right-side-up to wearer ✓
- Font 3 height = 49 px (spec §5.9 font table); typical run strings ~100-260 px wide
- Spec §5.5.6: off-screen coords are silently clipped (no error) — fully explains rc11 blank
- ALooK system layout #10 (the time layout demo app uses) ships with rotation=4, textX=238 — confirms 4 is the canonical value

## Fix for rc12

In `ARRunnerCore/Sources/ARRunnerCore/Glasses/RunningHUDFrame.swift` — `Layout` enum:

```swift
public static let rotation:  UInt8 = 4   // unchanged — topLR is correct
public static let leftMargin: Int16 = 284 // was 20 — anchor at right edge; text extends left
public static let timeY:      Int16 = 166 // was 40  — fb y inverted by lens, +49 for top-of-glyph anchor
public static let distanceY:  Int16 = 86  // was 120
public static let paceY:      Int16 = 6   // was 200
```

Derivation: anchor `x_fb = 303 − 20 = 283 ≈ 284` (puts left edge of text at x_wearer=20); `y_fb = 255 − T − 49 = 206 − T` for each T = target wearer-visible y (40, 120, 200).

## Demo-app patterns

- `LayoutCommandsViewController.swift:55-57` → `displayTimeLayout()` calls `cfgSet("ALooK")` + `layoutDisplay(id:10)` — uses ALooK layout #10 which has rotation=4 baked in
- `GraphicsCommandsViewController.swift:82-84` → demo `drawText()` uses `rotation=.bottomRL` (0) at x=102 (well clear of left edge) — works because bottomRL anchors at bottom-LEFT
- Custom "DemoApp" layout (`LayoutCommandsViewController.swift:124-137`) uses rotation=0 — different choice, but at center-screen coords

## Fallback ladder if rc12 still blanks

1. **Diagnostic test**: send single `txt(x:152, y:128, rotation:4, font:3, color:15, "test")` from a dev path. If still blank at center, firmware hypothesis is in play.
2. **rotation=5 (topRL) at x=20**: same 180° glyph; anchor at TOP-LEFT, text grows rightward. Through lens → text appears right-aligned but readable.
3. **rotation=5 at x=284**: x mirrored; through lens → left-aligned.
4. Send `rdDevInfo(id:10)` (spec §4.15) to read declared optical orientation; file ActiveLook issue if firmware is the culprit.

## Why rotation=0 read upside-down (rc8/rc10)

bottomRL anchors at bottom-LEFT and renders upright glyphs. At x=20: text grows rightward, visible. Lens flips upright glyphs → upside-down to wearer. Exactly what Joe observed.

## Sources

- `ActiveLook/ios-sdk` @ a39839f — `Sources/Classes/Public/ActiveLookTypes.swift:41-50` (TextRotation enum)
- `ActiveLook/Activelook-API-Documentation` @ main — `ActiveLook_API.md` §5.5.6, §5.7, §5.9, §5.10
- `ActiveLook/demo-app` @ da0ddda — `ios/example/{GraphicsCommandsViewController.swift, FontCommandsViewController.swift, LayoutCommandsViewController.swift}`
- AR-Runner HEAD — `RunningHUDFrame.swift:39,53-54`
