# Contributing

Thanks for your interest in AR-Runner.

## Project status

AR-Runner is in pre-v0.1 scaffolding. **Issues for discussion are welcome** —
please use [GitHub Issues](https://github.com/jkrilov/AR-Runner/issues) to share
ideas, report bugs, or ask about direction.

**Pull requests from outside contributors are paused until v0.1 lands** so the
architecture (D1–D9 in [`.squad/decisions.md`](.squad/decisions.md)) can settle
without drive-by churn. Once v0.1 ships, this policy will be revisited and this
file updated. Watch the [Releases page](https://github.com/jkrilov/AR-Runner/releases) —
when v0.1 is tagged, this contributor policy will be revisited and updated here.

## How AR-Runner is built

- **Swift 6** with strict concurrency (see decision D8).
- **watchOS 11** target (`ARRunnerWatch`) — workout authority and BLE owner.
- **iOS 18** target (`ARRunnerPhone`) — configuration cockpit and post-run review.
- **WidgetKit** target (`ARRunnerWidgets`) — Smart Stack surface.
- **Shared Swift package** (`ARRunnerCore`) — sport-agnostic models, messaging,
  storage protocols.
- **ActiveLook iOS SDK** over BLE for the AR HUD (Apache-2.0; consumed via SPM).
- **License:** [Apache 2.0](LICENSE).

By submitting a PR (once they reopen), you agree that your contribution is
licensed under the Apache License 2.0.

## About the Squad system

This repo is built using [Squad](https://github.com/bradygaster/squad), an AI
agent orchestration framework. The `.squad/` directory contains the persistent
team configuration, decision ledger, and session history. You do not need to
use Squad to contribute — but `.squad/decisions.md` is a useful read for
understanding why the architecture is shaped the way it is.
