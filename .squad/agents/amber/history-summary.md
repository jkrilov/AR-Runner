# Amber — History Summary

## Core Context
- **Project:** Apple Watch fitness app integrated with ActiveLook AR glasses
- **Role:** QA & Fitness Domain
- **Joined:** 2026-05-14T18:30:31.658Z

## Active Release Cycles (rc13–rc17)

### Key Patterns Across Releases

**Actor Reentrancy & Async Serialization (rc13):**
- `Task { await foo() }` from MainActor-isolated timer is NOT a serialization boundary; spawned tasks join the cooperative pool
- **Fix:** `await` multi-frame BLE sequences directly from the caller to prevent interleaving of holdFlush states
- holdFlush prologue/epilogue contract spans entire multi-frame burst; actor-level per-write locks don't protect this span

**Defensive Lifecycle Reset (rc13 + ongoing):**
- `needsHUDPowerOn` must be reset per-workout (not just per-connect) to ensure first per-tick frame re-asserts power
- When multi-state callers queue BLE sequences, the ViewModel caller MUST serialize; don't rely on actor internals

**Coordinate-System Foundations (rc14–rc16):**
- Real ALooK font heights: F1=24 / F2=38 / F3=64 / F4=75 / F5=82 (per Visual-Assets README, NOT spec §5.9 generic table)
- rc16 formula: `y_fb = 255 − wearer_top` (no font-height subtraction); empirically pinned via rc15 bench data
- Different surfaces can use different fonts (splash font 2 fits 15-char string; run HUD font 3 is more readable)

**Hardware Lifecycle Boundaries (rc17):**
- `HKWorkoutSession.end()` is a hard cliff; all BLE/runtime work must complete BEFORE it returns
- OS suspends processes microseconds after HK session release; `bluetooth-central` UIBackgroundModes keeps radio warm but not process alive
- Do NOT eagerly teardown hardware sessions when user is still reading results; user-explicit disconnect is the right boundary

**Icon / Asset Strategy (rc15–rc16):**
- Always check `ActiveLook/Activelook-Visual-Assets` preloaded catalog BEFORE scoping custom image upload pipeline
- Preloaded icons (40_chrono_40x40, 12_heart-beat_28x28, etc.) skip `cfgWrite`/`imgSave` entirely; `imgDisplay(id, x, y)` is one BLE write
- rc15's escape hatch (defer icons to rc16) was correct call; the spec-research phase proved upload overhead wasn't justified

**Test Coverage Discipline:**
- Exhaustive-switch after enum additions is mandatory; compiler catches all call-sites
- Layout geometry tests MUST pin coords to prevent silent drift; a passing test under wrong assumptions is dangerous
- String-backed Codable enum cases MUST lock rawValue in tests (especially across process boundaries like WCSession)

**Release Process (bundled-bump pattern):**
- Version bump (`CURRENT_PROJECT_VERSION`) ships IN THE SAME PR as feature code
- `xcodegen generate` + Info.plist placeholder check runs in same commit
- Reduces release cycle from 2 PRs to 1; stabilized pattern across Laughlin (rc12) and Amber (rc13–16)

## Archive

Full technical details from 2026-05-14 through 2026-05-15 (scaffold validation, multi-agent merge, contract tests, Linux CI) are in `history-archive.md`.

Detailed release notes from rc13–rc17 cycles (bug root-causes, test assertions, frame sequences) are in `history-pre-summary.md` (written 2026-05-19, pre-summarization).

---

## Cross-Agent Dependencies

**For Laughlin (coordinate system owner):**
- Finish-screen Y anchors (timeY=166, distanceY=86) need revalidation under rc16 formula `y_fb = 255 − wearer_top`
- They work on bench but may have font-height drift; a 30-minute pass closes this known gap

**For Weiss (BLE adapter owner):**
- Per-burst BLE serialization is now enforced at the ViewModel caller (not the adapter)
- ActiveLookGlassesAdapter reentrancy is documented; if future work spawns multiple concurrent callers, revisit burst-locking strategy

**For Richards (architecture):**
- Font-metrics table should be extracted to typed code (currently prose comments)
- Layout will benefit from surface-scoped siblings (SplashLayout / LiveHUDLayout / FinishLayout) once third HUD screen lands

---

Generated 2026-05-19 (summarization pass to reduce 33KB → ~8KB while retaining load-bearing patterns).
