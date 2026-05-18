# Glasses Pairing Diagnosis — v0.3.0-rc1 indefinite "Scanning…" (REWRITTEN)

**Author:** Weiss
**Date:** 2026-05-18T13:46:44-04:00 (rewrite; original 2026-05-18T13:40:57-04:00)

---

## ⚠️ PRIOR DIAGNOSIS RETRACTED

The previous version of this file blamed a watchOS platform restriction —
"`CBCentralManager` on watchOS silently no-ops against non-MFi peripherals
like ActiveLook" — and recommended a full pivot to phone-owned BLE with
WCSession state mirroring.

**That diagnosis was wrong.** Joe provided counter-evidence: the official
ActiveLook watch app pairs and connects to glasses directly from watchOS.
Apple Developer Forum thread/774914 describes a real but *narrower* problem
than I attributed to it.

Re-reading ActiveLook's own iOS SDK source (`ActiveLook/ios-sdk`,
`Sources/Classes/Public/ActiveLookSDK.swift`) on the way back to first
principles produced the actual root cause in two minutes. I should have
read the reference SDK before recommending an architectural pivot.

---

## TL;DR (corrected)

**Our `startScan()` filters with the ActiveLook command service UUID
(`0783B03E-…`). Engo 2 / ActiveLook glasses do NOT include that 128-bit
private service UUID in their BLE advertising payload — it lives only on
the GATT table you can read *after* connecting. A service-filtered scan
matches against the advertising packet, so `didDiscover` is never invoked.**

This is **not a watchOS restriction** — the same code would also fail on
iOS. ActiveLook themselves discovered and documented this in their SDK
source with a literal `// Scanning with services list not working` comment
(`ActiveLookSDK.swift:192`).

**Fix:** scan with `withServices: nil` and filter inside `didDiscover` by
**manufacturer data** (`kCBAdvDataManufacturerData` prefix `0xFA 0xDA` —
Microoled company ID).

**Effort:** ~10-line patch to `ActiveLookGlassesAdapter.swift`.

The platform-pivot recommendation in the prior diagnosis is withdrawn.

---

## What ActiveLook's SDK actually does

Source: `ActiveLook/ios-sdk@a39839f`, `Sources/Classes/Public/ActiveLookSDK.swift`.

### Scanning (line 192-194)

```swift
// Scanning with services list not working
centralManager.scanForPeripherals(withServices: nil,
                                  options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
```

### Filtering glasses (line 383-388)

```swift
private func peripheralIsActiveLookGlasses(peripheral: CBPeripheral,
                                           advertisementData: [String: Any]) -> Bool {
    if let manufacturerData = advertisementData["kCBAdvDataManufacturerData"] as? Data,
       manufacturerData.count >= 2 {
        return manufacturerData[0] == 0xFA && manufacturerData[1] == 0xDA
    }
    return false
}
```

This is invoked from `didDiscover` (line 549) as a guard. Everything else
gets ignored without a print.

### Known-device fast path (line 368, 240–298)

