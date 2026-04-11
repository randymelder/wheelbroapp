// BluetoothManager.swift
// Full CoreBluetooth implementation for BLE 4.0 OBD-II dongles (ELM327-based,
// compatible with Vgate iCar Pro and similar adapters).
//
// DATA FLOW:
//   1. User taps "Scan for Devices" → startScanning() discovers ALL BLE peripherals.
//   2. User taps a row → connect(to:) initiates a CBCentralManager connection.
//   3. On connect, we discover services/characteristics and subscribe to notify.
//   4. If Simulator is OFF, initializeOBDDongle() sends the AT command sequence.
//   5. readVIN() is called once after init to get the vehicle VIN.
//   6. startPIDPolling() fires every 5 s, cycling through the PID list.
//   7. Each response is accumulated in a buffer until ">" is seen (ELM327 prompt),
//      then parsed and forwarded to OBDDataManager via updateFromOBD(key:value:).
//
// BLUETOOTH PERMISSION:
//   Info.plist must contain:
//   <key>NSBluetoothAlwaysUsageDescription</key>
//   <string>WheelBro uses Bluetooth to connect to your OBD-II dongle.</string>

import Foundation
import CoreBluetooth
import Observation

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Known BLE OBD Service / Characteristic UUIDs
// These are common UUIDs for ELM327-compatible BLE OBD-II adapters.
//
// Service UUIDs are used as a scan filter so that iOS surfaces devices like the
// Vgate iCar Pro that only appear when scanned for their specific service UUID.
// Characteristic UUIDs are used after connection to locate the correct channel.
// ─────────────────────────────────────────────────────────────────────────────
private let knownOBDServiceUUIDs: [CBUUID] = [
    CBUUID(string: "E7810A71-73AE-499D-8C15-FAA9AEF0C3F2"),  // Vgate iCar Pro / vLinker BM+ — single all-in-one char
    CBUUID(string: "FFE0"),   // Generic ELM327 BLE adapters    (characteristic FFE1)
    CBUUID(string: "18F0"),   // Vgate vLinker MC+/FD+          (RX=2AF0 notify, TX=2AF1 write)
    CBUUID(string: "FFF0"),   // FFF0-service variant            (characteristic FFF1)
]

