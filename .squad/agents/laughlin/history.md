# Laughlin — History

## Core Context

- **Project:** An Apple Watch fitness app integrated with ActiveLook AR glasses.
- **Role:** watchOS Dev
- **Joined:** 2026-05-14T18:30:31.655Z

## Learnings


## Summary

**Archive:** Pre-rc12 development (rc5-rc11) documented in history-archive.md. Key patterns:
- rc5–rc8: 4-release blank-screen saga (power-on, write serialization, queryID, cfgSet). All fixes load-bearing.
- rc9: Polish (rotation 0→2, holdFlush wrap). Went blank on bench.
- rc10: Bisect (reverted rotation, kept holdFlush). Text upside-down but readable.
- rc11: Tried rotation=4. Went blank. Directive issued: bundle version bump into feature PRs.

**Active sessions: rc12+**

### 2026-05-19T15:55:00Z — rc12: Four-Constant Coordinate Fix + Bundled-Bump Release Pattern Validated

**Work:** Shipped v0.3.0-rc12 fixing rotation=4 coordinate placement bug uncovered by textrotation forensic research. Updated 4 Layout constants (leftMargin 20→284, timeY 40→166, distanceY 120→86, paceY 200→6) in single PR #71 COMBINED with version bump (26→27), xcodegen regen, and Info.plist placeholder check — all committed together per Joe's bundled-bump directive.

**Outcome:** 154/154 Core tests pass. TestFlight upload succeeded. Tag v0.3.0-rc12 released.

**Pattern validation:** First release using Joe's bundled-bump pattern (feature + version bump in same PR, no separate follow-up bump PR). Cuts release cycle from 2 PRs to 1, no wasted merge round. End-to-end validated.

**Key learning:** Coordinate errors and firmware rejections have different diagnostic signatures. Off-screen clipping per spec §5.5.6 is silent (no 0xE2 error), but rotation + anchor corner interactions are subtle. When text goes blank, check bounding box vs. framebuffer bounds before escalating to firmware hypothesis.

---
