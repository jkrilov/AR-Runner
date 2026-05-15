# Richards — History

## Core Context

- **Project:** An Apple Watch fitness app integrated with ActiveLook AR glasses.
- **Role:** Lead
- **Joined:** 2026-05-14T18:30:31.650Z

## Learnings

### GitHub Remote Setup — 2026-05-14T14:37:10-04:00

- **Repo URL:** git@github.com:jkrilov/AR-Runner.git
- **Default Branch:** main
- **Initial Commit SHA:** fd2faad
- **Commit Message:** "Initial commit: Squad scaffolding for AR-Runner" (126 files, ~14.5 KB)
- **Status:** Initialized and committed locally. Push deferred to user (SSH auth required).
- **Setup Process:**
  - `git init -b main` — initialized with main as default branch
  - `git remote add origin git@github.com:jkrilov/AR-Runner.git` — SSH remote configured
  - `git status` verified runtime state dirs (.squad/orchestration-log/, .squad/log/, .squad/decisions/inbox/, .squad/sessions/, .squad/.scratch/) were properly gitignored
  - 126 files staged and committed (Squad scaffolding, workflows, .copilot/ skills, team config)
- **No issues:** All files properly staged, runtime state correctly ignored by .gitignore

<!-- Append learnings below -->

### System Architecture Plan — 2026-05-14T15:03:23-04:00

- **Deliverable:** `docs/planning/architecture.md` (v0.1) — full system architecture for AR-Runner
- **Decisions inbox:** `.squad/decisions/inbox/richards-architecture-v0.md` (7 ADRs)
- **Key architectural choices made:**
  - `ARRunnerCore` shared SPM package (models, workout state machine, glasses frame protocol, WCSession contract) consumed by both watchOS and iOS shells
  - Three WCSession message types: `LayoutConfigMessage` (phone→watch), `WorkoutTickMessage` (watch→phone, ~1Hz), `WorkoutLifecycleMessage` (watch↔phone)
  - BLE strategy: Option B (phone-only) for v0.1, Option C (hybrid handoff) as v1 target — pending Weiss SDK confirmation
  - State ownership: Watch/HealthKit owns workout session + metrics + history; Phone/iCloud KV owns layout config + preferences; BLE owner TBD
  - Minimum targets: watchOS 11 / iOS 18 / Swift 6 (recommended, Joe must confirm)
  - `GlassesFrameProtocol` abstracted behind a Swift protocol so Laughlin can build before BLE strategy is locked
- **Blocking inputs needed:**
  - **Weiss:** ActiveLook SDK platform support (iOS? watchOS? SPM/XCFramework/Pod?), GATT frame throughput/budget
  - **Laughlin:** WCSession reachability during HKWorkoutSession, App Intent background launch capability
  - **Killian:** Is custom run history in MVP scope? (D4 decision)
  - **Joe:** D1–D7 decision points (BLE ownership, OS targets, persistence strategy, workspace layout, Swift 6)
- **Risk register:** 5 risks documented (BLE occlusion, watch radio contention, App Intent background, frame budget, iCloud KV race)
- **Patterns applied:** SPM bounded contexts, domain-driven state ownership, typed WCSession contract, abstract BLE protocol boundary

### 2026-05-14: Team update from Joe — 9 architecture decisions locked (see decisions.md D1-D9). Next phase: Xcode scaffolding (Laughlin) + ActiveLook watchOS BLE spike (Weiss).

### 2026-05-14: Team update from Joe — v0.1 foundation scaffold + BLE spike landed on feat/v01-foundation. Branch awaiting Joe's push & PR. Next: WorkoutController impl (Laughlin) + watchOS BLE wrapper impl (Weiss).

### 2026-05-15: Public-repo prep executed (PR #4 chore/public-repo-prep)

Joe approved all 5 of my open audit questions verbatim and asked me to execute. Branch `chore/public-repo-prep` opened against main; PR #4 awaiting Killian review (I'm locked out of reviewing — authored both the audit and the implementation).

**Decisions locked (drops in inbox):**
- **License: Apache 2.0**, copyright `2026 Joe Krilov`. Canonical Apache text from apache.org with copyright footer appended. Matches inbound ActiveLook iOS SDK license — no compatibility analysis required for downstream consumers.
- **ActiveLook visual-assets hard rule:** PERMANENT. No commits from `Activelook-Visual-Assets` or `Config-Generator` (CC BY-NC-ND incompatible with our Apache 2.0 outbound). Original art only. Documented the alternative path (relicense → non-commercial) so future-me doesn't have to re-derive the reasoning.
- **Outside PRs:** paused-until-v0.1. Issues for discussion welcome.
- **README Squad mention:** light footer credit only — never lead the README with it.

**SPDX header rollout:** 23 committed `.swift` files. Used the **two-line `SPDX-FileCopyrightText` + `SPDX-License-Identifier` form** (not the audit's earlier draft of `// Copyright (c)` + SPDX). Joe's brief specified that exact form; it's also the form most actively maintained by SPDX/REUSE tooling. Convention is now locked for all new Swift files going forward — reviewers should reject untagged sources.

**Subtle things for future-Joe:**
1. **`gh pr create` with a `--body $(cat <<EOF…)` heredoc hung indefinitely** in this non-interactive shell. Switching to `--body-file <tmpfile>` (committed nowhere; deleted after) succeeded in <2s. Pattern to remember for any future automated PR creation.
2. **The audit doc itself echoed the corporate username 3× in §1 / §4 / §10.** Almost shipped that as new-tracked content. Always run the redaction grep against the staged tree, not just the originally-flagged file. `sed -i ''` (BSD form on macOS) caught all three echoes.
3. **`.squad/decisions/inbox/` is gitignored** — the two decision drops I created (`richards-activelook-visual-assets-rule.md` + `richards-public-repo-prep-locked.md`) won't appear in PR #4. They're picked up by Scribe locally on the next merge cycle. This is expected behavior, but worth flagging in case anyone wonders why the PR diff is "missing" the decision rationale.
4. **Apache 2.0 LICENSE has a built-in `Copyright [yyyy] [name of copyright owner]` placeholder block** as part of its standard text, separate from the actual copyright assertion. Decision: leave the placeholder block intact (it's part of the official license text and useful for downstream forks) and append the real `Copyright 2026 Joe Krilov` line at the very bottom. Do not edit the bracketed sample.
5. **`xcodegen generate` regenerates `AR-Runner.xcodeproj/`** and produced no diff against committed state — confirmed SPDX headers don't disturb the project graph. If any future PR adds new Swift files, expect the project file to update; that's project.yml-driven, not header-driven.

**Pre-flight verified clean:** `swift build` (10/10 modules), `xcodegen generate`, and the post-edit `grep -r joekrilov_microsoft .` returning zero hits across the entire working tree.

**Reviewer protocol enforced:** I did not self-approve. Killian is the designated reviewer per the audit's §9 step 9 recommendation and the reviewer-rejection-protocol spirit. Coordinator should spawn Killian next.
