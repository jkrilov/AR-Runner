# Session Log: watchOS CI Runtime Fix

**Timestamp:** 2026-05-14T21:26:21Z  
**Focus:** Resolving ARRunnerWatch CI build failure

## Summary

macOS-latest CI runner ships Xcode 16 with watchOS 11 SDK but not simulator runtime. App schemes probe for destinations and require the runtime; widget schemes don't, which is why ARRunnerWidgetsWatch passed but ARRunnerWatch failed.

Fixed via conditional `sudo xcodebuild -downloadPlatform watchOS` in matrix job, gated on watchOS destination strings. All matrix cells now green.

## Key Takeaway

Xcode SDKs (codesigned, in package) vs. simulators (downloaded separately) are independent. macOS CI pipelines need explicit platform downloads when app schemes trigger destination resolution.
