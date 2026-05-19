# Skill: Release Mechanics CI Polling Patterns

> **Owner:** Scribe (learned from Laughlin-13 session, 2026-05-18)
> **Born:** 2026-05-18
> **Confidence:** HIGH (operational lesson from post-release cleanup)
> **Related:** `ios-testflight-ci-via-actions`, Release workflows, Scribe post-release duties

## Why this skill exists

During v0.3.0-rc6 release (Laughlin-13 session), Laughlin used a `sleep N && gh pr view ... | python3` polling loop to wait for CI gates. The pattern left **7 stuck shell processes** that the coordinator had to kill manually. This is a recurring class of cruft in release workflows.

## The trap

```bash
# ❌ ANTI-PATTERN: leaves orphan shells
while ! gh pr view $PR_NUMBER --json=statusCheckRollup | python3 -c "..."; do
    sleep 10
done
```

**Problems:**
1. `sleep N && command` constructs are not job-control-aware — backgrounding or timeouts leave sleep processes behind.
2. Python subprocess parsing can silently fail; the while loop keeps retrying forever or until forcefully killed.
3. No built-in timeout; if the API is slow or transient, shells accumulate.
4. Each loop iteration spawns new `gh` and `python3` processes — after N retries, you have 2N zombie or stalled processes.

## The right patterns

### Pattern A: `gh pr checks --watch` (RECOMMENDED)

```bash
# ✅ CORRECT: built-in timeout, single process, guaranteed exit
gh pr checks $PR_NUMBER --watch --interval=5 --timeout=600
```

**Advantages:**
- Single process, exits cleanly on completion or timeout.
- `--timeout=600` (10 min) prevents runaway — adjust for your tolerance.
- `--interval=5` (5 sec) is a good default; tune down for faster feedback.
- Built into `gh` CLI — no subprocess nesting or string parsing.
- Returns exit code 0 on green, non-zero on failure → safe in `set -e` scripts.

**When to use:** Any time you need to wait for all required checks to pass on a PR.

### Pattern B: `gh run watch` (FOR WORKFLOWS)

```bash
# ✅ CORRECT: watch a specific workflow run
gh run watch $RUN_ID --interval=5 --timeout=600
```

**Advantages:**
- Direct workflow monitoring (vs. PR-level checks).
- Same single-process, timeout-aware behavior as Pattern A.
- Returns exit code matching the run's conclusion (0=success, non-zero=failure or neutral).

**When to use:** When you have a workflow run ID (e.g., from `gh workflow run` output) and need to wait for it to complete.

### Pattern C: `gh pr checks <pr> --jq` (FOR SCRIPTING)

```bash
# ✅ CORRECT: poll with jq, single process, clean exit
until gh pr checks $PR_NUMBER --jq '.[] | select(.status=="COMPLETED" and .conclusion=="SUCCESS") | length' | grep -q '^4$'; do
    sleep 5
done
```

**Advantages:**
- Uses `--jq` to parse directly at the CLI layer (no Python subprocess).
- Cleaner exit semantics than Python.
- Still requires manual timeout logic; combine with a counter or `timeout(1)` wrapper.

**When to use:** Complex filtering or when you need conditional logic beyond "all green."

## The supervisor pattern (for long-running CI workflows)

If your workflow is naturally long-running (10+ minutes), wrap the wait in a supervisor that guarantees cleanup:

```bash
#!/bin/bash
set -e
PR_NUMBER=$1
TIMEOUT_SEC=1800  # 30 minutes

trap 'echo "Interrupted; cleanup:"; jobs -p | xargs -r kill; exit 130' INT TERM

(
    set +e
    gh pr checks "$PR_NUMBER" --watch --timeout="$TIMEOUT_SEC"
    EXIT_CODE=$?
    exit "$EXIT_CODE"
) &
WATCH_PID=$!

wait "$WATCH_PID" || EXIT_CODE=$?
trap - INT TERM
exit "$EXIT_CODE"
```

**Why:** Traps guarantee that `gh` is killed on interrupt, not orphaned.

## Anti-patterns to avoid

| Anti-Pattern | Problem | Fix |
|---|---|---|
| `sleep 60 && gh pr view ... \| python3 -c "..."` | Orphan shells on timeout or interrupt | Use `gh pr checks --watch` |
| `while true; do ... sleep 10; done` with no counter | Infinite retry loop | Add explicit timeout or counter |
| `gh pr view \| grep "success"` (string parsing) | Fragile to API changes; slow with large output | Use `gh pr checks --jq` |
| Nested subprocesses (`... \| jq \| grep \| ...`) | Each subprocess is a potential orphan | Minimize nesting; use `gh --jq` at the boundary |
| Fire-and-forget in the background | Can't track completion; hard to clean up | Explicit `wait` with trap handlers |

## Lesson for release workflows

**Release workflows are the most critical code path.** Operators (Laughlin, coordinator) are watching them in real-time. Use the most robust waiting pattern available (Pattern A) rather than clever scripting. Every orphaned shell in a release flow creates noise and delays the next session's startup (post-release cleanup directive).

## References

- `gh pr checks` documentation: `gh pr checks --help`
- `gh run watch` documentation: `gh run watch --help`
- `gh pr view --jq` documentation: `gh pr view --help` (search for `--jq`)
- Scribe session notes: 2026-05-18T23:00:00Z post-release cleanup (7 stuck shells killed)
- Post-release autonomy directive: `.squad/decisions.md` entry `2026-05-18T22:44:55Z`