private let knownOBDCharacteristicUUIDs: Set<CBUUID> = [
    CBUUID(string: "BEF8D6C9-9C21-4C9E-B632-BD58C1009F9F"),  // Vgate E7810A71 service — all-in-one RX+TX
    CBUUID(string: "FFE1"),   // Generic ELM327 BLE adapters
    CBUUID(string: "2AF0"),   // Vgate 18F0 service — RX / notify only
    CBUUID(string: "2AF1"),   // Vgate 18F0 service — TX / write only
    CBUUID(string: "FFF1"),   // Less common variant
    CBUUID(string: "18F1"),   // 18F0 service variant (legacy)
]

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SAE J1979 PID Name Table
// Maps 2-char uppercase hex PID codes to human-readable names.
// Covers Mode 01 PIDs 01–D3 per the SAE J1979 standard.
// ─────────────────────────────────────────────────────────────────────────────
private let pidNames: [String: String] = [
    "01": "Monitor Status / MIL",
    "02": "Freeze Frame DTC",
    "03": "Fuel System Status",
    "04": "Engine Load",
    "05": "Coolant Temperature",
    "06": "Short-Term Fuel Trim (Bank 1)",
    "07": "Long-Term Fuel Trim (Bank 1)",
    "08": "Short-Term Fuel Trim (Bank 2)",
    "09": "Long-Term Fuel Trim (Bank 2)",
    "0A": "Fuel Pressure",
    "0B": "Intake Manifold Pressure",
    "0C": "Engine RPM",
    "0D": "Vehicle Speed",
    "0E": "Timing Advance",
    "0F": "Intake Air Temperature",
    "10": "Mass Air Flow",
    "11": "Throttle Position",
    "12": "Secondary Air Status",
    "13": "O2 Sensors Present (2-bank)",
    "14": "O2 Sensor 1-1 Voltage / Trim",
    "15": "O2 Sensor 1-2 Voltage / Trim",
    "16": "O2 Sensor 1-3 Voltage / Trim",
    "17": "O2 Sensor 1-4 Voltage / Trim",
    "18": "O2 Sensor 2-1 Voltage / Trim",
    "19": "O2 Sensor 2-2 Voltage / Trim",
    "1A": "O2 Sensor 2-3 Voltage / Trim",
    "1B": "O2 Sensor 2-4 Voltage / Trim",
    "1C": "OBD Standard",
    "1D": "O2 Sensors Present (4-bank)",
    "1E": "Auxiliary Input Status (PTO)",
    "1F": "Engine Run Time",
    "20": "Supported PIDs 21–40",
    "21": "MIL Distance",
    "22": "Fuel Rail Pressure (relative)",
    "23": "Fuel Rail Pressure (absolute)",
    "24": "O2 Sensor 1-1 (wide range)",
    "25": "O2 Sensor 1-2 (wide range)",
    "26": "O2 Sensor 1-3 (wide range)",
    "27": "O2 Sensor 1-4 (wide range)",
    "28": "O2 Sensor 2-1 (wide range)",
    "29": "O2 Sensor 2-2 (wide range)",
    "2A": "O2 Sensor 2-3 (wide range)",
    "2B": "O2 Sensor 2-4 (wide range)",
    "2C": "EGR Command",
    "2D": "EGR Error",
    "2E": "EVAP Purge",
    "2F": "Fuel Tank Level",
    "30": "Warm-ups Since DTC Clear",
    "31": "Distance Since DTC Clear",
    "32": "EVAP Vapor Pressure",
    "33": "Barometric Pressure",
    "34": "O2 Sensor 1-1 (wide range + current)",
    "35": "O2 Sensor 1-2 (wide range + current)",
    "36": "O2 Sensor 1-3 (wide range + current)",
    "37": "O2 Sensor 1-4 (wide range + current)",
    "38": "O2 Sensor 2-1 (wide range + current)",
    "39": "O2 Sensor 2-2 (wide range + current)",
    "3A": "O2 Sensor 2-3 (wide range + current)",
    "3B": "O2 Sensor 2-4 (wide range + current)",
    "3C": "Catalyst Temp Bank 1 Sensor 1",
    "3D": "Catalyst Temp Bank 2 Sensor 1",
    "3E": "Catalyst Temp Bank 1 Sensor 2",
    "3F": "Catalyst Temp Bank 2 Sensor 2",
    "40": "Supported PIDs 41–60",
    "41": "Monitor Status This Drive Cycle",
    "42": "Control Module Voltage",
    "43": "Absolute Engine Load",
    "44": "Commanded Equivalence Ratio",
    "45": "Relative Throttle Position",
    "46": "Ambient Air Temperature",
    "47": "Absolute Throttle Position B",
    "48": "Absolute Throttle Position C",
    "49": "Accelerator Pedal Position D",
    "4A": "Accelerator Pedal Position E",
    "4B": "Accelerator Pedal Position F",
    "4C": "Commanded Throttle Actuator",
    "4D": "MIL On Time",
    "4E": "Time Since DTC Clear",
    "4F": "Max Values (EQ Ratio / O2 Voltage / O2 Current / MAP)",
    "50": "Max MAF",
    "51": "Fuel Type",
    "52": "Ethanol Content",
    "53": "Absolute EVAP Pressure",
    "54": "EVAP System Vapor Pressure",
    "55": "Short-Term O2 Trim Bank 1 / 3",
    "56": "Long-Term O2 Trim Bank 1 / 3",
    "57": "Short-Term O2 Trim Bank 2 / 4",
    "58": "Long-Term O2 Trim Bank 2 / 4",
    "59": "Fuel Rail Absolute Pressure",
    "5A": "Relative Accelerator Pedal Position",
    "5B": "Hybrid Battery Pack Remaining Life",
    "5C": "Engine Oil Temperature",
    "5D": "Fuel Injection Timing",
    "5E": "Engine Fuel Rate",
    "5F": "Emission Requirements",
    "60": "Supported PIDs 61–80",
    "61": "Driver Demand Engine Torque",
    "62": "Actual Engine Torque",
    "63": "Engine Reference Torque",
    "64": "Engine Percent Torque Data",
    "65": "Auxiliary Input / Output",
    "66": "Mass Air Flow Sensor",
    "67": "Engine Coolant Temperature (multi-sensor)",
    "68": "Intake Air Temperature Sensor",
    "69": "EGR / VVT System",
    "6A": "EGR Valve B",
    "6B": "EGR Temperature",
    "6C": "Commanded Throttle Actuator Control",
    "6D": "Fuel Pressure Control System",
    "6E": "Injection Pressure Control System",
    "6F": "Turbo Compressor Inlet Pressure",
    "70": "Boost Pressure Control",
    "71": "Variable Geometry Turbo Control",
    "72": "Wastegate Control",
    "73": "Exhaust Pressure",
    "74": "Turbocharger RPM",
    "75": "Turbocharger Temperature A",
    "76": "Turbocharger Temperature B",
    "77": "Charge Air Cooler Temperature",
    "78": "Exhaust Gas Temperature Bank 1",
    "79": "Exhaust Gas Temperature Bank 2",
    "7A": "DPF Bank 1",
    "7B": "DPF Bank 2",
    "7C": "DPF Temperature",
    "7D": "NOx NTE Control Area Status",
    "7E": "PM NTE Control Area Status",
    "7F": "Engine Run Time (extended)",
    "80": "Supported PIDs 81–A0",
    "81": "Engine Run Time for AECD",
    "82": "Engine Run Time for AECD (continued)",
    "83": "NOx Sensor",
    "84": "Manifold Surface Temperature",
    "85": "NOx Warning / Inducement System",
    "8D": "Throttle Position G",
    "8E": "Engine Friction Torque",
    "9A": "Hybrid / EV System Data",
    "9D": "Engine Fuel Rate (mass)",
    "9E": "Engine Exhaust Flow Rate",
    "9F": "Fuel System Percentage Use",
    "A0": "Supported PIDs A1–C0",
    "A2": "Cylinder Fuel Rate",
    "A6": "Odometer",
    "AA": "Vehicle Speed Limit",
    "B2": "Battery State of Health",
    "D2": "State of Charge (estimated / reported)",
    "D3": "Engine Distance Since Last DTC Clear",
]

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - PIDResult
// Lightweight value type for a discovered supported PID and its name.
// ─────────────────────────────────────────────────────────────────────────────
struct PIDResult: Identifiable {
    let id   = UUID()
    let pid  : String   // e.g. "0C"
    let name : String   // e.g. "Engine RPM"
}

