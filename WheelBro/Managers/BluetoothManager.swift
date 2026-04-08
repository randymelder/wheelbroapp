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
// We do NOT filter on them during scanning (we scan for ALL devices), but we
// use them when searching for the correct characteristic after connection.
// ─────────────────────────────────────────────────────────────────────────────
private let knownOBDCharacteristicUUIDs: Set<CBUUID> = [
    CBUUID(string: "FFE1"),   // Most common (Vgate iCar Pro, OBDLINK MX+)
    CBUUID(string: "2AF0"),   // Some rebranded ELM327 adapters
    CBUUID(string: "FFF1"),   // Less common variant
    CBUUID(string: "BEF1"),   // Rare variant
    CBUUID(string: "18F1"),   // 18F0 service variant
]

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

    // =========================================================================
    // MARK: - Bridge to OBDDataManager
    // =========================================================================
    /// Set by ContentView after both managers are created.
    var obdDataManager: OBDDataManager?

    // =========================================================================
    // MARK: - Private State
    // =========================================================================
    private var centralManager:   CBCentralManager!
    private var obdCharacteristic: CBCharacteristic?
    private var responseBuffer:   String = ""

    // PID poll timer and rotating index
    private var pidPollTimer:    Timer?
    private var currentPIDIndex: Int = 0

    // AT-command init queue
    private var initQueue:     [String] = []
    private var isInitializing: Bool    = false

    // Test-mode command queue
    private var testQueue:  [String] = []
    private var isTestMode: Bool     = false

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

        // nil services = scan for every advertising device.
        // allowDuplicates:false prevents the list from flooding with RSSI updates.
        centralManager.scanForPeripherals(withServices: nil,
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
    }

    // =========================================================================
    // MARK: - Connection
    // =========================================================================

    func connect(to peripheral: CBPeripheral) {
        stopScanning()
        connectionStatus = "Connecting to \(peripheral.name ?? "Unknown")…"
        centralManager.connect(peripheral, options: nil)
    }

    func disconnect() {
        guard let p = connectedPeripheral else { return }
        stopPIDPolling()
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
            // Init complete — now read VIN
            isInitializing = false
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
        pidPollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.pollNextPID()
        }
    }

    private func stopPIDPolling() {
        pidPollTimer?.invalidate()
        pidPollTimer = nil
    }

    private func pollNextPID() {
        guard isConnected, obdCharacteristic != nil else { return }
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
    // MARK: - BLE Write
    // =========================================================================

    private func write(_ command: String) {
        guard let p = connectedPeripheral,
              let ch = obdCharacteristic,
              let data = command.data(using: .utf8) else { return }

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

        if isTestMode {
            testOBDResult += "← RSP: \(clean)\n"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.sendNextTestCommand()
            }
            return
        }

        // Ignore known non-data ELM327 responses
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
            }
            // After VIN is read, start the live-data polling loop
            startPIDPolling()
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

        discoveredPeripherals.append(DiscoveredPeripheral(
            peripheral: peripheral,
            name:       name,
            rssi:       RSSI.intValue
        ))
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        peripheral.delegate = self
        isConnected = true
        connectionStatus = "Connected to \(peripheral.name ?? "Unknown")"
        obdDataManager?.isConnected = true
        obdDataManager?.connectedDeviceName = peripheral.name ?? "Unknown"

        // Discover all services (nil = all, not filtered)
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        isConnected = false
        connectionStatus = "Connection failed: \(error?.localizedDescription ?? "unknown error")"
        obdDataManager?.isConnected = false
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        connectedPeripheral  = nil
        obdCharacteristic    = nil
        isConnected          = false
        connectionStatus     = "Disconnected"
        obdDataManager?.isConnected          = false
        obdDataManager?.connectedDeviceName  = ""
        stopPIDPolling()
    }
}

// =============================================================================
// MARK: - CBPeripheralDelegate
// =============================================================================
extension BluetoothManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            // Discover all characteristics (nil = all)
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard obdCharacteristic == nil,          // stop once we have one
              let characteristics = service.characteristics else { return }

        for ch in characteristics {
            // Look for known OBD characteristic UUID first, then fall back to
            // any characteristic that supports both write and notify.
            let isKnown = knownOBDCharacteristicUUIDs.contains(ch.uuid)
            let canWrite  = ch.properties.contains(.write) || ch.properties.contains(.writeWithoutResponse)
            let canNotify = ch.properties.contains(.notify) || ch.properties.contains(.indicate)

            if isKnown || (canWrite && canNotify) {
                obdCharacteristic = ch
                peripheral.setNotifyValue(true, for: ch)

                // If simulator is OFF, run the AT init sequence now
                if let mgr = obdDataManager, !mgr.isSimulatorOn {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.initializeOBDDongle()
                    }
                }
                break
            }
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

    init(peripheral: CBPeripheral, name: String, rssi: Int) {
        self.id         = peripheral.identifier
        self.peripheral = peripheral
        self.name       = name
        self.rssi       = rssi
    }
}
