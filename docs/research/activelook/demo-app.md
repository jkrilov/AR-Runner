# ActiveLook Demo App

## Purpose
Reference implementation demonstrating SDK usage for scanning, connecting to, and controlling ActiveLook AR glasses via BLE with example commands.

## Platform & License
- **Language/Platform:** Swift (iOS), Kotlin (Android)
- **License:** Open source (Apache 2.0 implied from iOS SDK parent)
- **Last Activity:** Main branch shows 78 commits; last commit date not explicitly visible but repository is active

## Activity Signal
**Active** — Maintained repository with examples for both iOS and Android platforms, regularly referenced in official docs.

## Key Folders/Files
- `ios/` — Xcode project demonstrating iOS SDK integration; uses CocoaPods
- `android/` — Android Studio project; companion to iOS
- `README.md` — Brief setup instructions for iOS (Xcode) and Android (Android Studio)

## What We'd Lift/Reference/Learn
- **UI/UX patterns** — scan → discover → connect → command flow serves as template for AR-Runner's phone/watch integration
- **Error handling** — connection lifecycle (onGlassesConnected, onGlassesDisconnected, onConnectionError callbacks)
- **Command examples** — power, luma, draw shapes, text, battery polling—direct mappings to HUD updates
- **BLE state management** — demonstrates singleton `ActiveLookSDK.shared` pattern for maintaining glasses connection

## Constraints & Architecture Notes
- iOS SDK available via CocoaPods or Swift Package Manager; **no vendored source in demo-app**
- Demo is mobile-centric (phone controls glasses)—no mention of watchOS as control device
- Simple sequential command model; no built-in batching or rate limiting for high-frequency updates (e.g., live metrics)
- Assumes app owns the BLE connection lifecycle start-to-finish

## Open Questions for AR-Runner
- Should the Watch run the demo logic directly (via SDK bridged to watchOS) or proxy through iPhone?
- How to handle metric refresh rates (e.g., HR/cadence 1–5 Hz) given BLE latency?