@Observable
final class BluetoothManager: NSObject {

    // =========================================================================
    // MARK: - Public State  (observed by SwiftUI views)
    // =========================================================================
    var discoveredPeripherals: [DiscoveredPeripheral] = []
    var connectedPeripheral:   CBPeripheral?
    var isConnected:           Bool   = false
    var isScanning:            Bool   = false
    var connectionStatus:      String = "Ready"

    // "Test OBD Data" flow — set to true to trigger an alert in SettingsView
    var testOBDResult:    String = ""
    var showTestOBDAlert: Bool   = false

    // PID Discovery
    var pidDiscoveryResults: [PIDResult] = []
    var isDiscoveryRunning:  Bool        = false
    var discoveryFinished:   Bool        = false

    // =========================================================================
    // MARK: - Bridge to OBDDataManager / DiagnosticsManager
    // =========================================================================
    /// Set by ContentView after both managers are created.
    var obdDataManager:  OBDDataManager?
    var diagnostics:     DiagnosticsManager?

    // =========================================================================
    // MARK: - Private State
    // =========================================================================
    private var centralManager:  CBCentralManager!
    private var obdNotifyChar:   CBCharacteristic?   // RX — subscribed for notifications
    private var obdWriteChar:    CBCharacteristic?   // TX — target for all write calls
    private var responseBuffer:  String = ""

    // PID poll timer and rotating index
    private var pidPollTimer:    Timer?
    private var currentPIDIndex: Int = 0

    // AT-command init queue
    private var initQueue:     [String] = []
    private var isInitializing: Bool    = false

    // Test-mode command queue
    private var testQueue:  [String] = []
    private var isTestMode: Bool     = false

    // PID discovery queue and flag
    private var discoveryQueue: [String] = []
    private var isDiscovering:  Bool     = false

    // ─────────────────────────────────────────────────────────────────────────
    // Standard OBD-II PIDs polled every 5 seconds (Mode 01 = live data)
    // Each string is the raw command sent to the ELM327 (terminated with \r).
    //
    // PID reference (SAE J1979):
    //   010C → Engine RPM          : ((A*256)+B)/4
    //   010D → Vehicle Speed       : A  (km/h; convert to mph × 0.6214)
    //   012F → Fuel Tank Level     : A/2.55  (%)
    //   0105 → Coolant Temperature : A−40  (°C; convert to °F)
    //   015C → Engine Oil Temp     : A−40  (°C; convert to °F)
    //   ATRV → Battery Voltage     : ELM327 AT command, returns e.g. "12.3V"
    //   03   → Read DTCs (Mode 03) : lists stored fault codes
    // ─────────────────────────────────────────────────────────────────────────
    private let pidSequence: [String] = [
        "010C\r",   // RPM
        "010D\r",   // Speed
        "012F\r",   // Fuel Level
        "0105\r",   // Coolant Temp
        "015C\r",   // Oil Temp
        "015E\r",   // Fuel Rate (L/hr) — PID 5E, supported on Jeep Wrangler JK 2012+
        "ATRV\r",   // Battery Voltage  ← AT command, not a Mode-01 PID
        "03\r"      // Fault Codes (Mode 03)
    ]

    // =========================================================================
    // MARK: - Init
    // =========================================================================
    override init() {
        super.init()
        // Initialise on the main queue so delegate callbacks arrive on main thread.
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    // =========================================================================
    // MARK: - Scanning
    // =========================================================================

    /// Discovers ALL nearby BLE peripherals without any service-UUID filter.
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            connectionStatus = "Bluetooth not powered on"
            return
        }
        discoveredPeripherals.removeAll()
        isScanning = true
        connectionStatus = "Scanning…"
        diagnostics?.log(.info, .ble, "Scan started (filter: \(knownOBDServiceUUIDs.count) service UUIDs)")

