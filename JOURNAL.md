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

### TTE view — fix immediate update on BLE connect and reliable 1-second ticker
**Date/Time:** 2026-04-11

**Requested:** Two bugs: (1) TTE view did not start showing values immediately after a BLE connection — values took ~10 seconds to appear. (2) TTE view was not updating every second; updates were taking ~10 seconds.

**Root causes:**
- `startPIDPolling()` used `Timer.scheduledTimer(withTimeInterval: 5.0, ...)` which does not fire until the first full interval elapses. After the AT init + VIN read sequence, the first live-data PID poll was delayed an additional 5 seconds, producing the observed ~10 second total delay.
- `private let ticker = Timer.publish(...).autoconnect()` was declared as a property on the SwiftUI `struct` (value type). Every state change that triggers a re-render recreates the struct instance, creating a new `TimerPublisher`. With `.autoconnect()`, each new publisher restarts the 1-second countdown, so the timer reset after every tick and never delivered a second fire reliably.

**Changes made:**
- `Managers/BluetoothManager.swift` — `startPIDPolling()` now calls `pollNextPID()` once immediately before setting up the repeating timer, so live values arrive the moment polling starts.
- `Views/TTEView.swift` — removed `import Combine` and the `private let ticker` property. Replaced `.onReceive(ticker)` with a `.task { while !Task.isCancelled { try? await Task.sleep(for: .seconds(UIConstants.tteTickInterval)); tickCount += 1 } }` block. SwiftUI's `.task` modifier pins its async context to the view's identity in the hierarchy, not to the struct instance, so it is never restarted by re-renders — only when the view appears or disappears.

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

---

### TTEView — fix values stuck at zero
**Date/Time:** 2026-04-11

**Requested:** TTE and DTE values on TTEView remained zero even when OBD data was flowing.

**Root cause:** `@State private var fuelText: Double?` and `@State private var dteText: Double?` were set to `Optional(0.0)` on the first `.task` tick. The `??` operator saw a non-nil value and never fell through to `obdManager.distanceToEmpty` / `obdManager.fuelLevel`.

**Changes made:**
- `Views/TTEView.swift` — removed `fuelText` and `dteText` `@State` vars. OBD value cards now read `obdManager.distanceToEmpty` and `obdManager.fuelLevel` directly. Enhanced `statusLabel` to return "Connected — turn ignition ON" when BLE is connected but all ECU values (fuel, RPM, speed) are zero.

---

### BLE — fix ATSP0 failing to detect vehicle protocol (SEARCHING/STOPPED on all PIDs)
**Date/Time:** 2026-04-11

**Requested:** All OBD values stayed at zero — SEARCHING/STOPPED returned for every Mode 01 PID even with ignition on.

**Root cause:** `ATSP0` (auto-detect) scans through all protocols and fails on the IOS-Vlink adapter for the Jeep Wrangler JK, returning SEARCHING indefinitely. The correct protocol must be set explicitly.

**Changes made:**
- `Constants.swift` — `ATCommand.autoProtocol` changed from `"ATSP0\r"` to `"ATSP6\r"` (ISO 15765-4 CAN, 11-bit ID, 500 kbaud — correct for Jeep JK). Added `ELM327Response.searching = "SEARCHING"` and `ELM327Response.stopped = "STOPPED"`.
- `Managers/BluetoothManager.swift` — SEARCHING and STOPPED tokens added to the discard guard in `processLine()`. Added `consecutiveSearchingCount` to rate-limit the diagnostic warning to once on first occurrence then every 10 cycles.

---

### BLE — fix slow polling (1 PID per 5 s → response-driven cycling)
**Date/Time:** 2026-04-11

**Requested:** Only one PID was being queried per second; all PIDs should cycle as fast as the adapter responds.

**Root cause:** `pollNextPID()` was called only by the 5-second timer. With 7 PIDs, a full cycle took ~35 s.

**Changes made:**
- `Managers/BluetoothManager.swift` — `pollNextPID()` is now called at the end of `processLine()`'s normal path (response-driven). The timer is reduced to `BLEConstants.pidPollInterval` (1.5 s) as a watchdog only — it fires when the adapter hasn't responded (e.g. NODATA with no prompt, lost packet) to prevent the cycle from stalling. `startPIDPolling()` calls `pollNextPID()` once immediately so values appear without waiting for the first timer interval.

---

### BLE — fix VIN not updating (race condition with response-driven polling)
**Date/Time:** 2026-04-11

**Requested:** VIN field never updated. No `[OBD VIN]` log lines appeared despite all other OBD values flowing correctly.

**Root cause:** `readVIN()` was called immediately after `startPIDPolling()` in `sendNextInitCommand`. The first `pollNextPID()` call also fired immediately, sending `010C\r` and `0902\r` to the ELM327 in rapid succession. The ELM327 processed the VIN request but its multi-frame response (ISO-TP segments `0:490201…`, `1:…`, `2:…`) was displaced by the incoming polling commands and never arrived in the BLE notification buffer.

