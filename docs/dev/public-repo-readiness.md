# Public-Repo Readiness Audit

**Date:** 2026-05-15T09:49 (America/New_York)
**Auditor:** Richards (Lead / Architect)
**Scope:** `jkrilov/AR-Runner` — all 193 tracked files, plus commit metadata
**Verdict:** 🟡 **Go after a small, well-scoped cleanup pass** (≈30–60 min of work)

---

## Executive Summary

AR-Runner is in good shape to go public. There are **no real secrets** in the tree (only example/template strings inside skill docs that teach how to detect secrets), no API keys, no credentials, no proprietary code, and no internal-corporate references in any committed source or Apple-platform artifact. The repo is small (193 tracked files), the Squad system on top of it is itself open source (`bradygaster/squad`), and the ActiveLook iOS SDK we plan to consume is **Apache 2.0** — so there is no licensing barrier to shipping AR-Runner under a permissive OSS license.

The 5 things Joe must do before flipping the visibility switch:

1. **Redact one Microsoft-corporate username** — `<corporate-account>` appears once in `.squad/orchestration-log/2026-05-14T20-48-00Z-amber.md` (line 46). Single-occurrence, easy edit.
2. **Add a `LICENSE` file** — recommendation: **Apache 2.0** (rationale below).
3. **Add a copyright/SPDX header** to all `.swift` files under `ARRunnerCore/`, `ARRunnerWatch/`, `ARRunnerPhone/`, `ARRunnerWidgets/` (≈20 files; one-line header).
4. **Add `SECURITY.md` and `CONTRIBUTING.md`** — light versions; this is a personal project, not a community one yet.
5. **Update README** with a "Project Status: Pre-v0.1, scaffolding only" badge so first-time visitors don't expect a working app.

Everything else (Squad logs, agent histories, cast names, decisions ledger) is fine to ship as-is. The squad system being publicly visible is a **feature**, not a leak — it tells future readers how the codebase was built.

The big "do NOT do this later" warning: **never commit ActiveLook visual assets** (icons, fonts, layouts from `Activelook-Visual-Assets`). They are CC BY-NC-ND, which is incompatible with any OSS license and would taint the repo. We don't currently ship any; keep it that way unless Joe decides to negotiate a commercial license or commit to non-commercial use.

---

## 1. PII & Secrets Findings

### Method
- `git ls-files | xargs grep -nE …` for: emails, `/Users/`, common API key prefixes (`gho_`, `ghp_`, `github_pat_`, `sk-`, `AKIA`, `xoxb-`), passwords, tokens.
- Inspected commit author metadata for the full git log.
- Walked every committed `.squad/` artifact (agent histories, decisions ledger, orchestration logs, casting registry, identity files).

### Findings