        // Filter by known OBD service UUIDs so iOS surfaces devices like the
        // Vgate iCar Pro that only appear in service-filtered scans.
        centralManager.scanForPeripherals(withServices: knownOBDServiceUUIDs,
                                          options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])

        // Auto-stop after 10 seconds to save battery
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, self.isScanning else { return }
            self.stopScanning()
        }
    }

    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
        if connectionStatus == "Scanning…" {
            connectionStatus = "Scan complete — tap a device to connect"
        }
        diagnostics?.log(.info, .ble, "Scan stopped — \(discoveredPeripherals.count) device(s) found")
    }

    // =========================================================================
    // MARK: - Connection
    // =========================================================================

    func connect(to peripheral: CBPeripheral) {
        stopScanning()
        connectionStatus = "Connecting to \(peripheral.name ?? "Unknown")…"
        diagnostics?.log(.info, .ble, "Connecting → \(peripheral.name ?? peripheral.identifier.uuidString.prefix(8))")
        centralManager.connect(peripheral, options: nil)
    }

    func disconnect() {
        guard let p = connectedPeripheral else { return }
        stopPIDPolling()
        // Cancel any in-flight init or discovery so stale responses don't
        // trigger commands on a future connection.
        initQueue        = []
        discoveryQueue   = []
        isInitializing   = false
        isDiscovering    = false
        responseBuffer   = ""
        centralManager.cancelPeripheralConnection(p)
    }

    // =========================================================================
    // MARK: - OBD-II Dongle Initialisation (ELM327 AT Commands)
    // =========================================================================

    /// Sends the standard ELM327 initialisation sequence.
    /// Each command must complete (receive a response) before the next is sent.
    /// The sequence resets the chip, disables echo/spaces/headers, and selects
    /// automatic ISO/SAE protocol detection.
    private func initializeOBDDongle() {
        isInitializing = true
        diagnostics?.log(.info, .system, "AT init sequence started (7 commands)")

        // ── ELM327 AT Command Reference ──────────────────────────────────────
        // ATZ    Reset the ELM327 (takes ~1 s; response is the version string)
        // ATE0   Echo off       — stop reflecting our commands back to us
        // ATL0   Linefeed off   — cleaner response framing
        // ATS0   Spaces off     — parse hex bytes without embedded spaces
        // ATH0   Headers off    — omit the OBD header bytes we don't need
        // ATSP0  Auto protocol  — let ELM327 detect CAN/ISO/VPW/PWM automatically
        // ATAT1  Adaptive timing mode 1 — adjusts timeout to match vehicle
        // ─────────────────────────────────────────────────────────────────────
        initQueue = [
            "ATZ\r",    // 1. Reset chip
            "ATE0\r",   // 2. Echo off
            "ATL0\r",   // 3. Linefeeds off
            "ATS0\r",   // 4. Spaces off
            "ATH0\r",   // 5. Headers off
            "ATSP0\r",  // 6. Auto-detect OBD protocol
            "ATAT1\r"   // 7. Adaptive timing mode 1
        ]

        sendNextInitCommand()
    }

    private func sendNextInitCommand() {
        guard !initQueue.isEmpty else {
            isInitializing = false
            diagnostics?.log(.info, .system, "AT init complete — starting polling")
            // Start polling immediately so data flows even if VIN read fails or
            // the vehicle doesn't support Mode 09.  VIN is a fire-and-forget read.
            startPIDPolling()
            readVIN()
            return
        }
        let cmd = initQueue.removeFirst()
        write(cmd)
    }

    // =========================================================================
    // MARK: - VIN Reading
    // =========================================================================

    /// Requests the Vehicle Identification Number via OBD-II Mode 09, PID 02.
    ///
    /// Command: "0902\r"
    /// Response example (headers off, spaces off):
    ///   "490201314A344241324431334242313233343536"
    ///   Prefix  = "490201"  (mode 49, PID 02, byte count 01)
    ///   Payload = 17 ASCII bytes encoded as hex pairs
    private func readVIN() {
        write("0902\r")   // Mode 09, PID 02 = VIN
    }

    // =========================================================================
    // MARK: - PID Polling
    // =========================================================================

    private func startPIDPolling() {
        stopPIDPolling()
        currentPIDIndex = 0
        diagnostics?.log(.info, .system, "PID polling started (\(pidSequence.count) PIDs, 5 s interval)")
        pidPollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.pollNextPID()
        }
    }

    private func stopPIDPolling() {
        pidPollTimer?.invalidate()
        pidPollTimer = nil
    }

    private func pollNextPID() {
        guard isConnected, obdWriteChar != nil else { return }
        let cmd = pidSequence[currentPIDIndex]
        currentPIDIndex = (currentPIDIndex + 1) % pidSequence.count
        write(cmd)
    }

    // =========================================================================
    // MARK: - Test OBD Data
    // =========================================================================

    /// Sends VIN + 3 PIDs and accumulates results for display in an alert.
    /// Called from SettingsView when the user taps "Test OBD Data".
    func testOBDData() {
        guard isConnected else {
            testOBDResult = "Not connected to any OBD device."
            showTestOBDAlert = true
            return
        }
        isTestMode   = true
        testOBDResult = "── WheelBro OBD-II Test ──\n\n"

        // VIN + RPM + Fuel Level + Coolant Temp
        testQueue = ["0902\r", "010C\r", "012F\r", "0105\r"]
        sendNextTestCommand()
    }

    private func sendNextTestCommand() {
        guard !testQueue.isEmpty else {
            testOBDResult += "\n── Test Complete ──"
            isTestMode = false
            showTestOBDAlert = true
            // Resume normal polling
            startPIDPolling()
            return
        }
        let cmd = testQueue.removeFirst()
        let label = cmd.replacingOccurrences(of: "\r", with: "")
        testOBDResult += "→ CMD: \(label)\n"
        write(cmd)
    }

    // =========================================================================
    // MARK: - PID Discovery
    // =========================================================================
    // Queries Mode 01 support PIDs 0x00, 0x20, 0x40, 0x60 in sequence.
    // Each returns a 32-bit bitmask describing which PIDs exist on this vehicle.
    // Results are stored in pidDiscoveryResults and exposed to DiscoveryView.
    // Normal PID polling is paused for the duration and resumed on completion.
    // =========================================================================

    func startPIDDiscovery() {
        guard isConnected else { return }
        stopPIDPolling()
        pidDiscoveryResults  = []
        isDiscoveryRunning   = true
        discoveryFinished    = false
        isDiscovering        = true
        diagnostics?.log(.info, .system, "PID discovery started (ranges 00–60)")
        // Query the four standard support-PID ranges for JK (2012+)
        discoveryQueue = ["0100\r", "0120\r", "0140\r", "0160\r"]
        sendNextDiscoveryCommand()
    }

    private func sendNextDiscoveryCommand() {
        guard !discoveryQueue.isEmpty else {
            isDiscovering      = false
            isDiscoveryRunning = false
            discoveryFinished  = true
            diagnostics?.log(.info, .system, "PID discovery complete — \(pidDiscoveryResults.count) PIDs supported")
            if isConnected { startPIDPolling() }
            return
        }
        write(discoveryQueue.removeFirst())
    }

    /// Parses a Mode-01 support-PID response and appends matched entries
    /// to pidDiscoveryResults. Silently ignores malformed / NODATA responses.
    private func parseSupportBitmask(_ response: String) {
        // Expected (headers off, spaces off): "41" + 2-char base PID + 8 hex chars
        guard response.hasPrefix("41"), response.count >= 12 else { return }

        let basePIDHex = String(response.dropFirst(2).prefix(2))
        guard let basePID = UInt32(basePIDHex, radix: 16) else { return }

        let bitmaskHex = String(response.dropFirst(4).prefix(8))
        guard bitmaskHex.count == 8,
              let bitmask = UInt32(bitmaskHex, radix: 16) else { return }

        for bit in 0..<32 {
            guard (bitmask >> (31 - bit)) & 1 == 1 else { continue }
            let pidValue  = basePID + UInt32(bit + 1)
            guard pidValue <= 0xFF else { continue }
            let pidString = String(format: "%02X", pidValue)
            let name      = pidNames[pidString] ?? "PID 0x\(pidString)"
            pidDiscoveryResults.append(PIDResult(pid: pidString, name: name))
        }
    }

    // =========================================================================
    // MARK: - BLE Write
    // =========================================================================

    private func write(_ command: String) {
        guard let p = connectedPeripheral,
              let ch = obdWriteChar,
              let data = command.data(using: .utf8) else { return }

        let label = command.replacingOccurrences(of: "\r", with: "")
        diagnostics?.log(.info, .obd, "→ \(label)")

        // ELM327 BLE adapters typically use writeWithoutResponse for speed.
        // Fall back to writeWithResponse if the characteristic requires it.
        let type: CBCharacteristicWriteType = ch.properties.contains(.writeWithoutResponse)
            ? .withoutResponse
            : .withResponse
        p.writeValue(data, for: ch, type: type)
    }

    // =========================================================================
    // MARK: - Response Processing & Parsing
    // =========================================================================

    private func handleRawResponse(_ raw: String) {
        // Buffer until we see the ELM327 prompt character ">"
        responseBuffer += raw

        guard responseBuffer.contains(">") else { return }

        let full = responseBuffer
        responseBuffer = ""

        // Log the complete raw response (strip prompt and surrounding whitespace)
        let logPayload = full
            .replacingOccurrences(of: ">", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !logPayload.isEmpty {
            diagnostics?.log(.info, .obd, "← response", raw: logPayload)
        }

        // Split on newlines, process each non-empty, non-prompt line
        let lines = full.components(separatedBy: CharacterSet.newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != ">" else { continue }
            processLine(trimmed)
        }
    }

    private func processLine(_ line: String) {
        // Normalise: uppercase, strip spaces for hex parsing
        let clean = line.replacingOccurrences(of: " ", with: "").uppercased()

        if isInitializing {
            sendNextInitCommand()
            return
        }

        if isDiscovering {
            parseSupportBitmask(clean)     // no-op on NODATA / ERROR
            sendNextDiscoveryCommand()     // always advance the queue
            return
        }

        if isTestMode {
            testOBDResult += "← RSP: \(clean)\n"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.sendNextTestCommand()
            }
            return
        }

        // Log known non-data ELM327 responses before dropping them
        if clean.contains("NODATA") {
            diagnostics?.log(.warning, .obd, "NO DATA — PID not supported or vehicle timeout")
        } else if clean.contains("UNABLETOCONNECT") {
            diagnostics?.log(.error, .obd, "UNABLE TO CONNECT — check OBD port / ignition")
        } else if clean.contains("ERROR") {
            diagnostics?.log(.warning, .obd, "ELM327 error: \(clean)")
        }
        guard !clean.contains("NODATA"),
              !clean.contains("ERROR"),
              !clean.contains("UNABLETOCONNECT"),
              !clean.hasPrefix("ELM") else { return }

        parseOBDLine(clean)
    }

    // ─────────────────────────────────────────────────────────────────────────
    /// Decodes a single normalised OBD-II response line and forwards
    /// key/value pairs to OBDDataManager.
    ///
    /// Mode 01 (live data)  response prefix: "41" + PID hex
    /// Mode 09 (vehicle info) VIN prefix:    "4902"
    /// Mode 03 (DTC read)   response prefix: "43"
    /// AT RV   (battery V)  response suffix: "V"
    // ─────────────────────────────────────────────────────────────────────────
    private func parseOBDLine(_ s: String) {

        // ── Mode 01: Live Data ────────────────────────────────────────────────
        if s.hasPrefix("41"), s.count >= 6 {
            let pidHex  = String(s.dropFirst(2).prefix(2))
            let payload = String(s.dropFirst(4))

            switch pidHex {

            case "0C":
                // Engine RPM  = ((A * 256) + B) / 4
                guard payload.count >= 4,
                      let a = UInt32(payload.prefix(2), radix: 16),
                      let b = UInt32(payload.dropFirst(2).prefix(2), radix: 16)
                else { return }
                let rpm = Int((a * 256 + b) / 4)
                obdDataManager?.updateFromOBD(key: "rpm", value: String(rpm))

            case "0D":
                // Vehicle Speed  = A km/h → mph
                guard let a = UInt32(payload.prefix(2), radix: 16) else { return }
                let mph = Double(a) * 0.621371
                obdDataManager?.updateFromOBD(key: "speed", value: String(format: "%.1f", mph))

            case "2F":
                // Fuel Tank Level  = A / 2.55  (%)
                guard let a = UInt32(payload.prefix(2), radix: 16) else { return }
                let pct = Double(a) / 2.55
                obdDataManager?.updateFromOBD(key: "fuelLevel", value: String(format: "%.1f", pct))

            case "05":
                // Engine Coolant Temp  = A − 40  (°C) → °F
                guard let a = UInt32(payload.prefix(2), radix: 16) else { return }
                let f = celsiusToFahrenheit(Double(a) - 40)
                obdDataManager?.updateFromOBD(key: "coolantTemp", value: String(format: "%.1f", f))

            case "5C":
                // Engine Oil Temp  = A − 40  (°C) → °F
                guard let a = UInt32(payload.prefix(2), radix: 16) else { return }
                let f = celsiusToFahrenheit(Double(a) - 40)
                obdDataManager?.updateFromOBD(key: "oilTemp", value: String(format: "%.1f", f))

            case "5E":
                // Fuel Rate  = ((A * 256) + B) / 20  (L/hr)
                guard payload.count >= 4,
                      let a = UInt32(payload.prefix(2), radix: 16),
                      let b = UInt32(payload.dropFirst(2).prefix(2), radix: 16)
                else { return }
                let lph = Double(a * 256 + b) / 20.0
                obdDataManager?.updateFromOBD(key: "fuelRate", value: String(format: "%.3f", lph))

            // ── Future PID expansion: add case "XX": blocks here ──────────────
            // Mode 01 PID reference (SAE J1979):
            //   01  = Calculated engine load
            //   06  = Short term fuel trim (Bank 1)
            //   07  = Long term fuel trim (Bank 1)
            //   0A  = Fuel pressure (gauge) kPa
            //   0B  = Intake manifold pressure kPa
            //   0E  = Timing advance (°)
            //   0F  = Intake air temperature
            //   10  = MAF air flow rate
            //   11  = Throttle position
            //   33  = Barometric pressure
            //   42  = Control module voltage  (alternative battery V source)
            //   46  = Ambient air temperature
            // ─────────────────────────────────────────────────────────────────
            default: break
            }
            return
        }

        // ── Mode 09 PID 02: VIN ───────────────────────────────────────────────
        // Response (spaces off, headers off) example:
        //   "490201314A344241324431334242313233343536"
        //   Skip "4902" (4 chars) + optional frame-counter byte "01" (2 chars)
        if s.hasPrefix("4902"), s.count > 8 {
            // Drop "490201" prefix (6 chars) to get raw VIN hex payload
            let hexPayload = String(s.dropFirst(6))
            var vinStr = ""
            var idx = hexPayload.startIndex
            while idx < hexPayload.endIndex {
                let next = hexPayload.index(idx, offsetBy: 2, limitedBy: hexPayload.endIndex) ?? hexPayload.endIndex
                if let byte = UInt8(hexPayload[idx..<next], radix: 16), byte > 0 {
                    vinStr.append(Character(UnicodeScalar(byte)))
                }
                idx = next
            }
            if vinStr.count >= 10 { // plausibility check — real VINs are 17 chars
                obdDataManager?.updateFromOBD(key: "vin", value: vinStr)
                diagnostics?.log(.info, .parse, "VIN decoded: \(vinStr)")
            } else if !vinStr.isEmpty {
                diagnostics?.log(.warning, .parse, "VIN too short (\(vinStr.count) chars): \(vinStr)", raw: hexPayload)
            }
            // Polling was already started by sendNextInitCommand — nothing to do here.
            return
        }

        // ── Mode 03: DTCs ─────────────────────────────────────────────────────
        // Response prefix: "43" followed by groups of 4 hex chars per DTC.
        // "4300000000000000" = no faults stored.
        if s.hasPrefix("43"), s.count >= 4 {
            let dtcPayload = String(s.dropFirst(2))
            var dtcs: [String] = []
            var idx = dtcPayload.startIndex
            while idx < dtcPayload.endIndex,
                  dtcPayload.distance(from: idx, to: dtcPayload.endIndex) >= 4 {
                let end  = dtcPayload.index(idx, offsetBy: 4)
                let code = String(dtcPayload[idx..<end])
                if code != "0000" {
                    dtcs.append(decodeDTC(code))
                }
                idx = end
            }
            let result = dtcs.filter { !$0.isEmpty }.joined(separator: ",")
            obdDataManager?.updateFromOBD(key: "errorCodes", value: result.isEmpty ? "None" : result)
            return
        }

        // ── AT RV: Battery Voltage ─────────────────────────────────────────────
        // Response: "12.3V" or "14.2V"
        if s.hasSuffix("V"), let voltage = Double(s.dropLast()) {
            obdDataManager?.updateFromOBD(key: "batteryVoltage", value: String(format: "%.2f", voltage))
        }
    }

    // =========================================================================
    // MARK: - Helpers
    // =========================================================================

    private func celsiusToFahrenheit(_ c: Double) -> Double { (c * 9.0 / 5.0) + 32.0 }

    /// Decodes a 4-hex-char OBD-II DTC byte pair into a standard code string (e.g. "P0300").
    private func decodeDTC(_ hex: String) -> String {
        guard hex.count == 4, let value = UInt16(hex, radix: 16), value != 0 else { return "" }

        // Bits 15–14 select the system
        let systems  = ["P", "C", "B", "U"]
        let sysIndex = Int((value >> 14) & 0x03)
        let system   = systems[sysIndex]

        // Bits 13–12 = first digit (0–3)
        let digit1   = Int((value >> 12) & 0x03)

        // Bits 11–0 = last three digits in hex
        let last3    = String(format: "%03X", value & 0x0FFF)

        return "\(system)\(digit1)\(last3)"
    }
}

