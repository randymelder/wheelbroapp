# WheelBro — Change Journal

Changes requested by Randy Melder, in chronological order.

---

## 2026-04-10

### Add About tab to the app
**Date/Time:** 2026-04-10 20:44

**Requested:** Add a new "About" view to the app. Tab bar order should be TTE, Data, Settings, About. The About view should show app version and copyright info. Add the About navigation title to the navigation bar.

**Changes made:**
- `Views/AboutView.swift` — new file; displays app logo, version, build number, vehicle, and copyright footer. Includes a `NavigationStack` with a large "About" navigation bar title.
- `ContentView.swift` — tab order updated to TTE (0), Data (1), Settings (2), About (3). First-launch default tab updated from index 1 to index 2 to keep Settings as the first-launch destination.

---

### Previously requested features — applied to Xcode project
**Date/Time:** 2026-04-10 21:06

**Requested:**
1. Add a clear/delete option for the log after export.
2. Add a full-width red "Disconnect" button on Settings, visible only when paired with a BLE device.
3. On Settings BLE device list, filter out unsupported devices — only Vgate-compatible adapters shown.
4. Add a `pid` column to the log data model and include it in the CSV export.
5. Add a "Discover PIDs" button to Data view that queries the vehicle's supported PIDs and exports them as `wheelbro_discovery_*.csv`.

**Changes made:**
- `Models/LogEntry.swift` — added `pid: String` field (e.g. "010C", "012F", "ATRV", "derived").
- `Managers/OBDDataManager.swift` — updated `logCurrentValues()` to pass the correct PID string for each key when inserting `LogEntry` rows.
- `Managers/BluetoothManager.swift` — added `discoveredPIDs: [String]` and `isDiscoveringPIDs: Bool` state; added `discoverSupportedPIDs()`, `sendNextPIDDiscoveryCommand()`, and `parsePIDSupportResponse()` for Mode 01 PID discovery (queries 0100/0120/0140/0160); added `isPIDDiscoveryMode` handler in `processLine`; added `isVgateCompatible: Bool` computed property to `DiscoveredPeripheral`.
- `Views/SettingsView.swift` — BLE device list now filters to `isVgateCompatible` devices only with an explanatory message when non-compatible adapters are hidden; replaced Connection Control section with a conditional block (only shown when connected) containing the connected device name and a full-width red "Disconnect" button.
- `Views/DataView.swift` — added `@Environment(BluetoothManager.self)` and `@Environment(\.modelContext)`; CSV export header/rows now include `pid` column; log export sheet triggers a "Clear Log Data?" confirmation alert on dismiss; added "Discover PIDs" button (disabled when not connected) that calls `bleManager.discoverSupportedPIDs()` and exports results as `wheelbro_discovery_*.csv` with a 60-entry PID description table.

---

### Fix SwiftData migration crash on launch
**Date/Time:** 2026-04-10 21:22

**Requested:** Bug fix — app crashed at launch with `NSCocoaErrorDomain Code=134110` / `Validation error missing attribute values on mandatory destination attribute` after adding the `pid` column.

**Changes made:**
- `Models/LogEntry.swift` — changed `var pid: String` to `var pid: String = ""`. SwiftData's lightweight migration engine reads the property-level default to backfill existing rows; the `init` parameter default is invisible to it.

---

### About view cleanup and company name rebrand
**Date/Time:** 2026-04-10 21:27

**Requested:** Remove the Platform and Protocol rows from the About view info card. Replace "WheelBro, LLC" with "RCMAZ Software, LLC" everywhere in the app.

**Changes made:**
- `Views/AboutView.swift` — removed `Platform / "iOS"` and `Protocol / "OBD-II / ELM327 BLE"` rows (and their dividers) from the info card. Copyright line updated to "© 2026 RCMAZ Software, LLC".
- `Views/DataView.swift` — footer copyright updated to "© 2026 RCMAZ Software, LLC. All Rights Reserved."

---

### Update README — IP owner corrected to RCMAZ Software, LLC
**Date/Time:** 2026-04-10 21:35

**Requested:** Update the README to reflect that RCMAZ Software, LLC is the owner of all app assets and intellectual property.

