# Skill: anticipatory-contract-tests

**One-line:** Write integration tests that *define* an unimplemented contract before the owner implements it, using `XCTSkipIf` markers so CI stays green while the contract is encoded in code.

## When to use

You're QA / domain on a parallel-agent project. Two implementing agents own the upcoming surface. You can write tests faster than they can implement, and you want their implementation to have a *target* — a green/skipped suite that turns green when their code lands.

## The pattern

1. **Anchor today's behavior with passing tests.** Write the tests that exercise the *current* surface against the locked decisions. These must pass today and stay green forever. They become the regression net.

2. **For contracts that don't exist yet, write the test body anyway** — using only API that *does* compile today. Wrap each anticipatory test in:

   ```swift
   try XCTSkipIf(
     true,
     "EXPECTED-FAILING-UNTIL: <workstream> implementation — <one-line gap>. Owner: <agent>."
   )
   ```

   The skip keeps CI green; the body keeps the contract live (won't bit-rot under refactors).

3. **If the test needs an API that doesn't compile yet** (e.g., `controller.alerts` doesn't exist), keep the test body as a `// commented-out` sketch under the skip. When the API lands the reviewer uncomments + deletes the skip in one diff.

4. **Cross-link the test docstring with a `decisions/inbox/` contract-gap entry** so the implementing agent can see the menu of gaps without reading every test file.

5. **Hand-off via PR description**: explicitly list which expected-failing tests each owner must turn green, with file + test name + owner.

## Why XCTSkipIf vs. alternatives

| Choice | Pro | Con |
|---|---|---|
| `XCTSkipIf(true, "...")` | CI green; body stays compiled; one-line removal turns it on | XCTest-only |
| Swift Testing `@Test(.disabled(...))` | Cleaner annotation | Mixing XCTest + Swift Testing in one suite is messy |
| Comment out the test | Zero CI noise | Body bit-rots; reviewer can't see the contract; no skip count in test report |
| `XCTFail("not implemented")` with `@available` gate | Forces implementation | Breaks CI immediately; not anticipatory, just blocking |

`XCTSkipIf` wins because the skip count in the test report (`3 tests skipped`) is itself documentation: anyone reading CI output knows there's pending work.

## Anti-patterns to avoid

- **Don't blindly add new mock affordances** to support an anticipated contract. If the canonical mock can't express the contract, that *is* the contract gap — write it up in the inbox entry. Adding `simulateAutoReconnect()` to `MockGlassesFrame` would have hidden the missing `enableAutoReconnect(policy:)` surface on `GlassesFrameTransport` itself.
- **Don't assume the bridge task has run.** Cross-actor stream forwarding is asynchronous — every assertion against the consuming side's observable state needs `waitUntil { … }` polling, not a fixed `Task.sleep`.
- **Don't delete unstaged WIP from a peer agent's branch** when switching branches. The working tree carries it; stash with a labelled message and restore later.

## Marker format (codify)

```
// EXPECTED-FAILING-UNTIL: <workstream-id> implementation — <gap>. Owner: <agent>.
```

Used both in the test docstring and as the `XCTSkipIf` message. Greppable across the codebase, machine-trackable in CI dashboards.

## Example

See `ARRunnerCore/Tests/ARRunnerCoreTests/Integration/DisconnectResilienceTests.swift` (PR #8). Three expected-failing tests (`*_ExpectedFailing` suffix) cover three contract gaps; matching inbox entry at `.squad/decisions/inbox/amber-v02-resilience-contract-gaps.md`.