// =============================================================================
// MARK: - CBCentralManagerDelegate
// =============================================================================
extension BluetoothManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:       connectionStatus = "Bluetooth Ready"
        case .poweredOff:      connectionStatus = "Bluetooth is Off"; isConnected = false
        case .unauthorized:    connectionStatus = "Bluetooth Unauthorized — check Privacy settings"
        case .unsupported:     connectionStatus = "BLE not supported on this device"
        case .resetting:       connectionStatus = "Bluetooth Resetting…"
        case .unknown:         connectionStatus = "Bluetooth state unknown"
        @unknown default:      connectionStatus = "Bluetooth state unknown"
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        // Use advertised local name as fallback when CBPeripheral.name is nil
        let name = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? "Unknown (\(peripheral.identifier.uuidString.prefix(8)))"

        // De-duplicate by peripheral UUID
        guard !discoveredPeripherals.contains(where: { $0.id == peripheral.identifier }) else { return }

        let svcUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let item = DiscoveredPeripheral(
            peripheral:            peripheral,
            name:                  name,
            rssi:                  RSSI.intValue,
            advertisedServiceUUIDs: svcUUIDs
        )
        discoveredPeripherals.append(item)
        diagnostics?.log(.info, .ble, "Found: \(name)  RSSI \(RSSI) dBm  supported=\(item.isVgateCompatible)  [\(peripheral.identifier.uuidString.prefix(8).uppercased())]")
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        peripheral.delegate = self
        isConnected = true
        connectionStatus = "Connected to \(peripheral.name ?? "Unknown")"
        obdDataManager?.isConnected = true
        obdDataManager?.connectedDeviceName = peripheral.name ?? "Unknown"
        diagnostics?.log(.info, .ble, "Connected: \(peripheral.name ?? "Unknown")  [\(peripheral.identifier.uuidString.prefix(8).uppercased())]")

        // Discover all services (nil = all, not filtered)
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        isConnected = false
        connectionStatus = "Connection failed: \(error?.localizedDescription ?? "unknown error")"
        obdDataManager?.isConnected = false
        diagnostics?.log(.error, .ble, "Connection failed: \(error?.localizedDescription ?? "unknown error")")
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        connectedPeripheral  = nil
        obdNotifyChar        = nil
        obdWriteChar         = nil
        isConnected          = false
        connectionStatus     = "Disconnected — tap Scan to reconnect"
        stopPIDPolling()
        obdDataManager?.isConnected         = false
        obdDataManager?.connectedDeviceName = ""
        obdDataManager?.resetValues()
        if let error {
            diagnostics?.log(.warning, .ble, "Disconnected (error): \(error.localizedDescription)")
        } else {
            diagnostics?.log(.info, .ble, "Disconnected: \(peripheral.name ?? "Unknown")")
        }
    }
}

