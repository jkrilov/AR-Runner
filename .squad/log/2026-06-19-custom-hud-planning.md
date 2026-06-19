# 2026-06-19 — Custom HUD Layout Editor Planning (v0.6.1 / v0.7)

## Session Narrative

**Participants:** Weiss (AR Integration), Killian (UX Lead), Richards (Lead/Architect)  
**Scope:** Phone custom-HUD-layout editor planning + watch apply path + persistence/sync architecture.  
**Outcome:** Three coordinated planning docs consolidated into decisions.md, all open questions captured.

## Context Grounding

Founded on v0.6.0–0.6.2 foundation shipped earlier:
- `HUDLayout` Codable type (slots: [MetricKind?]) with `default(for: WorkoutType)` factory
- `HUDGridDefinition.standard4` — single bench-validated 4-slot geometry
- `WorkoutType` orthogonal model (activity × environment) with legacy-preserving Codable
- Live render path fully parameterized (`metricStrings` + `frames` + `RunningHUDFrame`)
- `MetricKind.isValid(for: WorkoutType)` validity matrix already exists

## Three Planning Phases

### Phase 1: Weiss (Rendering + Data Model)

**Verdict:** Constrained-custom via parameterized raw `txt` rendering.

Custom layouts ride the **raw-txt path** (already shipping), not the dormant curated `selectLayout(id:)` channel. No glasses-flash upload, no `CuratedLayoutCatalog` entry, no `layoutSave` needed. This avoids 3MB flash pool burn and keeps rendering in app-side code (testable, debuggable).

**New types** (Core-resident, pure Swift):
- `HUDLayoutCatalog` — wraps user customs only (system presets are code)
- `WorkoutLayoutDefaults` — maps WorkoutType → HUDLayout.id
- `HUDLayout.validated(for:)` — sanitize invalid metrics at apply time (slots → `nil`, render `--`)

**v1 Grid:** `standard4` only (fixed 4 slots). 2-slot and 6-slot deferred — each requires a bench cycle to lock coordinates (rc11→rc16 regression class).

**Watch apply:** Swap hardcoded `HUDLayout.default(for: sport)` with a resolver chain: `defaults.layoutID(for:)` → `catalog.layout(id:)` → else `HUDLayout.default(for:)`. Everything downstream unchanged. Dangling-reference safety: missing id falls through to built-in.

**Risk:** Slot 1 (secondary line-1-right) budget ≈4 font-2 glyphs. Long assignments collide with slot 0. Mitigation: editor width warning + guidance + 0.5-day worst-case bench spike to lock threshold.

### Phase 2: Richards (Persistence + Sync)

**Architecture:** App Group UserDefaults store + WCMessage additive cases (within v6, NOT a bump to v7).

**Key decision: Additive v6, NOT v7.** The WCMessage envelope stamps `currentSchemaVersion` on every encode. A global bump to 7 would make a v7 watch's `workoutTick` messages get rejected by a not-yet-updated v6 phone (regressing the live mirror). Staying at v6 with new `.layoutCatalog` / `.layoutDefaults` cases instead: v6 peers degrade gracefully to `.unknown` (ignored, no throw), link intact.

**Persistence:**
- Keys: `"hudLayoutCatalog"` / `"workoutLayoutDefaults"` in suite `group.com.arrunner.shared`
- New `Shared/Settings/HUDLayoutStore` wraps the App Group (mirrors `WorkoutTypePreference` pattern)
- Catalog + defaults each self-versioned (schema evolution isolated from wire)
- Max-cap proposal: 16 custom layouts (keeps blob a few KB, within `applicationContext` limits)

**Sync semantics:**
- Phone-authoritative (editing phone-only in v0.6.1)
- Full-catalog replace (diff/merge complexity not worth it)
- Reachable: immediate `sendMessageData` (snappy). Not reachable: `updateApplicationContext` or ordered `transferUserInfo`
- Watch persistence: decode + write to App Group on receipt, so next workout resolves customs with **no phone present**

**Phasing:**
- **Phase A (Persistence + Sync):** Can land BEFORE editor UI, fully shippable and inert for users with no customs. Owners: Richards (Core/messaging) + Laughlin (watch/phone plumbing).
- **Phase B (Editor UI):** Depends on Phase A. Killian (UX) + Weiss (validation) + Laughlin (phone impl).

