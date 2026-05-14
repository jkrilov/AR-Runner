### 2026-05-14T16:09:31-04:00: Tooling decision — XcodeGen for project generation
**By:** Joe (via Copilot) — codified during v0.1 foundation scaffolding
**What:** The Xcode workspace and project files are GENERATED from `project.yml` via XcodeGen (`brew install xcodegen` on Mac). The repo does NOT commit `.xcodeproj` or `.xcworkspace` bundles. Source of truth is `project.yml` + Swift sources + `Package.swift` files. To work on the project locally:
  1. Clone repo
  2. On Mac, run `xcodegen generate` from repo root
  3. Open `AR-Runner.xcworkspace`
**Why:** (1) Lets the project be edited from non-Mac environments like Squad on Windows. (2) Eliminates the `.xcodeproj` merge-conflict nightmare entirely. (3) Reproducible: anyone running `xcodegen generate` gets the same project. (4) Reviewable: `project.yml` is YAML — diffs make sense in PRs. Standard pattern for 2026-era Swift projects with mixed-environment teams.
