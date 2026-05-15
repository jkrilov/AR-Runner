# Skill: Swift 6 actors implementing `AsyncStream`-returning protocols

**When to use:** You have a `Sendable` protocol with a stream-returning method (`func foo() -> AsyncStream<X>`), and you want to implement it in an actor that yields from internal state.

**The trap:** Swift 6 strict concurrency raises `[#ConformanceIsolation]`:

```
error: conformance of 'MyActor' to protocol 'StreamProtocol' crosses into
       actor-isolated code and can cause data races
note:  actor-isolated instance method 'foo()' cannot satisfy nonisolated requirement
```

The protocol requirement is nonisolated by default (no `async` keyword). The actor's method is actor-isolated. Conformance fails because callers from outside the actor would invoke a nonisolated method that touches isolated state.

## Three fixes, in order of preference

### 1. Make the requirement `async` (recommended)

```swift
protocol StreamProtocol: Sendable {
    func foo() async -> AsyncStream<X>      // ← async
}

actor MyActor: StreamProtocol {
    func foo() async -> AsyncStream<X> {    // ← matches
        AsyncStream { continuation in
            self.register(continuation)
        }
    }
}
```

Callers say `let s = await actor.foo()`. Cheap. Preserves actor safety. This is the usual answer for actor-backed protocols.

### 2. Make the method `nonisolated` and read state via a synchronous bridge

Only viable when you can construct the stream without touching mutable actor state. Usually means storing the continuations in a `nonisolated(unsafe)` box or a class-backed sink. Not worth the complexity for v0.1.

### 3. `@preconcurrency` on the conformance

```swift
actor MyActor: @preconcurrency StreamProtocol { ... }
```

Silences the diagnostic at compile time but ships the data race into runtime. Use only at vendor-SDK boundaries (per D8's `@preconcurrency import` pattern).

## Multi-subscriber replay-on-subscribe pattern

When implementing the stream itself, you typically want every late subscriber to immediately see the current state. The pattern:

```swift
private var continuations: [UUID: AsyncStream<State>.Continuation] = [:]
private var current: State = .initial

func states() async -> AsyncStream<State> {
    AsyncStream { continuation in
        let id = UUID()
        continuation.yield(current)              // replay
        continuations[id] = continuation
        continuation.onTermination = { @Sendable [weak self] _ in
            guard let self else { return }
            Task { await self.removeContinuation(id) }
        }
    }
}

private func transition(to next: State) {
    current = next
    for c in continuations.values { c.yield(next) }
}

private func removeContinuation(_ id: UUID) {
    continuations.removeValue(forKey: id)
}
```

## Caveats

- `AsyncStream` requires macOS 10.15+. SPM packages that don't list `.macOS(...)` in `platforms` default to a version where it's unavailable; local `swift build` on macOS will fail. Add `.macOS(.v13)` (or your minimum). Linux CI is unaffected.
- Tests that capture `var` arrays inside `Task { ... }` will trip `[#SendingRisksDataRace]`. Wrap the accumulator in a tiny in-test `actor` rather than fighting the diagnostic.
- If your consumer subscribes AFTER calling the producer's `start(...)`, the first synchronous emissions are lost. Subscribe first, start second. Cost a heart-rate sample in `testExplicitScenarioReplaysDeterministicFieldUpdates` before this pattern was applied.
- **Region-based isolation checker false positive on `Self`-capture in cross-actor closures (Swift 6.0):** A test helper that builds a `Task { for await x in stream { ... Self.helper(x) ... } }` where the enclosing type is a non-`Sendable` `XCTestCase` subclass triggers `error: pattern that the region-based isolation checker does not understand how to check. Please file a bug`. Workaround: hoist the helper out to a file-private free function so the closure no longer captures the test class. Adding `[capture]` lists or making the wrapper `async` does NOT help; only de-`Self`-ing does.

## Parallel-spawn → independent-merge → final-reconciliation flow

Pattern when three branches go out in parallel and each stubs the other two's surfaces:

1. **While both upstreams are open, stub their types additively.** Do not `import` from a sibling branch. Define your own minimal protocol with a different module path (e.g. `Protocols/HealthKitSubstrate.swift` while the canonical `Workout/WorkoutHealthSubstrate.swift` is in flight). Two concurrent compilations succeed independently.
2. **When upstreams merge, audit for redeclaration via grep before rebasing.** `git rebase` only flags textual conflicts; a duplicate type declaration in a *different* file path will rebase clean and then fail to build. Run `grep -lR <stub-type-name>` against the post-merge tree before `git add`-ing anything.
3. **Adapt the mocks to the canonical surface, never the canonical surface to the mocks.** The just-merged types are locked. Throw away your stubs (`git rm`), throw away your stub-typed wrapper (`git checkout --ours` if it was an add/add conflict), and rewrite mocks to conform to the real protocol shape.
4. **Distinguish "canonical happy-path stub" (lives in the source target) from "QA scenario mock" (lives in the test target).** Canonical stubs are simple, predictable, and meant for SwiftUI previews and basic unit tests. QA mocks add scenario controls, failure injection, and recording for after-the-fact assertions. Both can coexist; document the divergence in a decision-inbox file so the team knows when to reach for which.
5. **Preserve any Scribe / log commits already on top of your feature work.** Default `git rebase main` replays them in order; the append-only `merge=union` driver in `.gitattributes` handles `decisions.md` / `history.md` / `log/` / `orchestration-log/` automatically.

## Provenance

- Discovered while building `MockGlassesFrame` and `FakeHealthKitSubstrate` in `feat/integration-mocks` (Amber, 2026-05-15).
- Reconciled against canonical `GlassesFrameTransport` (Weiss, PR #5) and `WorkoutHealthSubstrate` + `WorkoutController` (Laughlin, PR #7) post-merge (Amber, 2026-05-15).
- Confirmed against Swift 6.0 (CI Linux container) and 6.3.2 (local macOS).
