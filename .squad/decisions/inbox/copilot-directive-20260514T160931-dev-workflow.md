### 2026-05-14T16:09:31-04:00: User directive — dev workflow split
**By:** Joe (via Copilot)
**What:** AR-Runner development is split across two environments:
  - **Windows (this repo's primary dev box)** — Squad coordination, agent-driven code generation, editing Swift source / project.yml / docs / Markdown, git operations, PR review on GitHub. This is where THINKING and WRITING happen.
  - **Mac** — Running `xcodegen generate`, opening `AR-Runner.xcworkspace`, compiling Swift against Apple frameworks (HealthKit/WatchKit/WidgetKit/CoreBluetooth), running watchOS/iOS Simulator, BLE testing against real ActiveLook glasses, code signing, TestFlight, App Store. This is where VERIFICATION and DEPLOYMENT happen.
  Cadence: spawn agents → review PR → switch to Mac → build/run/verify → file issue or come back to Windows → fix → repeat.
**Why:** User request — practical operational pattern for the project. The ARRunnerCore SPM package is theoretically Linux-compileable (pure Swift, no Apple frameworks), so a future CI lane could `swift test` core models on Linux GitHub Actions runners — but that's an optimization for later. For now, Mac is the build authority.
