# AR-Runner — Copilot Instructions

## Project status

This repository is **greenfield** — no application source code exists yet. The only committed infrastructure is the Squad agent orchestration system (`.squad/`, `.github/agents/`, `.github/workflows/`). Don't assume build tools, package manifests, or test runners exist until you verify; ask before scaffolding a stack.

## Planned stack (per team roster)

AR-Runner targets an **Apple Watch + AR glasses running app** integrating:

- **watchOS / Swift / HealthKit** (owned by Laughlin)
- **ActiveLook SDK over BLE** for AR glasses HUD (owned by Weiss)
- **Workout & fitness metrics** (owned by Amber)

Treat these as the working assumption when proposing architecture, but confirm with the user before generating non-trivial code.

## Squad orchestration system

This repo uses [Squad](https://github.com/bradygaster/squad) for AI team coordination. The coordinator agent (`.github/agents/squad.agent.md`) is the authoritative governance file — its rules override any conflicting guidance.

Key locations:

- `.squad/team.md` — roster (must contain a `## Members` section; the header is hard-coded in workflows)
- `.squad/routing.md` — who handles what
- `.squad/decisions.md` — append-only decision ledger; agents drop entries into `.squad/decisions/inbox/` and Scribe merges them
- `.squad/agents/{name}/charter.md` — per-agent identity (read by coordinator at spawn time)
- `.squad/agents/{name}/history.md` — append-only personal learnings

Append-only files (`decisions.md`, `history.md`, `log/`, `orchestration-log/`) use `merge=union` in `.gitattributes` so branch merges combine entries automatically.

### Runtime state (gitignored)

Don't commit these — they're per-machine scratch:

```
.squad/orchestration-log/
.squad/log/
.squad/decisions/inbox/
.squad/sessions/
.squad/.scratch/
.squad-workstream
```

## GitHub label automation

Four workflows in `.github/workflows/` drive issue routing:

- `sync-squad-labels.yml` — generates `squad:{member}` labels from `team.md`'s `## Members` table
- `squad-triage.yml` — when an issue gets the bare `squad` label, the Lead triages and adds a `squad:{member}` sub-label
- `squad-issue-assign.yml` — routes labeled issues to the named member
- `squad-heartbeat.yml` — event-based keep-alive

**If you edit `team.md`, keep the `## Members` header verbatim** — the workflows parse it by exact name.

## Conventions specific to this repo

- **Never write to `.squad/decisions.md` directly.** Drop a file in `.squad/decisions/inbox/{agent}-{slug}.md`; Scribe merges.
- **Each agent only edits its own `history.md`.** Cross-agent updates go through Scribe.
- **Reviewer rejections lock out the original author** — a different agent must do the revision (see `squad.agent.md` → Reviewer Rejection Protocol).
- **The coordinator dispatches, never implements.** When acting through Squad, spawn the relevant agent rather than producing domain artifacts inline.
