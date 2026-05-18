# Skill: SVG → opaque PNG on macOS without librsvg

## When to use this

You need to convert a vector source (SVG) to a raster PNG on a Mac (local
dev or GitHub-hosted macOS runner) and the asset must be **fully opaque**
(no alpha) — typically because it's destined for an App Store icon, an
asset catalog `AppIcon.appiconset`, or another context that rejects
transparency.

You'd normally reach for `rsvg-convert` (from `librsvg`) or `cairosvg`, but
neither is preinstalled on stock macOS or GitHub `macos-latest` runners,
and adding a brew/pip dependency is overkill for a one-shot icon export.

## The pattern

Use only tools that ship with macOS: `qlmanage` (QuickLook) to rasterize
the SVG, then `sips` to flatten alpha by round-tripping through JPEG.

```bash
# 1. Rasterize SVG via QuickLook thumbnail at the size you want.
qlmanage -t -s 1024 -o . AppIcon-1024.svg
# qlmanage emits "<input>.png" — rename to your final name.
mv AppIcon-1024.svg.png AppIcon-1024.png

# 2. Verify dimensions / alpha.
sips -g pixelWidth -g pixelHeight -g hasAlpha AppIcon-1024.png

# 3. Flatten alpha. sips can't directly strip alpha from PNG, but
#    round-tripping through JPEG (which has no alpha channel) and back
#    to PNG produces an opaque PNG. Use formatOptions 100 to avoid
#    JPEG compression loss for the intermediate.
sips -s format jpeg -s formatOptions 100 AppIcon-1024.png --out _tmp.jpg
sips -s format png _tmp.jpg --out AppIcon-1024.png
rm _tmp.jpg

# 4. Confirm hasAlpha is now "no".
sips -g hasAlpha AppIcon-1024.png
```

## Why it works

- `qlmanage -t` invokes the QuickLook generator for the file type and
  writes the resulting thumbnail at the requested pixel size. The macOS
  SVG QuickLook plugin handles standard SVG 1.1 features (gradients,
  paths, transforms, opacity) well enough for icon-quality output.
- `sips` is the macOS image utility. It refuses to clear alpha on PNG in
  place (`--setProperty hasAlpha false` is a no-op for PNG), but the
  format-conversion path through JPEG forcibly drops the alpha channel
  because JPEG can't represent it. Converting back to PNG yields an
  RGB-only PNG, which is what App Store Connect wants.

## Caveats

- The SVG must paint its own background — qlmanage doesn't add one. Any
  uncovered area becomes black (and stays black after the alpha flatten).
- Very complex SVG features (filters, foreignObject, embedded fonts that
  aren't installed) may render incorrectly via QuickLook. Stick to paths,
  gradients, and basic shapes for icon work.
- For batch / non-icon work where you'd want a programmable pipeline,
  prefer `brew install librsvg` + `rsvg-convert`. This skill is for the
  "one icon, no new dependencies" case.

## Seen in

- `Assets/AppIcon/AppIcon-1024.svg` → `AppIcon-1024.png` for the
  AR-Runner iPhone app icon (rc11 Apple validation fix).