**Changes made:**
- `README.md` — License section updated; "WheelBro LLC" replaced with "RCMAZ Software, LLC".

---

## 2026-04-11

### BLE device list — show all devices, sort by name
**Date/Time:** 2026-04-11

**Requested:** The "IOS-Vlink" adapter was not appearing in the device list due to overly-aggressive filtering. Remove all device filtering; show every BLE peripheral sorted alphabetically by name.

**Changes made:**
- `Managers/BluetoothManager.swift` — `startScanning` changed to `withServices: nil` (scans all devices). Removed `isVgateCompatible` computed property from `DiscoveredPeripheral`.
- `Views/SettingsView.swift` — replaced filtered `supportedPeripherals` computed property with a plain sorted list (`bleManager.discoveredPeripherals.sorted { $0.name < $1.name }`). Updated empty-state label to "No devices found — tap Scan to search".

---

### Split RX/TX BLE characteristics for vLinker / IOS-Vlink adapters
**Date/Time:** 2026-04-11

**Requested:** After connecting to IOS-Vlink, the PID Discovery spinner never completed — the root cause was that 18F0-service adapters use separate notify-only (2AF0) and write-only (2AF1) characteristics.

**Changes made:**
- `Managers/BluetoothManager.swift` — split `obdCharacteristic` into `obdNotifyChar` (subscribe) and `obdWriteChar` (write). Replaced `knownOBDCharacteristicUUIDs` with two independent sets `knownNotifyUUIDs` / `knownWriteUUIDs`. Rewrote `didDiscoverCharacteristics` to assign each role independently so either a combined (FFE1) or split (2AF0/2AF1) adapter works. Fixed all write call sites to use `obdWriteChar`.

---

### PID Discovery — Phase 2 live value polling
**Date/Time:** 2026-04-11

**Requested:** After discovering which PIDs the vehicle supports, also query the current value for each discovered PID and include those values in the discovery export.

**Changes made:**
- `Managers/BluetoothManager.swift` — added `pidValueResults: [String: String]`, `isValuePollingMode`, `valuePollingQueue`, `currentValuePollPID`. `sendNextPIDDiscoveryCommand` transitions to Phase 2 when Phase 1 is complete. Added `sendNextValuePollingCommand()` with 1.5 s per-PID timeout (`valuePollingTimeoutWork: DispatchWorkItem`). Added `parsePIDValue(pid:response:)` and `decodePIDValue(pidHex:data:)` covering ~40 SAE J1979 Mode 01 PIDs. Added 90 s overall safety timeout.
- `Views/DataView.swift` — discovery CSV export updated to three columns (`pid`, `description`, `value`); value column populated from `bleManager.pidValueResults`.

---

### PID Discovery — off-by-one value association fix
**Date/Time:** 2026-04-11