| File | Finding | Severity | Recommendation |
|------|---------|----------|----------------|
| `.squad/orchestration-log/2026-05-14T20-48-00Z-amber.md:46` | `gh CLI authed as <corporate-account>; repo owned by jkrilov.` — leaks Joe's Microsoft-corporate GitHub username. | 🔴 | **Redact** to `<corporate-account>` or remove the sentence. The blocker context is preserved by `repo owned by jkrilov; PR creation failed.` |
| Commit metadata (all 32 commits) | Author email is `jkrilov@gmail.com`. | 🟢 | **Leave as-is.** That email is already on Joe's public GitHub profile by virtue of every push he has ever made; rewriting history to scrub it would force-push over PR #1, #2, #3 and accomplish nothing. |
| `.squad/decisions.md:299` + `.squad/config.json` | References model `claude-opus-4.7-1m-internal` (an internal-only model alias). | 🟡 | **Leave as-is.** It's a model name string, not a credential. `.github/agents/squad.agent.md:451` (the upstream Squad governance file) already references `claude-opus-4.6-1m (Internal only)` and is publicly available in `bradygaster/squad`. Same shape of disclosure; harmless. |
| `.squad/skills/swift-6-strict-concurrency-default/SKILL.md:123` | `First observed: 2026-05-14, AR-Runner project, Joe Krilov on Swift 6.3.2…` — Joe's full name. | 🟢 | **Leave.** Joe's full name is already on his public GitHub profile and was explicitly chosen for `team.md`. No new disclosure. |
| `.squad/decisions.md:297` | `By: Joe Krilov (via Copilot)` — full name. | 🟢 | Same as above. |
| `README.md:21` | "Joe — product direction" — first name. | 🟢 | **Keep.** Per project policy, first names are intentional. |
| `.squad/agents/richards/history.md:13,20` + `.squad/log/2026-05-14T18-37-10Z-github-connect.md:17` + `.squad/orchestration-log/2026-05-14T18-37-10Z-richards.md:14` | `git@github.com:jkrilov/AR-Runner.git` (SSH remote URL). | 🟢 | **Leave.** That URL is public the moment the repo flips public. |
| `.copilot/skills/secret-handling/SKILL.md:44`, `.squad/templates/skills/{secret-handling,gh-auth-isolation}/SKILL.md` | Strings like `OPENAI_API_KEY=sk-proj-...`, `GITHUB_TOKEN=ghp_...`, `ghp_xxxxxxxxxxxx`. | 🟢 | **Leave.** All are placeholders/examples teaching detection, not real secrets. |
| Hardcoded `/Users/joekrilov/...` paths | None in any committed file. | 🟢 | Checked. Build artifacts under `ARRunnerCore/.build/` contain machine-local paths but `.build/` is gitignored. |
| AWS keys, Slack tokens, GitHub PATs (`AKIA[0-9A-Z]{16}`, `xoxb-`, `gho_`) | None found anywhere committed. | 🟢 | Clean. |
| Internal Microsoft hostnames, internal tool names | None. | 🟢 | Clean. |

### `.squad/log/**` and `.squad/orchestration-log/**` — keep or strip?

These are detailed agent transcripts, ~10 files totaling a few hundred lines. After a full read-through:

- **Recommendation: KEEP all but the one Amber log line above.** They make the project's working method legible to future readers ("oh, so this is how a multi-agent dev team actually moves through a CI bug") and demonstrate the Squad system in action. That's a value-add, not a leak. There is no client data, no third-party IP, no internal-only context other than the one line flagged.
- The single Microsoft-username leak is a 1-character `sed` away from being clean.

---

## 2. License Recommendation

### Recommended: **Apache License 2.0**

Reasoning (named trade-offs):