// =============================================================================
// MARK: - CBPeripheralDelegate
// =============================================================================
extension BluetoothManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        diagnostics?.log(.info, .ble, "Services discovered: \(services.count)")
        for service in services {
            diagnostics?.log(.info, .ble, "  Service: \(service.uuid.uuidString)")
            // Discover all characteristics (nil = all)
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard let characteristics = service.characteristics else { return }

        let svcUUID = service.uuid.uuidString.uppercased()

        switch svcUUID {

        case "E7810A71-73AE-499D-8C15-FAA9AEF0C3F2":
            // Vgate iCar Pro / vLinker BM+ — single characteristic handles both RX and TX
            guard obdWriteChar == nil else { return }
            for ch in characteristics where ch.uuid == CBUUID(string: "BEF8D6C9-9C21-4C9E-B632-BD58C1009F9F") {
                obdNotifyChar = ch
                obdWriteChar  = ch
                peripheral.setNotifyValue(true, for: ch)
                diagnostics?.log(.info, .ble, "Vgate (E7810A71) char: \(ch.uuid.uuidString)")
            }

        case "18F0":
            // Vgate vLinker MC+/FD+ — SPLIT characteristics: 2AF0=RX notify-only, 2AF1=TX write-only
            for ch in characteristics {
                switch ch.uuid {
                case CBUUID(string: "2AF0"):
                    obdNotifyChar = ch
                    peripheral.setNotifyValue(true, for: ch)
                    diagnostics?.log(.info, .ble, "Vgate (18F0) RX notify char: 2AF0")
                case CBUUID(string: "2AF1"):
                    guard obdWriteChar == nil else { break }
                    obdWriteChar = ch
                    diagnostics?.log(.info, .ble, "Vgate (18F0) TX write char: 2AF1")
                default: break
                }
            }

        default:
            // Generic fallback — first characteristic with both write and notify capability
            guard obdWriteChar == nil else { return }
            for ch in characteristics {
                let canWrite  = ch.properties.contains(.write) || ch.properties.contains(.writeWithoutResponse)
                let canNotify = ch.properties.contains(.notify) || ch.properties.contains(.indicate)
                if canWrite && canNotify {
                    obdNotifyChar = ch
                    obdWriteChar  = ch
                    peripheral.setNotifyValue(true, for: ch)
                    diagnostics?.log(.info, .ble, "Generic OBD char: \(ch.uuid.uuidString)")
                    break
                }
            }
        }

        triggerInitIfReady(peripheral: peripheral)
    }

    /// Fires the ELM327 AT init sequence once both notify and write characteristics
    /// are assigned. Called after each service's characteristics are discovered so
    /// the Vgate 18F0 split case (two characteristics, one service) is handled correctly.
    /// Sets isInitializing = true immediately (before the async delay) so that a
    /// second call from a subsequent service's callback cannot schedule a duplicate.
    private func triggerInitIfReady(peripheral: CBPeripheral) {
        guard obdNotifyChar != nil, obdWriteChar != nil else { return }
        guard !isInitializing else { return }
        guard let mgr = obdDataManager, !mgr.isSimulatorOn else { return }
        isInitializing = true   // claim the slot before the 0.5 s window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.initializeOBDDongle()
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let data = characteristic.value,
              let text = String(data: data, encoding: .utf8) else { return }
        handleRawResponse(text)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        // Notification subscription confirmed — nothing extra needed.
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error = error {
            connectionStatus = "Write error: \(error.localizedDescription)"
        }
    }
}