### Phase 3: Killian (Phone Editor UX)

**Entry point:** Settings → "Glasses Layouts" disclosure row (new section between Workout and Units).

**Glasses Layouts screen (3 sections):**
1. **Presets (read-only):** 3 curated presets, rows show slot summary. Tap → read-only detail + "Duplicate" button. No delete.
2. **My Layouts (custom):** Tap → Layout Editor. Swipe-to-delete with confirm if assigned. `+` creates new custom (seeded by current default).
3. **Defaults per workout type:** 6 rows (one per WorkoutType). Tap → picker of {presets ∪ custom valid for that type}. Invalid layouts still selectable but show warning.

**Layout editor:**
- Fixed 4-slot grid, 2×2 visual layout, slots fillable or empty
- Tap-slot → modal metric picker (grouped Valid/Unavailable via `isValid(for:)`)
- Prevent duplicate metrics in two slots
- Auto-generate name from filled slots, user may override
- **Validity = warn, not block (v1)** — a layout can be assigned to multiple types, so hard validation at edit time is impossible. Invalid-for-type metrics render `--` at apply.

**Preview:**
- Inline amber-panel, 304×256 aspect, amber-on-black
- Synthetic values (pace 5:30/km, HR 152, dist 4.2 km, time 23:18) via real `unitLabel(for:in:)`
- Approximate hierarchy + correct metric order. Pixel-exact lens-flip deferred v0.7+.

**Apply:** Changes apply at NEXT workout (never mid-run). Footer: "Changes apply to your next workout."

**v1 scope (minimum lovable):**
- Glasses Layouts entry + list (presets, custom CRUD)
- 4-slot editor, empty slots, tap→metric-picker, no-duplicate rule, auto-name + override
- Per-type default assignment (6 rows)
- Validity warn (not block)
- Static preview
- Apply-at-next-workout + sync via Richards' Phase A

**Deferred (v0.7+):**
- Variable slot counts / 2-slot + 6-slot grids
- Freeform positioning + `layoutSave` + custom icons
- Pixel-exact lens-flip preview + real font metrics
- Live "push to glasses now"
- CloudKit cross-device sync
- Per-type editing of same layout

## Open Questions for jkrilov

(Consolidated from all three plans)

**Weiss:**
- OQ1: v1 = `standard4` only?
- OQ2: Slot-1 overflow — soft warn or hard-block save?
- OQ3: Custom-icon support confirmed deferred?
- OQ4: Per-type default fallback semantics?
- OQ5: Catalog sync transport — App-Group + WCMessage only, or CloudKit?
- OQ6: Custom layout per-type-scoped or global (assignable to multiple types)?

**Richards:**
- Q1: CloudKit in 0.6.1 (recommend no)?
- Q2: Max custom layouts cap (propose 16)?
- Q3: Confirm 4-slot only?
- Q4: One-directional sync (phone→watch) acceptable?
- Q5: Prune orphaned assignments on delete?
- Q6: Confirm additive-within-v6 over v7 bump?

**Killian:**
- Q1: Fixed 4-cell grid (recommend yes)?
- Q2: Unlimited custom layouts or cap?
- Q3: Auto-name-with-override or require name?
- Q4: Warn-and-allow or hard-block invalid assignments?
- Q5: Global layout or per-type instances?
- Q6: Approximate static preview or pixel-exact?
- Q7: Per-type reset + global "Restore all defaults" affordances?
- Q8: Settings disclosure row or dedicated tab?

## Dependencies

- **Weiss** ↔ **Killian:** Editor UX relies on HUDGridDefinition constants; preview must match `standard4` + lens-flip.
- **Richards** ← **Weiss:** Core data types + validated method.
- **Killian** ← **Richards:** Phase A (persistence + sync) unblocks Phase B (editor UI).
- **All** ← **jkrilov:** Open questions above.

## Next Steps

1. jkrilov reviews + answers open questions → decisions recorded
2. Richards implements Phase A (Core types, resolver, WCMessage v6.x cases, watch persistence)
3. Laughlin implements Phase A plumbing (watch resolution swap, phone send/reconcile)
4. Killian drafts editor UI (depends on Phase A complete)
5. Weiss validates geometry on Engo 2 (0.5-day bench spike for slot-1 threshold)