**Changes made:**
- `Managers/BluetoothManager.swift`:
  - `OBDCommand.requestVIN` appended to `pidSequence` as the 8th entry, so VIN is requested once per full poll cycle (~8 responses) rather than as a fire-and-forget one-shot.
  - `readVIN()` call removed from `sendNextInitCommand()`; `readVIN()` helper left in place but is no longer called.
  - Added multi-frame VIN parsing in `parseOBDLine()`: single-frame `490201XX…`, first-frame `0:4902XX…`, continuation frames `N:XX…`, and ISO-TP byte-count header silencer (`014`, `008`, etc.).
  - Added `decodeVINHex(_ hex: String)` helper that converts hex pairs to ASCII and calls `updateFromOBD(key: OBDKey.vin, value:)` once ≥10 valid characters are decoded.
  - Added `vinFrameBuffer: String` and `isCapturingVIN: Bool` private state; both reset in `disconnect()`.
  - Data-flow comment at top of file updated to describe VIN-in-cycle approach.

---

### BLE — fix VIN displaying garbage characters (0xFF fill bytes from ECU)
**Date/Time:** 2026-04-11

**Requested:** VIN updated but displayed "ÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿ" — garbage characters.

**Root cause:** The Jeep JK ECU returns `NODI=0x00` and all `0xFF` fill bytes for Mode 09 PID 02, indicating the VIN is not stored in the OBD-II VIN register. `decodeVINHex` only filtered null bytes (`byte > 0`); `0xFF` = 255 passed through and decoded to the `ÿ` character (U+00FF).

**Changes made:**
- `Managers/BluetoothManager.swift` — `decodeVINHex` guard changed from `byte > 0` to `byte >= 0x20, byte < 0x7F` (printable ASCII range). Added an explicit branch: if `vinStr` is empty after filtering fill bytes, logs the issue and sets VIN to `"Not available"` rather than leaving the field blank.

---

### DataView — fix export share sheet failing with NSCocoaErrorDomain Code=256
**Date/Time:** 2026-04-11

**Requested:** Tapping "Discover PIDs" produced errors: `Failed to request default share mode for fileURL ... Code=-10814` and `error fetching item for URL ... NSCocoaErrorDomain Code=256 "The file couldn't be opened."` The share sheet never appeared.

**Root cause:** `UIActivityViewController` was given a sandboxed `file://` URL to the app's Documents directory. The system's share sheet process cannot read that URL directly — it fails with `NSFileReadUnknownError (256)`. The `NSOSStatusErrorDomain Code=-10814` (LaunchServices) is a secondary symptom: the system couldn't find a default app handler for `.txt` via the file URL path.

**Changes made:**
- `Views/DataView.swift` — replaced file-write + file-URL pattern with `NSItemProvider(item: csv as NSString, typeIdentifier: "public.plain-text")` + `provider.suggestedName`. The CSV content is passed inline to `UIActivityViewController`; no file is written to disk. `suggestedName` is used by Files.app as the default save name (`wheelbro_log_*.txt` / `wheelbro_discovery_*.txt`). State vars changed from `exportURL: URL?` / `discoveryURL: URL?` to `exportItems: [Any]` / `discoveryItems: [Any]`. Applied to both the log export and the discovery export paths.

---

### Logging default off; console output gated on AppConstants.verboseLogging
**Date/Time:** 2026-04-11

**Requested:** Data logging should be disabled by default. All console `print()` messages should be toggleable via a single bool constant in `Constants.swift`.

**Changes made:**
- `Constants.swift` — added `enum AppConstants` with `static let verboseLogging: Bool = true`. Added top-level `func wbLog(_ message: String)` marked `@inline(__always)` — a drop-in for `print` that no-ops when `verboseLogging` is `false`.
- `Managers/BluetoothManager.swift` — all `print(` calls replaced with `wbLog(` (32 call sites).
- `Managers/OBDDataManager.swift` — all `print(` calls replaced with `wbLog(` (6 call sites). `init` now explicitly writes `false` to `UserDefaultsKey.isLoggingEnabled` on first launch (matching the pattern used for `isSimulatorOn`), making the off-by-default intent unambiguous.

---

### TTEView — no-connection overlay with Settings navigation
**Date/Time:** 2026-04-11

**Requested:** When the user opens the TTE tab and no BLE device is connected (and simulator is off), warn them and show the Settings view.

**Changes made:**
- `Views/TTEView.swift` — added `@Binding var selectedTab: Int`. Added `isDisconnected` computed property (`!obdManager.isSimulatorOn && !bleManager.isConnected`). Added `disconnectedOverlay` sub-view: a semi-transparent dark overlay with a red bolt icon, explanatory text, and a yellow "Open Settings" button that sets `selectedTab = Tab.settings`. Overlay applied via `.overlay { if isDisconnected { disconnectedOverlay } }` with a fade transition. Preview updated to supply `.constant(Tab.tte)`.
- `Views/ContentView.swift` — `TTEView()` updated to `TTEView(selectedTab: $selectedTab)` to pass the binding.
