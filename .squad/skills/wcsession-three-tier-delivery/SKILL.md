# Skill: WCSession Three-Tier Delivery

**Author:** Laughlin (watchOS Dev)
**Established:** 2026-05-15

## Problem

`WCSession` exposes three transport paths and which one to use depends on the message's freshness vs durability tradeoff. Picking the wrong path either drops important transitions or floods the system with stale ticks.

## Pattern

Pick the path per-message based on two tags: **latest-only** vs **queued**, and on the live **reachability** of the peer.

| Path                          | Reachability needed | Storage      | Use for                        |
|-------------------------------|---------------------|--------------|--------------------------------|
| `sendMessageData`             | Yes (in-foreground) | None         | Live ticks while reachable     |
| `updateApplicationContext`    | No                  | Latest only  | Live ticks while unreachable   |
| `transferUserInfo`            | No                  | FIFO queue   | Lifecycle / important events   |

```swift
private func transmit(_ message: WCMessage,
                      preferLatestOnly: Bool = false,
                      preferQueued: Bool = false) async {
    let payload = try? JSONEncoder().encode(message)
    guard let payload, let session else { return }

    if session.isReachable {
        session.sendMessageData(payload, replyHandler: nil) { _ in }
        return
    }
    if preferLatestOnly {
        try? session.updateApplicationContext(["wcMessage": payload])
    } else {
        session.transferUserInfo(["wcMessage": payload])
    }
}
```

Caller wraps it:
```swift
func send(snapshot: WorkoutTickMessage) async {
    await transmit(.workoutSnapshot(snapshot), preferLatestOnly: true)
}
func sendLifecycle(_ event: LifecycleEvent) async {
    await transmit(.workoutLifecycle(event), preferQueued: true)
}
```

## Why each tier

- **`sendMessageData`** is the lowest latency but requires the peer to be reachable (foreground or in pocket). Drops silently when not reachable.
- **`updateApplicationContext`** is latest-wins; great for live ticks because we don't care about old ticks. Survives app restart.
- **`transferUserInfo`** is queued; great for lifecycle transitions because we MUST not lose "started" or "ended". Delivered eventually even if the peer was off.

## Anti-patterns observed

- Sending live 1 Hz ticks via `transferUserInfo` → queue blow-up.
- Sending lifecycle events via `sendMessageData` only → lost transitions when phone was in pocket / asleep.
- Not encoding to `Data` first → `WCMessage` codable types include `Date` and enums; using `[String: Any]` directly loses precision and round-trip.

## Receiver-side counterpart

Decode the same `Data` blob from any of three delegate callbacks:
```swift
func session(_:, didReceiveMessageData: Data)        // sendMessageData
func session(_:, didReceiveApplicationContext: [String: Any])  // updateApplicationContext (key: "wcMessage")
func session(_:, didReceiveUserInfo: [String: Any])  // transferUserInfo (key: "wcMessage")
```

Republish through a single `AsyncStream<WCMessage>` so view-models don't care which path delivered.

## When to reuse

Any time a Swift app has **two roles** of inter-device traffic — one high-frequency-low-importance (telemetry / live mirror) and one rare-but-critical (lifecycle / config). The same payload type can ride all three transports as long as the encoded blob is `Data`.
