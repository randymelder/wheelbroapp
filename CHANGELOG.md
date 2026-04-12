# WheelBro — Changelog

All notable changes to WheelBro are documented here.

---

## [Unreleased]

### Added
- **No-connection overlay on TTE tab** — when BLE is disconnected and Simulator is off, a full-screen overlay with a red indicator and "Open Settings" button appears. Tapping the button navigates directly to the Settings tab.
- **`AppConstants.verboseLogging`** — single bool constant in `Constants.swift` that gates all console debug output. Set to `false` to silence every `wbLog()` call at zero cost (`@inline(__always)`).
- **`wbLog()` helper** — drop-in replacement for `print()` throughout both manager files. All 38 call sites replaced.
- **About tab** — displays app version, build number, vehicle compatibility, and copyright information. Tab order: TTE (0), Data (1), Settings (2), About (3).
- **`Constants.swift`** — centralised file replacing all magic numbers and string literals with named constants across `BLEConstants`, `VehicleConstants`, `UIConstants`, `AppConstants`, `ATCommand`, `OBDCommand`, `ELM327Response`, `OBDKey`, `OBDLogPID`, `PIDCode`, `DateFormat`, `UserDefaultsKey`, `Tab`, `AppInfo`.
- **PID Discovery (Phase 1 + Phase 2)** — bitmask range queries identify supported PIDs; each discovered PID is then polled for its current value. Export includes `pid`, `description`, and `value` columns.
- **`pid` column in log entries** — `LogEntry.pid` stores the OBD command string that produced each row (e.g. `010C`, `012F`, `ATRV`, `derived`). Included in CSV export header.
- **Disconnect button in Settings** — full-width red button, visible only when a BLE device is connected.
- **Clear log after export** — confirmation alert offered when the log export sheet is dismissed.
- **1-second TTE heartbeat** — `.task`-based async loop increments `tickCount` every second, triggering a numeric content transition on the TTE display. Stable across re-renders (not restarted by state changes).

### Changed
- **OBD protocol: `ATSP0` → `ATSP6`** — hardcoded to ISO 15765-4 CAN, 11-bit ID, 500 kbaud (the correct protocol for Jeep Wrangler JK). `ATSP0` (auto-detect) caused indefinite `SEARCHING…` / `STOPPED` responses on the IOS-Vlink adapter with this vehicle.
- **Response-driven PID polling** — each valid OBD response immediately triggers the next `pollNextPID()` call. The 5-second timer is replaced by a 1.5-second watchdog that fires only when the adapter goes silent (lost packet, `NODATA` without prompt). Cycles through all PIDs as fast as the adapter responds.
- **VIN integrated into poll cycle** — `OBDCommand.requestVIN` added as the 8th entry in `pidSequence`. Eliminates the race condition where a simultaneous one-shot `readVIN()` + `pollNextPID()` caused the ELM327 to drop the multi-frame ISO-TP VIN response.
- **BLE device list shows all peripherals** — device filtering removed; all discovered BLE peripherals are shown, sorted alphabetically. Resolves missing IOS-Vlink entries caused by service-UUID filtering.
- **Split RX/TX BLE characteristics** — `obdCharacteristic` split into `obdNotifyChar` (subscribe, UUIDs: FFE1, 2AF0, FFF1, BEF1, 18F1) and `obdWriteChar` (write, UUIDs: FFE1, 2AF1, FFF1, BEF1, 18F1). Supports both combined (FFE0/FFE1) and split (18F0/2AF0+2AF1) adapter types.
- **Export format: `.csv` → `.txt`** — both log and discovery exports use `.txt` extension.
- **Export delivery: file URL → `NSItemProvider`** — exports now pass content inline via `NSItemProvider(item: csv as NSString, typeIdentifier: "public.plain-text")` with `suggestedName`. Eliminates `NSCocoaErrorDomain Code=256` errors caused by `UIActivityViewController` failing to read sandboxed file URLs.
- **VIN decode: accepts printable ASCII only** — `decodeVINHex` guard changed from `byte > 0` to `byte >= 0x20 && byte < 0x7F`. Vehicles that return all `0xFF` fill bytes for Mode 09 (VIN not stored in OBD-II register) now display "Not available" instead of "ÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿ".
- **Multi-frame VIN parsing** — parser handles single-frame (`490201…`), first-frame (`0:4902…`), and continuation frames (`N:XX…`). ISO-TP byte-count header lines (`014`, `008`, etc.) are silently discarded.
- **`SEARCHING` / `STOPPED` handling** — these ELM327 tokens are now caught before `parseOBDLine` and counted. A diagnostic warning prints once on first occurrence and every 10 cycles thereafter.
- **Copyright / company name** — updated from "WheelBro LLC" to "RCMAZ Software, LLC" throughout all views and the README.
- **Logging default: off** — `isLoggingEnabled` is explicitly written as `false` to `UserDefaults` on first launch. Previously relied on `UserDefaults.bool` returning `false` for an absent key, which was correct but implicit.
- **Immediate first poll on connect** — `startPIDPolling()` calls `pollNextPID()` once before arming the watchdog timer, so live values appear immediately after the AT init sequence completes.

### Fixed
- **SwiftData migration crash** (`NSCocoaErrorDomain Code=134110`) — `LogEntry.pid` changed from `var pid: String` to `var pid: String = ""`. SwiftData's lightweight migration engine uses the property-level default to backfill existing rows; the `init` parameter default is not visible to it.
- **TTE / DTE values stuck at zero** — removed `@State var fuelText: Double?` and `@State var dteText: Double?` snapshot vars. Once set to `Optional(0.0)` on the first tick, the `??` operator never fell through to the live `obdManager` values. Cards now read `obdManager.distanceToEmpty` and `obdManager.fuelLevel` directly.
- **1-second ticker restarting on every re-render** — `Timer.publish(...).autoconnect()` declared as a `struct` property was recreated on every state change, resetting the countdown each tick. Replaced with a `.task` async loop pinned to the view's identity in the hierarchy.
- **PID discovery off-by-one value association** — `processLine`'s value-polling branch now only advances when the response starts with the expected `41XX` prefix for `currentValuePollPID`, or contains `NODATA`/`ERROR`. Stale in-flight Phase 1 responses are silently discarded.
- **Logging timer not starting on BLE connect** — `isConnected` now has `didSet { handleLoggingChange() }` so the timer starts immediately when BLE connects, not only when the logging toggle is flipped.
- **Duplicate `switch` case compiler warning** — removed duplicate `"31"` case in `decodePIDValue`.

---

© 2026 RCMAZ Software, LLC. All Rights Reserved.
