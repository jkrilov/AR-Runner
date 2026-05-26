---
name: "release-monotonicity"
description: "Semver-correct version-monotonicity guards in CI workflows, including trigger-tag self-collision avoidance and in-workflow comparator self-tests."
domain: "release-engineering"
confidence: "high"
source: "earned — AR-Runner v0.5.20 fixed two bugs that had forced manual workflow_dispatch on every v0.5.x release"
---

## Context

A release workflow that auto-triggers on pre-release tags (e.g.
`v*.*.*-*`) typically guards against backward version steps by comparing
the proposed version to the highest existing `v*` tag. Two non-obvious
pitfalls turn this guard into a foot-gun that blocks every release:

1. **Self-collision.** On a tag-push trigger, `git fetch --tags` makes the
   trigger tag visible locally. If the candidate list isn't filtered, the
   workflow rejects itself because RAW_VERSION matches an existing tag.
2. **`sort -V` is not SemVer-correct.** GNU version-sort orders longer
   strings with a shared prefix LATER, so it puts `1.0.0-rc1` AFTER
   `1.0.0`. SemVer 2.0 specifies the opposite — pre-releases sort
   BEFORE their release.

Both pitfalls are silent until release day, when they either let a
backward step through (false negative) or block a correct release (false
positive). The AR-Runner team hit the false-positive in every v0.5.x
release before v0.5.20.

## Patterns

### Pattern 1 — Exclude the trigger tag

On `push` events to `refs/tags/v*`, the tag that triggered the run is in
the local tag list after `git fetch --tags`. Filter it out exactly
before scanning candidates:

```bash
TRIGGER_TAG=""
if [[ "$GITHUB_EVENT_NAME" == "push" ]]; then
  TRIGGER_TAG="${GITHUB_REF#refs/tags/}"
fi
if [[ -n "$TRIGGER_TAG" ]]; then
  CANDIDATES="$(git tag --list 'v*' | grep -v -F -x "$TRIGGER_TAG" | sed 's/^v//')"
else
  CANDIDATES="$(git tag --list 'v*' | sed 's/^v//')"
fi
```

`grep -v -F -x` is "invert, fixed-string, whole-line" — the exact
exclusion semantics we want (no regex surprises, no substring matches).

### Pattern 2 — Inline `semver_gt` comparator (do not trust `sort -V`)

```bash
semver_gt() {
  # Returns 0 (true) iff $1 > $2 under SemVer 2.0.
  local a="$1" b="$2"
  local a_main="${a%%-*}" b_main="${b%%-*}"
  local a_pre="" b_pre=""
  [[ "$a" == *-* ]] && a_pre="${a#*-}"
  [[ "$b" == *-* ]] && b_pre="${b#*-}"
  local IFS=.
  local am=($a_main) bm=($b_main)
  unset IFS
  for i in 0 1 2; do
    local ai="${am[$i]:-0}" bi="${bm[$i]:-0}"
    (( ai > bi )) && return 0
    (( ai < bi )) && return 1
  done
  # MAJOR.MINOR.PATCH tied → absence-of-prerelease wins.
  [[ -z "$a_pre" && -z "$b_pre" ]] && return 1
  [[ -z "$a_pre" ]] && return 0
  [[ -z "$b_pre" ]] && return 1
  # Dot-separated identifier comparison: numeric vs numeric numerically,
  # otherwise ASCII lex; shorter sequence loses when all shared identifiers tie.
  local IFS=.
  local ap=($a_pre) bp=($b_pre)
  unset IFS
  local max=$(( ${#ap[@]} > ${#bp[@]} ? ${#ap[@]} : ${#bp[@]} ))
  for (( i=0; i<max; i++ )); do
    local ax="${ap[$i]-}" bx="${bp[$i]-}"
    [[ -z "$ax" ]] && return 1
    [[ -z "$bx" ]] && return 0
    if [[ "$ax" =~ ^[0-9]+$ && "$bx" =~ ^[0-9]+$ ]]; then
      (( 10#$ax > 10#$bx )) && return 0
      (( 10#$ax < 10#$bx )) && return 1
    else
      [[ "$ax" > "$bx" ]] && return 0
      [[ "$ax" < "$bx" ]] && return 1
    fi
  done
  return 1
}
```

### Pattern 3 — Self-test step BEFORE the guard step

A separate, earlier step in the same job runs assertions against the
comparator. If the comparator regresses, the workflow halts BEFORE doing
anything destructive (archive, upload, tag-push side effects).

Minimum fixture set, derived from real-world traps:

```bash
assert_gt 0.5.20    0.5.19         # basic increment
assert_gt 0.5.19    0.5.19-1       # release > prerelease  (sort -V trap)
assert_gt 0.5.19    0.5.19-rc2     # release > prerelease
assert_lt 0.5.19-1  0.5.19         # mirror
assert_gt 0.5.20-1  0.5.19         # new-prerelease > old release
assert_gt 0.5.19-2  0.5.19-1       # numeric prerelease ordering
assert_lt 0.5.19    0.5.19         # equality is not strict-greater
assert_gt 1.0.0     0.99.99        # numeric (not lex) on minor
```

The eleventh assertion (`assert_lt 0.5.19 0.5.19`) is critical — it
pins the "strictly greater" semantics. Equality-as-greater is the most
common regression when refactoring this code.

### Pattern 4 — Highest-tag selection by reduction

Once `sort -V` is off the table, iterate the candidate list keeping a
running max:

```bash
LATEST_TAG=""
while IFS= read -r cand; do
  [[ -z "$cand" ]] && continue
  if [[ -z "$LATEST_TAG" ]] || semver_gt "$cand" "$LATEST_TAG"; then
    LATEST_TAG="$cand"
  fi
done <<< "$CANDIDATES"
```

This is O(n) and reuses the same comparator the guard uses — one source
of truth, exercised by Pattern 3.

## Examples

- `.github/workflows/release-testflight.yml` (AR-Runner) — full
  implementation as of v0.5.20.

## Anti-Patterns

- **`sort -V | tail -n 1`** for SemVer ordering. Wrong for any version
  with a pre-release suffix.
- **`git tag --list` without trigger-tag exclusion** on a tag-push
  workflow. Guarantees self-collision.
- **Comparator-only fix without a self-test step.** The original bug
  shipped because nothing exercised the comparator in CI. Future edits
  will regress unless an assertion suite runs on every release.
- **Pulling in a marketplace action** (`madhead/semver-utils` et al.)
  for ~30 lines of bash on a critical-path release workflow. Adds an
  uncontrolled dependency for negligible savings; the inline version is
  self-testing on every run.
- **Python for this job.** Adds runner setup time and a heavier
  dependency surface than a pure-bash function that runs in well under
  a second.
