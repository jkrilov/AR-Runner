# Swift comment hygiene checklist

**Purpose:** rubric for "shorten or simplify comments after several rcs of churn" passes. Optimised for codebases where comments accumulate dated provenance, audit-trail tags, and references to old per-release decisions that no longer match the canonical vocabulary.

**When to invoke:** post-release cleanup PRs where the explicit ask is "comments that can be shortened or simplified as we've made changes" — not as part of feature work.

## Conservative principle

Cost of leaving a stale comment is small. Cost of deleting context the next maintainer needs is large. **When in doubt, leave it.**

A good pass touches dozens of files lightly. A bad pass deletes 200 lines of rationale to chase a line count.

## What to DROP

- **Dated audit tags** (`v0.2 audit P1.3`, `P1.2 fix`, `audit 2026-05-16`) when the fix is now obvious from the code shape AND captured in a skill/ADR/decision elsewhere. The tag is archaeology, not signal.
- **Dated provenance** (`v0.2.0 device feedback (Joe)`, `post-device-test feedback`) on features that have long shipped. Keep the rationale, drop the date.
- **Version-numbered references to old per-release decisions** (`v0.2 decision #3`, `decision #2`). Replace with the canonical contract language now used everywhere else (e.g. "phone-optional contract", "ADR-1"). One vocabulary, one place to update.
- **"not yet exposed in vX.Y UI"** qualifiers that are technically true but misleadingly versioned — rewrite as "any future X affordance" if the path is real, or delete if speculative.
- **Comments that explain WHAT** the code does when the code is obvious from naming and signature.
- **TODOs/FIXMEs older than 30 days** that refer to things now done — verify before deleting.
- **Multi-line MARK dividers** that don't aid navigation (e.g. one MARK per 5-line method).

## What to KEEP verbatim

- **Lens-flip formulas** / coordinate-system math
- **BLE wire-byte annotations** (`// 0x180F service, 2A19 char`)
- **ADR references** (`per ADR-1`, `per ADR-007`)
- **Skill citations** (`.squad/skills/...`)
- **"Why" rationale** — anything that explains a non-obvious choice
- **Fall-through-order explanations** in switch statements
- **Concurrency contracts** (`@unchecked Sendable because...`, isolation domain notes)
- **Idempotency / throwing contracts** documented on protocol methods
- **Wire format and unit annotations** at adapter boundaries

## What to SHORTEN (not delete)

- Long prose where a 1-line `///` summary works as well
- Multi-paragraph "why" comments where the second paragraph is rationale-for-the-rationale — keep paragraph 1
- "Historical bug + how we fixed it" comments → shorten to "Routes through X (not Y) because Z would silently default-case"
- Comments that name a specific person ("Joe's v0.2.0 ask") when the rationale is universal — de-personalise to the rationale

## Hard limit

If shortening a single comment block requires more than ~3 lines of net change, you're being too aggressive. Stop and leave it.

## Per-file ceiling

A good cleanup pass should remove roughly 1-3 net lines per touched file, across 5-15 files. If you're removing 10+ lines from one file, you're probably deleting rationale, not noise.

## Verification step

Run the test suite after each commit. A docs/comment sweep that breaks tests has touched something that wasn't a comment.

## Citations

- AR-Runner PR #78 (2026-05-19, post-rc17 docs sweep): 10 files, 21 net lines, 186/186 tests green. Followed this rubric end-to-end.
- Joe directive (2026-05-19): "comments that can be shortened or simplified as we've made changes" + "When in doubt, leave the comment."
