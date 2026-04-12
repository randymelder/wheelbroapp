# WheelBro

An OBD-II monitor for the **Jeep Wrangler JK (2011–2018)**, built for iOS with SwiftUI and SwiftData. WheelBro connects to your vehicle via a Bluetooth Low Energy ELM327-compatible OBD-II dongle and displays live engine data with a focus on fuel range awareness.

---

## Features

### Time to Empty (TTE)
The primary screen shows a large, animated **Time to Empty** countdown calculated from live fuel level, speed, and RPM data. Updated every second. Additional cards display:

- **Distance to Empty** (miles)
- **Fuel Level** (%)
- **Speed** (mph)
- **Pitch** — front-to-back tilt in degrees (Up / Down); useful for trail incline awareness
- **Roll** — side-to-side tilt in degrees (Right / Left)
- **Heading** — degrees true north with cardinal compass point (N, NE, E … NW)
- **Altitude** (ft)
- **Latitude** / **Longitude** — 5 decimal-place precision with hemisphere indicator
- **Diagnostic Trouble Codes** — live DTC list with fault/clear indicator
- **VIN** — decoded from OBD-II Mode 09

When no BLE device is connected and Simulator mode is off, a full-screen overlay prompts the user to connect a device and navigates directly to Settings.

**Swipe down** anywhere on the TTE screen to take a screenshot: the shutter sound plays, the screen flashes white, and the image is saved directly to your Photo Library (add-only permission — no read access to existing photos).

The status banner adapts to connection state:
- `Simulator ON` — simulator is active
- `Connected to <device>` — BLE connected, ECU responding
- `Connected — turn ignition ON` — BLE connected but ECU not yet responding
- Scanning / connection error states

### Data & Logging
- Automatic data logging — one row per OBD key every 10 seconds, stored locally via SwiftData
- **Logging is disabled by default** — enable in Settings
- Log auto-purge: entries older than 1 hour are removed automatically
- Browsable log preview showing the 30 most recent entries with key, PID, value, and timestamp
- **Export** via the native iOS share sheet as a `.txt` file (iCloud Drive / Files app compatible)
- Option to clear the log automatically after a successful export
- Session tracking with row and session count badges

### GPS & IMU Sensors
Live sensor data collected independently of the OBD connection:

- **Heading** — degrees true north (falls back to magnetic when uncalibrated); shown with cardinal compass label
- **Altitude** — metres from GPS, displayed in feet on the TTE screen
- **Latitude / Longitude** — WGS84 decimal degrees at 5 decimal-place precision (~1 m)
- **Pitch** — front-to-back tilt angle in degrees from the iPhone accelerometer; positive = nose up (climbing)
- **Roll** — side-to-side tilt angle in degrees; positive = right side higher

GPS data is logged to SwiftData every 10 seconds (independent of the OBD logging toggle) once location permission is granted. Background collection continues while the app is running. Pitch and roll are provided by `CMMotionManager` at 10 Hz with no additional permissions required.

### PID Discovery
Connect your OBD dongle and tap **Discover PIDs** to run a two-phase live query:
- **Phase 1** — bitmask range queries identify every Mode 01 PID supported by the ECU
- **Phase 2** — each discovered PID is polled for its current value

Results (PID code, description, live value) export as a `.txt` file via the share sheet.

### Bluetooth (BLE) Management
- Scan for **all** nearby Bluetooth LE peripherals (no service-UUID filter)
- Device list sorted alphabetically by name
- One-tap connect / full-width disconnect button (visible only when connected)
- Hardcoded protocol: **ATSP6** (ISO 15765-4 CAN, 11-bit ID, 500 kbaud) — the correct protocol for Jeep Wrangler JK; avoids the indefinite SEARCHING loop caused by auto-detect (`ATSP0`)
- Response-driven PID polling — each OBD response immediately triggers the next command, cycling through all PIDs as fast as the adapter responds
- "Test OBD Data" command for validating a new connection

### Simulator Mode
Toggle a built-in data simulator that generates realistic OBD values every 5 seconds — no vehicle or dongle required. Simulator is **on by default** on first launch. Useful for development and UI testing.

### Settings
- Simulator mode toggle (on by default)
- BLE device scanner and connection manager
- Data logging toggle (off by default)
- PID Discovery tool
- "Test OBD Data" diagnostic command

### About
Displays app version, build number, vehicle compatibility, and copyright information.

---

## Requirements

- iOS 17+
- Xcode 15+
- An ELM327-compatible Bluetooth LE OBD-II adapter (tested with IOS-Vlink / Vgate iCar Pro)
- Jeep Wrangler JK (2011–2018), or use Simulator Mode
- Location permission (When In Use) for GPS heading, altitude, and coordinates
- Photo Library add-only permission for swipe-down screenshots
- No additional permissions required for pitch/roll (CoreMotion)

---

## Architecture

| Layer | Technology |
|---|---|
| UI | SwiftUI — declarative four-tab interface (TTE / Data / Settings / About) |
| Storage | SwiftData — on-device persistent log storage |
| BLE | CoreBluetooth — scanning, connection, ELM327 AT init, ISO 15765-4 multi-frame parsing |
| GPS | CoreLocation — `LocationManager`; background-capable, 10-second SwiftData snapshots |
| IMU | CoreMotion — `MotionManager`; pitch & roll at 10 Hz, no permissions required |
| State | `@Observable` managers injected via the SwiftUI environment |
| Constants | Centralised `Constants.swift` — no magic numbers or string literals in call sites |
| Debug output | `wbLog()` gated on `AppConstants.verboseLogging` — silence all console output by flipping one constant |

### BLE / OBD Data Flow

1. User taps **Scan** → `BluetoothManager` discovers all nearby BLE peripherals
2. User taps a device → CoreBluetooth connects; services and characteristics are discovered
3. `initializeOBDDongle()` sends the AT command sequence: ATZ → ATE0 → ATL0 → ATS0 → ATH0 → **ATSP6** → ATAT1
4. Response-driven polling begins, cycling: RPM → Speed → Fuel → Coolant → Oil Temp → Battery Voltage → DTCs → VIN → (repeat)
5. Each parsed value is forwarded to `OBDDataManager` via `updateFromOBD(key:value:)`
6. SwiftUI views observe `OBDDataManager` via `@Observable` and re-render automatically

### Multi-Frame ISO-TP Handling
VIN (Mode 09 PID 02) and DTC (Mode 03) responses arrive as multi-frame ISO 15765-4 CAN sequences. The parser accumulates frame segments (`0:`, `1:`, `2:`) and decodes them once a complete payload is received.

---

## License

© 2026 RCMAZ Software, LLC. All Rights Reserved.
