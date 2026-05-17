# Discarded Sonnet Audit Spawns

**Timestamp:** 2026-05-17T00:22:43Z (UTC)  
**Record Type:** Transparency entry

## Context

Three audit agents were spawned at session start on `claude-sonnet-4.6` in violation of Joe's standing directive (encoded in `.squad/config.json`) that any code-touching agent must run on `claude-opus-4.7-1m-internal`. The coordinator failed to read `.squad/config.json` on session start and was not reminded until mid-session.

## Agents Discarded

- **Richards-1** (Sonnet 4.6, background, completed) — architecture/CI/dependency audit. Output overwritten by Richards-2.
- **Laughlin** (Sonnet 4.6, background, completed) — Swift/watchOS/HealthKit audit. Output overwritten by Laughlin-1.
- **Weiss** (Sonnet 4.6, background, completed) — ActiveLook/BLE audit. Partial findings merged into Weiss-1 per Weiss-1's note.

## Corrective Action

All three agents were re-spawned on `claude-opus-4.7-1m-internal` (Richards-2, Laughlin-1, Weiss-1). Final audit outputs are from the Opus versions.

## Lesson for Coordinator

`.squad/config.json` is a **Layer 0 persistent override** and must be read on every session start, alongside `team.md`, `routing.md`, and `registry.json`. This entry is recorded for transparency — no blame attached.