**Requested:** Analysis of a discovery export showed values stored against the wrong PID (e.g. `0106` received PID `0105`'s response). Root cause: `processLine`'s value-polling branch advanced on any line including stale in-flight Phase 1 responses.

**Changes made:**
- `Managers/BluetoothManager.swift`:
  - `processLine` value-polling branch now only advances when the response line starts with the expected `41XX` prefix for `currentValuePollPID`, or contains NODATA/ERROR. Stale lines are silently discarded.
  - `sendNextValuePollingCommand` arms a `DispatchWorkItem` timeout (1.5 s); cancelled immediately on a valid response.
  - `responseBuffer` cleared at Phase 1 → Phase 2 transition to discard any in-flight leftovers.
  - `disconnect()` and the 90 s safety timeout both cancel and nil the timeout work item.

---

### Logging — fix no rows captured when logging enabled
**Date/Time:** 2026-04-11

**Requested:** Data logging was enabled in Settings but no rows appeared in the Data view.

**Changes made:**
- `Managers/OBDDataManager.swift`:
  - Added `receivedKeys: Set<String>` tracking which OBD keys have been received at least once from the vehicle. `updateFromOBD` inserts into `receivedKeys` on every update.
  - `logCurrentValues` skips any key not in `receivedKeys` when in live (non-simulator) mode, preventing zero-filled rows for unsupported PIDs.
  - `isConnected` now has `didSet { handleLoggingChange() }` so the logging timer starts immediately when BLE connects.
  - `startLoggingIfNeeded` calls `stopLogging()` in its guard-fail path to cleanly kill the timer on disconnect.
  - `resetValues()` clears `receivedKeys` so a fresh connection starts clean.

---

### Export — change file extension to `.txt`, standardise filename prefix
**Date/Time:** 2026-04-11

**Requested:** Save export files as `.txt` instead of `.csv`. Log export prefix should be `wheelbro_log_`; discovery export prefix should be `wheelbro_discovery_`.

**Changes made:**
- `Views/DataView.swift` — both export paths updated: `wheelbro_log_<ts>.txt` and `wheelbro_discovery_<ts>.txt`.

---

### TTE view — 1-second live update ticker
**Date/Time:** 2026-04-11

**Requested:** Values on the TTE (Time to Empty) view should update every second rather than waiting for OBD data to change.

**Changes made:**
- `Views/TTEView.swift` — added `import Combine`. Added a `Timer.publish(every: UIConstants.tteTickInterval, ...)` publisher (`ticker`) and `@State var tickCount` incremented by `.onReceive(ticker)`. The TTE `.animation` value binding was changed from `obdManager.fuelLevel` to `tickCount`, forcing a display refresh and numeric transition every second.

---

### Duplicate switch-case warning fix
**Date/Time:** 2026-04-11

**Requested:** Compiler warning: "Literal value is already handled by previous pattern; consider removing it."

**Changes made:**
- `Managers/BluetoothManager.swift` — `decodePIDValue` had `case "21", "31"` where `"31"` was already covered by `case "1F", "31"` above it. Removed the duplicate; the `"21"` case (Distance Traveled with MIL on) now stands alone.

---

### Constants.swift — replace all magic numbers and string literals with named constants
**Date/Time:** 2026-04-11

**Requested:** Create a `Constants.swift` file that takes inventory of all magic numbers and replaces them with self-describing constant variables. Follow-up: extend to all string literals across every file.

**Changes made:**
- `Constants.swift` — new file. Defines the following caseless enums:
  - `BLEConstants` — scan timeout, PID poll interval, discovery timeout, command delays, value-poll timeout, bitmask bit count.
  - `VehicleConstants` — simulator interval, logging interval, log retention window, tank gallons, avg MPG, TTE speed/RPM references, idle GPH, simulated VIN.
  - `UIConstants` — TTE tick interval.
  - `PIDCode` — 42 named constants for SAE J1979 Mode 01 2-char PID hex codes used in `decodePIDValue`.
  - `ATCommand` — all 8 ELM327 AT initialisation and utility command strings (with `\r`).
  - `OBDCommand` — all 11 OBD-II query command strings for live data, VIN, DTCs, and PID discovery.
  - `ELM327Response` — 9 ELM327 response token strings (`NODATA`, `ERROR`, `>`, `41`, `4902`, etc.).
  - `OBDKey` — 9 telemetry key strings used in `updateFromOBD` and `LogEntry`.
  - `OBDLogPID` — 9 PID label strings stored in the `LogEntry.pid` column.
  - `DateFormat` — date, time, and combined date-time format strings.
  - `UserDefaultsKey` — all 4 UserDefaults / AppStorage key strings.
  - `Tab` — tab index integers (tte=0, data=1, settings=2, about=3).
  - `AppInfo` — vehicle name, copyright strings.
- `Managers/BluetoothManager.swift` — all numeric delays, bitmask range, command strings, response markers, and PID hex literals replaced with the above constants.
- `Managers/OBDDataManager.swift` — UserDefaults keys, date format strings, OBD key strings, log PID strings, and vehicle calculation constants replaced.
- `Views/ContentView.swift` — UserDefaults key and tab indices replaced.
- `Views/SettingsView.swift` — AppStorage key and vehicle name replaced.
- `Views/AboutView.swift` — vehicle name and copyright strings replaced.
- `Views/DataView.swift` — copyright string replaced.