| Option | For | Against | Verdict |
|--------|-----|---------|---------|
| **MIT** | Shortest, most permissive, widely understood. | No explicit patent grant — meaningful when wrapping GATT/BLE protocols where vendor patent claims are non-zero. | Acceptable, but Apache 2.0 is strictly better here. |
| **Apache 2.0** | Permissive + explicit patent grant + retaliation clause + standard NOTICE handling. **Matches the ActiveLook iOS SDK license**, so the inbound/outbound license story is uniform. | Slightly longer file. SPDX header is 3 lines instead of 1. | ✅ **Recommended.** |
| **BSD-3-Clause** | Permissive; no-endorsement clause useful if you don't want "Powered by AR-Runner" derivative branding. | No patent grant. No advantage over Apache 2.0 here. | Skip. |
| **MPL-2.0** | File-level copyleft — modifications to AR-Runner files must be shared back, but linking/embedding in proprietary apps is fine. | Heavier than this hobby project warrants; muddies the patent story vs. Apache. | Skip. |
| **GPL-3.0** | Strong copyleft — anyone shipping a derivative must open-source it. | **Wrong fit.** Would make the watch/phone targets effectively unshippable on the App Store for anyone but Joe (App Store distribution is in tension with GPL's user-freedoms requirements). Also incompatible with Apache 2.0-licensed dependencies in some interpretations. | Skip. |

**Decision driver:** The ActiveLook iOS SDK we plan to consume via SPM is Apache 2.0 (verified at `docs/research/activelook/ios-sdk.md:8`, "License: Apache 2.0"). Using the same license means contributors and consumers see one license model end-to-end with no compatibility analysis required.

### ActiveLook constraint analysis (CRITICAL)

Two ActiveLook repos, two different licenses:

| Repo | License | Constraint on us |
|------|---------|------------------|
| `ActiveLook/ios-sdk` (the SDK we'll consume via SPM) | **Apache 2.0** | None — Apache 2.0 is fully compatible with shipping AR-Runner under MIT, Apache 2.0, BSD, or MPL. |
| `ActiveLook/Activelook-Visual-Assets` (icons, fonts, prebuilt layouts) | **CC BY-NC-ND 4.0** | **Severe.** Non-Commercial + No-Derivatives + Attribution-required. |
| `ActiveLook/Config-Generator` (Python tool to author configs) | **CC BY-NC-ND 4.0** | Tool used at build-time only; output (a config binary) inherits constraints depending on derivative interpretation. |

**Hard rule for the public repo:** **Do not commit any ActiveLook visual asset** — no PNGs, no fonts, no `config.json` from their `cfgDescriptor/`, no copies of their layout templates. We don't currently ship any (we have zero glasses graphics in the repo today). If/when Weiss or Killian wants to bake layout presets per D6, two options:

1. **Author from scratch:** create original icons/layouts/fonts and ship those under our license. Recommended path.
2. **Stay non-commercial forever:** if AR-Runner is permanently a hobby project with no monetization, the CC BY-NC-ND assets are usable — but we would have to add a `THIRD_PARTY_LICENSES.md` file documenting attribution and the NC restriction, and accept that the project is no-longer freely sub-licensable.

This needs to be a Killian-tracked product decision before any visual asset lands. I'll flag it in my decision drop.

### LICENSE file content (recommended verbatim)

Use the standard Apache 2.0 text from <https://www.apache.org/licenses/LICENSE-2.0.txt> with this filled-in copyright notice at the bottom (or replace the bracketed sample at the end of the standard license text):

```
Copyright 2026 Joe Krilov

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```

A `NOTICE` file is **not required** for AR-Runner today (we ship no third-party Apache-licensed code yet). Add one when ActiveLook SDK is vendored or any other Apache 2.0 dep lands.

---

## 3. Copyright / SPDX Header Pattern

### Recommendation: SPDX one-liner at the top of every Swift source file

```swift
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Joe Krilov
```

**Why SPDX:**
- Machine-readable; license scanners (Swift Package Index, FOSSA, ScanCode, etc.) pick it up automatically.
- Two lines, no boilerplate Apache header bloat per file.
- The full Apache 2.0 text lives in `LICENSE` at repo root; SPDX is the contract that says "this file is governed by that".
- Standard convention in the Apple/Swift ecosystem (used by `swift-collections`, `swift-async-algorithms`, etc.).

### Files that need the header (≈20 files)

All `.swift` files under:
- `ARRunnerCore/Sources/**/*.swift` (8 files)
- `ARRunnerCore/Tests/**/*.swift` (6 files)
- `ARRunnerWatch/**/*.swift` (5 files)
- `ARRunnerPhone/**/*.swift` (3 files)
- `ARRunnerWidgets/**/*.swift` (2 files)

`Package.swift` and `project.yml` do not need a header (config files, not source).

Markdown docs do not need headers — they fall under `LICENSE` by directory inheritance.

---

## 4. Squad State Sanitization

| Artifact | Action |
|----------|--------|
| `.squad/team.md`, `routing.md`, `ceremonies.md`, `config.json` | **Keep as-is.** No PII beyond first names which are intentional. |
| `.squad/decisions.md` | **Keep as-is.** Full project history of why architectural choices were made — this is exactly the kind of thing OSS readers want. |
| `.squad/agents/{name}/charter.md` and `history.md` (all 7 agents) | **Keep as-is.** Histories are informative and demonstrate the working method. No leaks. |
| `.squad/identity/now.md`, `wisdom.md` | **Keep as-is.** |
| `.squad/casting/{registry,policy,history}.json` | **Keep as-is.** Cast names from "The Running Man (1987)" are visible. Per casting policy, the rationale is intentionally not explained in committed docs. The names alone are inert flavor. No need to tone down. |
| `.squad/log/**` (8 session logs) | **Keep as-is** after the one Amber-log redaction below. |
| `.squad/orchestration-log/**` (12 spawn prompts) | **Redact one line** in `2026-05-14T20-48-00Z-amber.md:46`. Keep the rest. |
| `.squad/skills/**`, `.squad/templates/**` | **Keep as-is.** These are upstream Squad scaffolding patterns and Joe-authored skills. Public value, no leaks. |
| `.copilot/skills/**`, `.copilot/mcp-config.json` | **Keep as-is.** No secrets; only patterns and SKILL stubs. |
| `.github/agents/squad.agent.md` | **Keep as-is.** This is the upstream Squad coordinator file (v0.9.4) — already public at `bradygaster/squad`. Going public here adds no new disclosure. |

### The single redaction to make

In `.squad/orchestration-log/2026-05-14T20-48-00Z-amber.md` line 46, change:

> `gh CLI authed as <corporate-account>; repo owned by jkrilov. PR creation failed. User must open PR manually or switch auth.`

to:

> `gh CLI authed as a different user account than the repo owner. PR creation failed. User must open PR manually or switch auth.`

That's it. One sed-line. The blocker is preserved; the corporate identity is gone.

---

## 5. README & First Impression

### Current state
- 33 lines, accurate, factual.
- Reads as a developer-internal doc, not a public landing page.
- No badges, no status indicator, no install-or-try invitation, no screenshot.
- Lists the squad ("Laughlin — watchOS, HealthKit, Swift scaffolding") which on a public repo will read oddly to anyone who doesn't know it's an AI team. That's fine — the existing wording could be left alone, or the section could be retitled "Maintainers / Squad" with a one-line link to a `docs/dev/squad.md` explainer.

### Recommended additions

1. **Status banner at the top:**
   > ⚠️ **Status: Pre-v0.1.** This repository is the architectural scaffold for AR-Runner. There is no installable build yet. The watch/phone/widget targets are stubs; the BLE wrapper and HealthKit integration are next. Stars welcome; PRs from outside contributors are paused until v0.1 lands.

2. **Badges** (top of README, under title):
   - License badge: `![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)` — clear signal.
   - CI build badge: link to `ci-build.yml` macOS workflow status.
   - CodeQL badge: link to `codeql.yml`.
   - **Skip:** test coverage (we have 6 model tests; coverage is not a meaningful signal yet), release version (no releases yet), download counters (no artifact yet).

3. **One-paragraph "What this is":**
   > AR-Runner is a personal experiment in building a watch-first running app that drives a heads-up display on ActiveLook AR glasses. The Apple Watch owns the workout (HealthKit) and the BLE link to the glasses; the iPhone is a configuration cockpit and post-run review tool. Built using the [Squad](https://github.com/bradygaster/squad) AI orchestration system as a deliberate experiment in agent-augmented solo development.

4. **Section order recommendation:**
   1. Title + badges
   2. Status banner
   3. What this is
   4. What's in this repo (already present; keep)
   5. Product shape (already present; keep)
   6. Read next (already present; keep)
   7. Squad / maintainers (rename current "Team" section)
   8. License (one line: "Apache 2.0 — see [LICENSE](LICENSE)")

### Honest answer to "is this ready to be a public face"

Yes, with the status banner. Many widely-respected OSS projects start at the architectural-scaffold stage (e.g., `swift-async-algorithms` started with empty target shells and a roadmap). The repo's strength is its decision provenance — `decisions.md` plus the docs/planning/ tree make the *why* legible, which matters more than the *what* at this stage.

---

## 6. SECURITY.md Outline

```markdown
# Security Policy

## Supported Versions
AR-Runner is in pre-v0.1 development. There are no released versions to support.
Once v0.1 ships, the latest tagged release will be the only supported version.

## Reporting a Vulnerability
Please report security vulnerabilities privately via GitHub's
[Private Vulnerability Reporting](https://github.com/jkrilov/AR-Runner/security/advisories/new)
feature. Do **not** open a public issue for security-sensitive findings.

Expected response time: best-effort within 7 days. This is a personal hobby project,
not a commercial product — please calibrate expectations accordingly.

## Scope
In scope:
- AR-Runner watch, phone, widget, and core targets.
- The Squad orchestration files in `.squad/` to the extent they could be weaponized
  (e.g., agent prompt injection that could affect future contributors using Squad).

Out of scope:
- Apple platform vulnerabilities — report to Apple.
- ActiveLook firmware/SDK vulnerabilities — report to ActiveLook.
- The upstream Squad project — report to https://github.com/bradygaster/squad.
```

Enable **Private Vulnerability Reporting** in repo settings → Security tab after flipping public.

---

## 7. CONTRIBUTING.md Outline

Light — this is a personal project, not a community project yet.

```markdown
# Contributing

Thanks for your interest in AR-Runner.

## Project status
This is a pre-v0.1 personal project. Outside contributions are **paused until
v0.1 ships** so the architecture can stabilize. Issues and discussions are
welcome.

## Once v0.1 is out
- Open an issue first to discuss any change larger than a typo.
- One change per PR; small, reviewable diffs.
- Follow the existing Swift 6 strict-concurrency conventions
  (see `.squad/decisions.md` D8 and the `swift-6-strict-concurrency-default` skill).
- Tests live in `ARRunnerCore/Tests/`; CI runs on Linux (core) and macOS (apps).

## About the Squad system
This repo is built using [Squad](https://github.com/bradygaster/squad), an AI
agent orchestration framework. The `.squad/` directory contains the persistent
team configuration, decision ledger, and session history. You do not need to
use Squad to contribute — but you may find `decisions.md` helpful for
understanding why the architecture is shaped the way it is.

## License
By submitting a PR, you agree that your contribution is licensed under the
Apache License 2.0 (see [LICENSE](LICENSE)).
```

---

## 8. GitHub Repo Settings Changes (do AFTER flipping visibility)

At <https://github.com/jkrilov/AR-Runner/settings>:

- **General → Features:**
  - ✅ Issues — keep enabled.
  - ✅ Discussions — **enable.** Useful for "what is this project" Q&A traffic that doesn't belong as an issue.
  - ❌ Wiki — disable. We use `docs/` instead.
  - ❌ Projects — keep disabled unless Killian wants to start using GitHub Projects for the v0.1 backlog.
  - ❌ Sponsorships — Joe's call; default off.
- **Branches → Branch protection rules:**
  - Add a rule on `main`: require PR before merging, require status checks (`ci-core-tests`, `ci-build` matrix, `CodeQL`), require linear history (matches our "no direct main" directive), and require conversation resolution. Disallow force pushes.
- **Code security and analysis:**
  - ✅ Enable **Private vulnerability reporting**.
  - ✅ Enable **Dependabot alerts** (free, no cost). **Defer Dependabot version updates** until we have real SPM deps (per the existing CI ADR).
  - ✅ Enable **Secret scanning** + **Push protection** (free on public repos).
  - ✅ Enable **CodeQL default setup OR keep your custom `codeql.yml`** — keep the custom one; it's already pinned to Xcode 16.4 and configured for Swift `security-extended` queries.
- **Actions → General:**
  - "Allow all actions and reusable workflows" — fine for a personal project.
  - "Workflow permissions: Read repository contents and packages permissions" with explicit `permissions:` blocks per workflow (already the pattern in `ci-*.yml`).
- **Pages:** leave off until there's a demo to show.
- **Tags / releases:** create a `v0.1.0-pre` tag once the audit cleanups land, so the public landing page has at least one tag visible.

---

## 9. Pre-Flight Checklist (ordered)

Do these in this order. Each is a small commit on a single `chore/public-repo-prep` branch, then one PR Joe reviews and merges before flipping visibility.

- [ ] **1. Redact corporate identity** — `sed`-edit `.squad/orchestration-log/2026-05-14T20-48-00Z-amber.md` line 46 per §4 above.
- [ ] **2. Add `LICENSE`** — paste Apache 2.0 text + Joe Krilov 2026 copyright per §2.
- [ ] **3. Add SPDX headers** — script-driven, prepend the 2-line header to every `.swift` file listed in §3.
- [ ] **4. Add `SECURITY.md`** — at repo root, per §6.
- [ ] **5. Add `CONTRIBUTING.md`** — at repo root, per §7.
- [ ] **6. Update `README.md`** — status banner, badges, "what this is" paragraph, license footer per §5.
- [ ] **7. Re-verify `.gitignore`** — confirm `.build/`, `.swiftpm/`, `xcuserdata/`, `Config/`, `*.xcodeproj/`, `*.xcworkspace/`, all `.squad/` runtime dirs, and `.squad-workstream` are still listed. (Already in place; just sanity-check no new artifact category needs adding.)
- [ ] **8. Run a final `git ls-files | xargs grep -nE '<corporate-account>'`** — must return zero hits.
- [ ] **9. Open the prep PR** — title `chore: prepare repo for public visibility`. Get a fresh-eyes review (not Richards — reviewer protocol). Recommended reviewer: **Killian** (product perspective on README + status framing).
- [ ] **10. Merge the prep PR.**
- [ ] **11. Flip visibility** at <https://github.com/jkrilov/AR-Runner/settings> → Danger Zone → Change visibility → Make public. *(One-way door — Google indexing starts ~hours later.)*
- [ ] **12. Apply repo-settings changes** per §8 (branch protection, vulnerability reporting, Dependabot alerts, secret scanning, Discussions).
- [ ] **13. Tag `v0.1.0-pre`** — gives the public landing page a first release marker.
- [ ] **14. Open Discussion: "Welcome / project status"** — single pinned discussion explaining pre-v0.1 status and that outside PRs are paused.

Estimated effort end-to-end: **30–60 minutes of human time + one CI cycle.**

---

## 10. Open Questions for Joe

Only the genuinely ambiguous ones. Joe should answer these before step 2 of the checklist.

1. **License confirmation: Apache 2.0?** I recommend it (matches inbound ActiveLook SDK, includes patent grant). MIT would also be defensible if Joe prefers maximum simplicity. **Pick one.**
2. **Copyright holder name on the LICENSE / SPDX headers** — `Joe Krilov`, `Joe K`, or something else? Standard recommendation: `Joe Krilov` matches what's already in `decisions.md` and matches Joe's public GitHub profile.
3. **ActiveLook visual assets policy** — confirm the hard rule: *"AR-Runner will not commit any asset, font, or layout template from the `Activelook-Visual-Assets` or `Config-Generator` repos. Original art only."* This is mostly a Killian/Weiss execution policy, but it deserves a one-line entry in `decisions.md` so it's binding. If Joe wants to keep the door open to using the CC BY-NC-ND assets under a permanent non-commercial covenant, say so now.
4. **Outside PRs: paused or open?** I recommend paused-until-v0.1 (per CONTRIBUTING.md draft) so the architecture can settle without drive-by churn. If Joe wants the opposite signal — "I want hacking from day one" — drop the pause language.
5. **Squad system disclosure tone in README** — current draft says "Built using Squad… as a deliberate experiment in agent-augmented solo development." Joe may prefer a lighter touch (e.g., just a single linked footnote) or no mention at all. Cosmetic, but it sets the project's voice.

---

**End of audit.** Verdict reaffirmed: 🟡 **Go after the small cleanup pass.** Repo is fundamentally healthy; one corporate-identity redaction, one license file, one header sweep, three short markdown files, and a README polish stand between Joe and a clean public flip.
