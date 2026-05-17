# Session Log — Full Codebase Audit (2026-05-16/17)

**Timestamp:** 2026-05-17T00:22:43Z (UTC)  
**Requested by:** Joe Krilov  
**Scope:** 2026-current best-practices audit across architecture, watchOS/Swift/HealthKit, and ActiveLook/BLE  
**Model:** claude-opus-4.7-1m-internal (after coordinator corrective re-spawn)

## Summary

Three-agent parallel audit run on Opus 4.7 (1M context) to assess current codebase health against 2026 best practices. Comprehensive read-only review of all production source, test scaffolds, CI workflows, and dependency currency.

## Findings Snapshot

### P1 Bugs (4)
1. HealthKit energy samples mis-classified as `.duration` — live kcal never reaches UI.
2. `StartWorkoutIntent.perform()` is a no-op TODO — widget Start button non-functional.
3. HUD per-tick field-update path unwired from workout pipeline — glasses silent post-connect.
4. Placeholder device IDs (0x01–0x03) in `CuratedLayoutCatalog` blocking real hardware test.

### P2 Hygiene (4)
1. Deprecated HK aggregate properties (`totalDistance`, `totalEnergyBurned`) in active use.
2. Tooling pins ~12 months stale (Xcode 16.4, Swift 6.0 vs. GA Xcode 17, Swift 6.2).
3. XCTest shipped inside production app target (compile-guarded, safe, but a smell).
4. CodeQL coverage asymmetric (ARRunnerWatch only; Phone target excluded).

### Modernization / Debt (3)
1. Preview constructs real `HealthKitWorkoutSubstrate` (risky for eager-init futures).
2. `CBCentralManager` re-instantiated on every reconnect (up to 30 stale managers per workout).
3. Documentation drift: copilot-instructions.md claims greenfield while ~30 files committed.

### Module Layering ✅
Confirmed clean — ARRunnerCore is platform-pure (Foundation-only), verified across 22 source files. Linux CI job enforces boundary.

## Audit Documents

- `.squad/audits/2026-05-16-richards-architecture.md` (13165 bytes)
- `.squad/audits/2026-05-16-laughlin-watchos.md` (15640 bytes)
- `.squad/audits/2026-05-16-weiss-ar-ble.md` (17157 bytes)

## Decisions Captured

Three new decision entries merged into `.squad/decisions.md`:
1. User directive: Opus 4.7 (1M) for code-touching agents (Joe's restatement of standing config).
2. HealthKit deprecated API migration plan (Laughlin).
3. Layout bake step blocking hardware use + Config-Generator workflow (Weiss).

## Note

Coordinator initially spawned all three agents on Sonnet 4.6 in violation of Joe's standing directive (encoded in `.squad/config.json`). Mid-session correction prompted full re-spawn on Opus 4.7. All agents are code-touching → must run on 1M-context Opus per policy.