For already-paired glasses, they persist a `SerializedGlasses` blob (which
contains the peripheral's `UUID`) and reconnect via:

```swift
centralManager.retrievePeripherals(withIdentifiers: [gUUID]).first
// ... then later: dGlasses.connect(...) → centralManager.connect(peripheral)
```

No scan involved on the reconnect path at all.

### "Is it already connected?" check (line 395)

```swift
centralManager.retrieveConnectedPeripherals(
    withServices: [GenericAccessService, DeviceInformationService, BatteryService])
```

Uses **standard** GATT services (not the ActiveLook private one) because
the system tracks those across processes.

### Other corroborating facts

- `Package.swift` declares `.watchOS(.v6)` as a supported platform target.
  The SDK compiles for watchOS even though the included `demo-app` is iOS-only.
- No Bluetooth entitlement is referenced anywhere in the SDK — they use the
  default Central role like we do.

---

## Why our PR #42 hangs on "Scanning…"

`ARRunnerWatch/Glasses/ActiveLookGlassesAdapter.swift:208-209`:

```swift
let serviceUUID = CBUUID(string: ActiveLookGATT.commandService) // 0783B03E-…
central.scanForPeripherals(withServices: [serviceUUID], options: nil)
```

We pass a non-empty `withServices` list, but Engo 2 doesn't advertise that
service in its connectable advertising packet — so the system filter never
matches and `didDiscover` is never called. The 30-s timeout fires because
we genuinely never see the device. Identical symptom would occur on iOS.

**The forum thread/774914 I cited is real**, but it covers a different
failure mode (peripherals seen on iOS but truly invisible on watchOS even
with correct advertising). Our case is the simpler mistake: we filtered on
something the peripheral isn't broadcasting. I conflated the two.

---

## Joe's runtime-independence constraint

> The Watch must connect to the glasses and run the workout WITHOUT the
> iPhone being present at runtime. Pairing handoff phone→watch is fine.
> Runtime BLE on phone is NOT fine.

Given the actual root cause is fixable on watchOS, this constraint is
satisfiable without changing where BLE lives. Three patterns considered:

### Pattern X — Watch-only, scan + manufacturer filter (RECOMMENDED)

- Watch scans with `withServices: nil`, filters in `didDiscover` by
  `kCBAdvDataManufacturerData` prefix `0xFA 0xDA`.
- After first successful connect, persist the `peripheral.identifier`
  (UUID) to local UserDefaults (or App Group if we also want phone to
  read it for diagnostics).
- On every subsequent app launch, skip scan entirely:
  `central.retrievePeripherals(withIdentifiers: [savedUUID])` →
  `central.connect(peripheral)`. Reconnect is silent and fast.
- Pros: matches ActiveLook's own pattern; satisfies Joe's constraint
  directly; no phone involvement at any stage; smallest diff.
- Cons: pairing UX is on the watch's small screen. Workable — our
  existing `GlassesConnectView` already does the right state shape; only
  the underlying scan logic changes.

### Pattern Y — Pair on phone, watch retrieves known peripheral

- Phone scans + connects once (better large-screen pairing UX), persists
  the UUID into a shared App Group / Keychain shared group.
- Watch uses `retrievePeripherals(withIdentifiers:)` and goes straight to
  `connect()` — never scans at runtime.
- Pros: nicer initial-pair UX on phone; **the runtime path on watch is
  even simpler than Pattern X** (no scan, no manufacturer filter).
- Cons: extra phone-side surface to build and maintain; phone required
  in range exactly once (for first pair). Joe explicitly OK'd this.

### Pattern Z — Phone runtime BLE

Rejected by Joe's constraint. Removed from consideration.

---

## Recommendation

**Pattern X first, with the option to layer Pattern Y later as a UX
upgrade.** Concretely:

1. **Patch the scan call (PR #43, scope: ~10 lines + 1 test).**
   - `startScan()`: change `withServices: [serviceUUID]` →
     `withServices: nil` with `[CBCentralManagerScanOptionAllowDuplicatesKey: false]`.
   - Add `isActiveLookManufacturerData(_:)` helper checking the
     `0xFA 0xDA` prefix.
   - In `didDiscover`, guard on the manufacturer-data filter before
     stopping scan / connecting.
   - Unit test: feed advertisement-data dicts with/without `0xFA 0xDA`
     prefix; assert the helper accepts/rejects correctly. (No CoreBluetooth
     mocking required for the pure helper.)

2. **Persist `peripheral.identifier` after first successful connect.**
   - Already have `GlassesPairingPreferences` UserDefaults shim — add a
     `pairedPeripheralID: UUID?` slot next to the existing `hasPaired`
     flag.

3. **On `prepareGlassesIfNeeded()` / auto-reconnect, prefer
   `retrievePeripherals(withIdentifiers:)` over scanning.**
   - If we have a saved UUID and the system still knows the peripheral
     → skip scan, go straight to `connect(peripheral)`.
   - If not, fall back to the patched scan path.

4. **Optional follow-up (PR #44): Pattern Y phone-assisted pairing.**
   - Phone-side `GlassesConnectView` that scans + connects + transmits
     the discovered UUID to the watch via WCSession `updateApplicationContext`.
   - Watch stores it, immediately calls `retrievePeripherals(...)` →
     `connect()`. Phone irrelevant at run time.
   - This is a UX improvement, not a correctness requirement.

### Effort estimate

| Item                                              | Effort           |
|---------------------------------------------------|------------------|
| Pattern X scan fix + manufacturer filter + test   | ~½ day, 1 PR     |
| Persist + use `retrievePeripherals` known-device  | ~½ day, same PR  |
| Pattern Y phone-assisted pair handoff             | ~1-2 days, later PR |

No new dependencies. No signing or CI changes. No `project.yml` churn.

### Risks

- **`retrievePeripherals` returning `[]`** is normal if iOS/watchOS has
  evicted the peripheral from its cache (e.g., reboot, long idle). Fall
  back to the patched scan path — don't surface an error.
- **Manufacturer ID validation** — `0xFA 0xDA` is sourced from
  ActiveLook's own SDK; it's the Microoled BLE company ID. Worth a code
  comment citing the SDK file/line so a future reader can verify.
- **Background scanning** still requires a service-UUID filter per Apple's
  rules, so background discovery of a *new* (unpaired) device from the
  watch would not work. Our pairing flow is foreground-only (user opens
  the sheet), and runtime reconnects use `retrievePeripherals` (not scan),
  so we don't hit this limit.

---

## Lessons (for myself + future agents)

1. **Validate "platform limitation" hypotheses against shipping
   counter-examples *before* recommending a pivot.** ActiveLook ships a
   watch app — that's prima facie evidence the platform supports the
   use case. The forum thread I cited didn't justify ignoring that.
2. **Read the reference SDK source first.** A 30-second `grep
   scanForPeripherals` on `ActiveLook/ios-sdk` would have flipped my
   diagnosis. The literal `// Scanning with services list not working`
   comment is right there.
3. **Service-UUID filters in `scanForPeripherals` match against the
   ADVERTISING packet, not the GATT table.** A peripheral can expose a
   service post-connect without advertising it. Manufacturer-data
   filtering is the standard workaround for opaque vendor peripherals.

(Skill update for `.squad/skills/activelook-bluetooth-pairing/SKILL.md`
to follow during the Pattern X implementation PR — will retire the
`watchos-cbcentral-third-party-restriction` skill draft entirely.)