// =============================================================================
// MARK: - Supporting Type
// =============================================================================

/// Lightweight value type wrapping a discovered CBPeripheral for display in a List.
struct DiscoveredPeripheral: Identifiable {
    let id:         UUID         // peripheral.identifier
    let peripheral: CBPeripheral
    let name:       String
    let rssi:       Int
    /// Service UUIDs extracted from the BLE advertisement packet.
    let advertisedServiceUUIDs: [CBUUID]

    // ── Compatibility ─────────────────────────────────────────────────────────
    /// Vgate-specific service UUIDs this app fully supports.
    /// Generic ELM327 clones (FFE0, FFF0) are excluded — they are in the scan
    /// filter to avoid missed discoveries, but not in the supported device list.
    private static let vgateServiceUUIDs: Set<CBUUID> = [
        CBUUID(string: "E7810A71-73AE-499D-8C15-FAA9AEF0C3F2"),  // iCar Pro / vLinker BM+
        CBUUID(string: "18F0"),                                   // vLinker MC+ / FD+
    ]

    /// True when the device advertises at least one Vgate-specific service UUID,
    /// or (fallback) when its name matches a known Vgate product identifier.
    /// The fallback handles devices whose scan response omits service UUIDs.
    var isVgateCompatible: Bool {
        if !advertisedServiceUUIDs.isEmpty {
            return !Set(advertisedServiceUUIDs).isDisjoint(with: Self.vgateServiceUUIDs)
        }
        // Name-based fallback
        let lower = name.lowercased()
        return lower.contains("vlink") || lower.contains("vlinkr") || lower.contains("vgate")
    }

    init(peripheral: CBPeripheral, name: String, rssi: Int, advertisedServiceUUIDs: [CBUUID] = []) {
        self.id                    = peripheral.identifier
        self.peripheral            = peripheral
        self.name                  = name
        self.rssi                  = rssi
        self.advertisedServiceUUIDs = advertisedServiceUUIDs
    }
}
