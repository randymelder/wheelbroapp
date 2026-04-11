# WheelBro

An OBD-II monitor for the **Jeep Wrangler JK (2011–2018)**, built for iOS with SwiftUI and SwiftData. WheelBro connects to your vehicle via a Bluetooth Low Energy ELM327/Vgate OBD-II dongle and displays live engine data with a focus on fuel range awareness.

---

## Features

### Time to Empty (TTE)
The primary screen shows a large, animated **Time to Empty** countdown calculated from live fuel level, speed, and RPM data. A **Distance to Empty** figure is displayed alongside it. The screen also surfaces real-time telemetry in a two-column card grid:

- RPM
- Speed (mph)
- Fuel Level (%)
- Oil Temperature (°F)
- Coolant Temperature (°F)
- Battery Voltage (V)
- Diagnostic Trouble Codes (DTCs)
- VIN

### Data & Logging
- Automatic data logging — one row per OBD key every 10 seconds, stored locally via SwiftData
- Log auto-purge: data older than 1 hour is removed automatically
- Browsable log preview showing the 30 most recent entries with key, PID, value, unit, and timestamp
- **CSV export** via the native iOS share sheet (iCloud Drive / Files app compatible)
- Session tracking with row and session count badges
- Option to clear the log automatically after a successful export

### PID Discovery
Connect your OBD dongle and run a live query to see every OBD-II PID your vehicle actually supports. Results are shown in a scrollable table and can be exported as a CSV file.

### Bluetooth (BLE) Management
- Scan for nearby Bluetooth LE OBD-II adapters
- Automatically filters to Vgate-compatible devices
- One-tap connect/disconnect
- Live connection status indicator with RSSI and device UUID
- "Test OBD Data" command for validating a new connection

### Simulator Mode
Toggle a built-in data simulator that generates realistic OBD values every 5 seconds — no vehicle or dongle required. Useful for development and UI testing.

### Diagnostics
A live internal event log (BLE and OBD events) available from Settings. Exportable for troubleshooting adapter or connection issues.

### Settings
- Vehicle selection (Jeep Wrangler JK 2011–2018)
- Simulator mode toggle
- BLE device scanner and connection manager
- Data logging toggle
- PID Discovery and Diagnostics tool links

---

## Requirements

- iOS 17+
- Xcode 15+
- A Vgate-compatible ELM327 Bluetooth LE OBD-II adapter
- Jeep Wrangler JK (2011–2018) or use Simulator Mode

---

## Architecture

- **SwiftUI** — declarative four-tab interface (TTE, Data, Settings, About)
- **SwiftData** — on-device persistent log storage
- **CoreBluetooth** — BLE scanning, connection, and ELM327 communication
- **@Observable** managers injected via the SwiftUI environment — no prop drilling

---

## License

© 2026 RCMAZ Software, LLC. All Rights Reserved.
