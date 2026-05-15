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

## Linux vs. macOS scheduler races (post-PR #8 lesson)

When an integration test pipes data through a controller that owns its own internal stream-forwarding task, **never let the test ALSO subscribe to the same upstream `AsyncStream`**. `AsyncStream` is single-consumer-by-design: yields go to whichever waiter the runtime picks. On macOS Darwin the test bridge often wins enough yields to stay green; on swift-corelibs Linux the controller's internal task can drain the entire stream first, leaving the test's bridge with zero metrics. PR #8 CI run 25936009488 burned a debug cycle on this exact pattern.

Concrete failure mode and correct fix:

- `WorkoutController.start(...)` calls `attachSubstrateStreams()` which spawns a `forwardingTask` doing `for await metric in substrate.metricEvents`.
- The test's `bridgeMetrics` *also* did `for await metric in substrate.metricEvents` — two consumers fighting over the same single-consumer stream.
- **Fix:** subscribe the test bridge to `controller.metrics` (the controller's outbound published stream), not to `substrate.metricEvents`. The controller republishes every metric it ingests, so the bridge sees all of them.

**Rule of thumb:** if the canonical controller exposes a `public nonisolated let foo: AsyncStream<T>` output, the test bridge MUST consume that. If the controller doesn't expose one, that's a contract gap to flag in `decisions/inbox/` — don't double-subscribe upstream as a workaround.

**Also worth keeping:** anticipatory tests using `AsyncStream`-backed mocks should still ensure the consumer side is ready before the producer fires (for the `glasses.updateField` → `.notConnected` flavour of race). But verify your hypothesis on the failing platform — adding a debug log inside the bridge that prints `glasses.connectionState` would have invalidated the connect-ordering hypothesis in 30 seconds and saved a CI round-trip.

**Reproduction tip:** `gh run view <id> --log-failed | grep -iE "(failed|XCTAssert|error:)"` extracts the specific failing test + assertion when the GitHub UI snippet truncates.
