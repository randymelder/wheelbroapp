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
