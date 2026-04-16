// BluetoothManager.swift
// Full CoreBluetooth implementation for BLE 4.0 OBD-II dongles (ELM327-based,
// compatible with Vgate iCar Pro and similar adapters).
//
// DATA FLOW:
//   1. User taps "Scan for Devices" → startScanning() discovers ALL BLE peripherals.
//   2. User taps a row → connect(to:) initiates a CBCentralManager connection.
//   3. On connect, we discover services/characteristics and subscribe to notify.
//   4. If Simulator is OFF, initializeOBDDongle() sends the AT command sequence.
//   5. startPIDPolling() begins response-driven cycling through pidSequence.
//      VIN (0902) is the last entry in pidSequence and is requested once per cycle.
//   6. Each response is accumulated in a buffer until ">" is seen (ELM327 prompt),
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
// Notify (RX) and write (TX) UUID sets are kept separate because some adapters
// (vLinker / IOS-Vlink on service 18F0) use split characteristics:
//   2AF0 = notify-only (RX)   2AF1 = write-only (TX)
// Other adapters (FFE0 service) use a single characteristic for both.
// ─────────────────────────────────────────────────────────────────────────────
private let knownNotifyUUIDs: Set<CBUUID> = [
    CBUUID(string: "FFE1"),   // FFE0 service — combined RX+TX
    CBUUID(string: "2AF0"),   // 18F0 service — RX notify-only
    CBUUID(string: "FFF1"),   // FFF0 service variant
    CBUUID(string: "BEF1"),   // Rare variant
    CBUUID(string: "18F1"),   // 18F0 legacy variant
]

private let knownWriteUUIDs: Set<CBUUID> = [
    CBUUID(string: "FFE1"),   // FFE0 service — combined RX+TX
    CBUUID(string: "2AF1"),   // 18F0 service — TX write-only
    CBUUID(string: "FFF1"),   // FFF0 service variant
    CBUUID(string: "BEF1"),   // Rare variant
    CBUUID(string: "18F1"),   // 18F0 legacy variant
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

    // Auto-detect failure — set to true when ATSP0 times out without locking in
    var showAutoDetectFailAlert: Bool = false

    // PID Discovery — Phase 1 (bitmask) and Phase 2 (values)
    var discoveredPIDs:    [String]        = []   // "010C", "010D", …
    var pidValueResults:   [String: String] = [:] // "010C" → "1250 RPM"
    var isDiscoveringPIDs: Bool            = false

    // =========================================================================
    // MARK: - Bridge to OBDDataManager
    // =========================================================================
    /// Set by ContentView after both managers are created.
    var obdDataManager: OBDDataManager?

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

    // Counts consecutive SEARCHING/STOPPED responses so we can warn the user
    // when the vehicle ECU isn't responding (ignition off, wrong protocol, etc.)
    private var consecutiveSearchingCount: Int = 0

    // Multi-frame VIN accumulator.
    // ISO 15765-4 CAN delivers the 0902 response across several frames.
    // ELM327 (ATH0) presents them as "0:490201XX…", "1:XX…", "2:XX…".
    // We accumulate hex payload here and decode once we have ≥34 hex chars.
    private var vinFrameBuffer:   String = ""
    private var isCapturingVIN:   Bool   = false

    // Test-mode command queue
    private var testQueue:  [String] = []
    private var isTestMode: Bool     = false

    // Application-level protocol probing (Auto Detect)
    // Each ATSPn is tried in order; the first that produces a valid 410C
    // response wins. All state is reset in disconnect() and startProtocolProbing().
    private var isProtocolProbing:        Bool             = false
    private var probeProtocols:           [String]         = []
    private var probeIndex:               Int              = 0
    private var probeAwaitingPIDResponse: Bool             = false
    private var probeTimeoutWork:         DispatchWorkItem? = nil

    // PID discovery — Phase 1: bitmask range queries
    private var pidDiscoveryQueue:  [String] = []
    private var isPIDDiscoveryMode: Bool     = false

    // PID discovery — Phase 2: per-PID value queries
    private var valuePollingQueue:      [String]          = []
    private var isValuePollingMode:     Bool              = false
    private var currentValuePollPID:    String            = ""
    private var valuePollingTimeoutWork: DispatchWorkItem? = nil

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
    // VIN is appended to the end of the sequence so it is polled once per full
    // cycle (~7 s) rather than as a fire-and-forget one-shot at init time.
    // A one-shot VIN request fired simultaneously with the first pollNextPID()
    // causes a race where the ELM327 receives "0902\r" and "010C\r" in quick
    // succession; the multi-frame VIN response is displaced and never arrives.
    private let pidSequence: [String] = [
        OBDCommand.requestRPM,
        OBDCommand.requestSpeed,
        OBDCommand.requestFuelLevel,
        OBDCommand.requestCoolantTemp,
        OBDCommand.requestOilTemp,
        ATCommand.batteryVoltage,
        OBDCommand.requestFaultCodes,
        OBDCommand.requestVIN,
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

        // Auto-stop after the scan timeout to save battery
        DispatchQueue.main.asyncAfter(deadline: .now() + BLEConstants.scanTimeout) { [weak self] in
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
        initQueue           = []
        testQueue           = []
        pidDiscoveryQueue          = []
        valuePollingQueue          = []
        isInitializing             = false
        isTestMode                 = false
        isPIDDiscoveryMode         = false
        isValuePollingMode         = false
        isDiscoveringPIDs          = false
        currentValuePollPID        = ""
        valuePollingTimeoutWork?.cancel()
        valuePollingTimeoutWork    = nil
        isProtocolProbing          = false
        probeProtocols             = []
        probeIndex                 = 0
        probeAwaitingPIDResponse   = false
        probeTimeoutWork?.cancel()
        probeTimeoutWork           = nil
        responseBuffer             = ""
        consecutiveSearchingCount  = 0
        vinFrameBuffer             = ""
        isCapturingVIN             = false
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
        var queue: [String] = [
            ATCommand.reset,          // 1. Reset chip
            ATCommand.echoOff,        // 2. Echo off
            ATCommand.linefeedsOff,   // 3. Linefeeds off
            ATCommand.spacesOff,      // 4. Spaces off
            ATCommand.headersOff,     // 5. Headers off
        ]
        // Auto Detect skips the ATSP command here — protocol probing sends
        // ATSPn commands one by one after init, testing each with 010C.
        if !(obdDataManager?.selectedProfile.isAutoDetect ?? false) {
            queue.append(obdDataManager?.selectedProfile.obdProtocol ?? "ATSP6\r")  // 6. Fixed protocol
        }
        queue.append(ATCommand.adaptiveTiming)   // last: adaptive timing
        initQueue = queue

        sendNextInitCommand()
    }

    // Human-readable label for each ELM327 AT command (for log output only).
    private func initCommandLabel(_ cmd: String) -> String {
        switch cmd {
        case ATCommand.reset:          return "ATZ  (chip reset)"
        case ATCommand.echoOff:        return "ATE0 (echo off)"
        case ATCommand.linefeedsOff:   return "ATL0 (linefeeds off)"
        case ATCommand.spacesOff:      return "ATS0 (spaces off)"
        case ATCommand.headersOff:     return "ATH0 (headers off)"
        case let cmd where cmd.hasPrefix("ATSP"):
            let label = cmd.replacingOccurrences(of: "\r", with: "")
            if let desc = obdDataManager?.selectedProfile.protocolDescription { return "\(label) (\(desc))" }
            return label
        case ATCommand.adaptiveTiming: return "ATAT1 (adaptive timing)"
        default: return cmd.replacingOccurrences(of: "\r", with: "")
        }
    }

    private func sendNextInitCommand() {
        guard !initQueue.isEmpty else {
            wbLog("[BLE Init] ✓ sequence complete")
            isInitializing = false
            if obdDataManager?.selectedProfile.isAutoDetect == true {
                // Auto Detect: no ATSP was sent during init — probe protocols now.
                wbLog("[BLE Init] Auto Detect profile — starting protocol probing")
                startProtocolProbing()
            } else {
                let proto = obdDataManager?.selectedProfile.obdProtocol.replacingOccurrences(of: "\r", with: "") ?? "?"
                let protoDesc = obdDataManager?.selectedProfile.protocolDescription ?? ""
                wbLog("[BLE Init] Protocol: \(proto) — \(protoDesc)")
                wbLog("[BLE Init] Starting PID polling (VIN included in cycle)")
                // VIN (0902) is the last entry in pidSequence so it is requested once
                // per full 8-PID cycle — no separate one-shot readVIN() needed.
                startPIDPolling()
            }
            return
        }
        let cmd = initQueue.removeFirst()
        let remaining = initQueue.count
        wbLog("[BLE Init] → \(initCommandLabel(cmd))  (\(remaining) remaining)")
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
        write(OBDCommand.requestVIN)
    }

    // =========================================================================
    // MARK: - PID Polling
    // =========================================================================

    private func startPIDPolling() {
        stopPIDPolling()
        currentPIDIndex = 0
        pollNextPID()   // fire immediately so values appear without waiting for the first interval
        pidPollTimer = Timer.scheduledTimer(withTimeInterval: BLEConstants.pidPollInterval, repeats: true) { [weak self] _ in
            self?.pollNextPID()
        }
    }

    private func stopPIDPolling() {
        pidPollTimer?.invalidate()
        pidPollTimer = nil
    }

    private func pollNextPID() {
        // Don't send PID commands while another exclusive mode owns the channel
        guard isConnected,
              obdWriteChar != nil,
              !isInitializing,
              !isProtocolProbing,
              !isTestMode,
              !isPIDDiscoveryMode,
              !isValuePollingMode else {
            wbLog("[PID Poll] skipped — isConnected=\(isConnected) obdWriteChar=\(obdWriteChar == nil ? "nil" : "set") init=\(isInitializing) probing=\(isProtocolProbing) test=\(isTestMode) disc=\(isPIDDiscoveryMode) val=\(isValuePollingMode)")
            return
        }
        let cmd = pidSequence[currentPIDIndex]
        currentPIDIndex = (currentPIDIndex + 1) % pidSequence.count
        wbLog("[PID Poll] → \(cmd.replacingOccurrences(of: "\r", with: ""))")
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
        stopPIDPolling()   // prevent timer firing mid-test and injecting poll responses
        isTestMode   = true
        testOBDResult = "── WheelBro OBD-II Test ──\n\n"

        // VIN + RPM + Fuel Level + Coolant Temp
        testQueue = [OBDCommand.requestVIN, OBDCommand.requestRPM,
                     OBDCommand.requestFuelLevel, OBDCommand.requestCoolantTemp]
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

    /// Queries the vehicle for all supported Mode 01 PIDs by sending the
    /// four range-support commands (0100, 0120, 0140, 0160). Each response is
    /// a 4-byte bitmask. Results accumulate in `discoveredPIDs`.
    func discoverSupportedPIDs() {
        guard isConnected else { return }
        stopPIDPolling()   // prevent poll responses from corrupting discovery state
        discoveredPIDs    = []
        pidValueResults   = [:]
        isDiscoveringPIDs  = true
        isPIDDiscoveryMode = true
        pidDiscoveryQueue  = [OBDCommand.discoverPIDs00, OBDCommand.discoverPIDs20,
                              OBDCommand.discoverPIDs40, OBDCommand.discoverPIDs60]
        sendNextPIDDiscoveryCommand()

        DispatchQueue.main.asyncAfter(deadline: .now() + BLEConstants.discoveryTimeout) { [weak self] in
            guard let self, self.isDiscoveringPIDs else { return }
            self.isPIDDiscoveryMode          = false
            self.isValuePollingMode          = false
            self.isDiscoveringPIDs           = false
            self.pidDiscoveryQueue           = []
            self.valuePollingQueue           = []
            self.currentValuePollPID         = ""
            self.valuePollingTimeoutWork?.cancel()
            self.valuePollingTimeoutWork     = nil
            wbLog("[PID Discovery] Safety timeout — \(self.discoveredPIDs.count) PIDs, \(self.pidValueResults.count) values")
            self.startPIDPolling()
        }
    }

    private func sendNextPIDDiscoveryCommand() {
        guard !pidDiscoveryQueue.isEmpty else {
            // Phase 1 complete — begin Phase 2: query a value for every discovered PID
            isPIDDiscoveryMode = false
            responseBuffer     = ""   // discard any in-flight Phase 1 leftovers
            wbLog("[PID Discovery] Phase 1 complete — \(discoveredPIDs.count) PIDs found. Starting value queries…")
            valuePollingQueue  = discoveredPIDs   // copy so we can mutate the queue
            isValuePollingMode = true
            sendNextValuePollingCommand()
            return
        }
        let cmd = pidDiscoveryQueue.removeFirst()
        wbLog("[PID Discovery] Querying \(cmd.replacingOccurrences(of: "\r", with: ""))…")
        write(cmd)
    }

    private func sendNextValuePollingCommand() {
        // Cancel any pending per-command timeout from the previous PID
        valuePollingTimeoutWork?.cancel()
        valuePollingTimeoutWork = nil

        guard !valuePollingQueue.isEmpty else {
            // Phase 2 complete
            isValuePollingMode = false
            isDiscoveringPIDs  = false
            wbLog("[PID Values] Complete — \(pidValueResults.count) values collected")
            startPIDPolling()
            return
        }
        currentValuePollPID = valuePollingQueue.removeFirst()
        wbLog("[PID Values] Querying \(currentValuePollPID)…")

        // Per-command timeout: if the vehicle doesn't respond within 1.5 s, skip to next PID
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isValuePollingMode else { return }
            wbLog("[PID Values] ← \(self.currentValuePollPID): timeout (no response)")
            self.sendNextValuePollingCommand()
        }
        valuePollingTimeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + BLEConstants.valuePollTimeout, execute: work)

        write("\(currentValuePollPID)\r")
    }

    /// Parses a Mode 01 PID-support response (e.g. "4100BE1FA813") into
    /// individual supported PID strings (e.g. ["010C", "010D", "012F", …]).
    private func parsePIDSupportResponse(_ s: String) {
        // Format: "41" + 2-char range PID + 8 hex chars (4 bytes bitmask)
        guard s.hasPrefix(ELM327Response.mode01Prefix), s.count >= 10 else { return }
        let rangePIDHex = String(s.dropFirst(2).prefix(2))
        guard let rangePID = UInt32(rangePIDHex, radix: 16) else { return }
        let dataHex = String(s.dropFirst(4).prefix(8))
        guard dataHex.count == 8, let bitmask = UInt32(dataHex, radix: 16) else { return }
        // Bit 31 = PID (rangePID + 1), bit 30 = PID (rangePID + 2), …
        // Bit 0 (LSB) = next range indicator — skip it
        wbLog("[PID Discovery] range 0x\(rangePIDHex) bitmask 0x\(dataHex)")
        for bit in 0..<BLEConstants.pidBitmaskBits {
            if (bitmask >> (31 - bit)) & 1 == 1 {
                let pid = rangePID + UInt32(bit) + 1
                let pidStr = String(format: "01%02X", pid)
                // Guard against duplicate lines from multi-frame ELM327 responses
                guard !discoveredPIDs.contains(pidStr) else {
                    wbLog("[PID Discovery]   (dup) \(pidStr)")
                    continue
                }
                discoveredPIDs.append(pidStr)
                wbLog("[PID Discovery]   ✓ \(pidStr)")
            }
        }
    }

    // =========================================================================
    // MARK: - PID Value Parsing
    // =========================================================================

    /// Interprets a raw ELM327 response line for a given PID and returns a
    /// human-readable value string, or "N/A" for NODATA/ERROR responses.
    private func parsePIDValue(pid: String, response: String) -> String {
        guard !response.contains(ELM327Response.noData),
              !response.contains(ELM327Response.error),
              !response.contains(ELM327Response.unableToConnect) else { return "N/A" }

        // Expected format (headers off, spaces off): "41" + 2-char PID hex + data bytes
        let pidHex = String(pid.dropFirst(2)).uppercased()   // "010C" → "0C"
        let prefix = "41\(pidHex)"
        guard response.hasPrefix(prefix) else { return response }
        let data = String(response.dropFirst(prefix.count))
        return decodePIDValue(pidHex: pidHex, data: data) ?? (data.isEmpty ? "N/A" : data)
    }

    /// Maps a 2-char Mode 01 PID hex code + raw data bytes to a formatted string.
    /// Returns nil for unknown PIDs so the caller can fall back to raw hex.
    private func decodePIDValue(pidHex: String, data: String) -> String? {
        // Helpers to extract bytes from the hex data string
        func b(_ n: Int) -> UInt32? {
            guard data.count >= (n + 1) * 2 else { return nil }
            let s = data.index(data.startIndex, offsetBy: n * 2)
            let e = data.index(s, offsetBy: 2)
            return UInt32(data[s..<e], radix: 16)
        }
        func ab() -> UInt32? {       // (A*256)+B two-byte value
            guard let a = b(0), let bv = b(1) else { return nil }
            return a * 256 + bv
        }

        switch pidHex {
        case PIDCode.monitorStatus:
            guard let a = b(0) else { return nil }
            return a & 0x80 != 0 ? "MIL ON" : "MIL OFF"
        case PIDCode.calculatedEngineLoad:
            guard let a = b(0) else { return nil }
            return String(format: "%.1f%%", Double(a) / 2.55)
        case PIDCode.engineCoolantTemp,
             PIDCode.intakeAirTemp,
             PIDCode.ambientAirTemp:
            guard let a = b(0) else { return nil }
            return "\(Int(a) - 40) °C"
        case PIDCode.shortTermFuelTrimBank1,
             PIDCode.longTermFuelTrimBank1,
             PIDCode.shortTermFuelTrimBank2,
             PIDCode.longTermFuelTrimBank2:
            guard let a = b(0) else { return nil }
            return String(format: "%.1f%%", (Double(a) - 128.0) * 100.0 / 128.0)
        case PIDCode.fuelPressureGauge:
            guard let a = b(0) else { return nil }
            return "\(a * 3) kPa"
        case PIDCode.intakeManifoldPressure,
             PIDCode.barometricPressure:
            guard let a = b(0) else { return nil }
            return "\(a) kPa"
        case PIDCode.engineRPM:
            guard let v = ab() else { return nil }
            return String(format: "%.0f RPM", Double(v) / 4.0)
        case PIDCode.vehicleSpeed:
            guard let a = b(0) else { return nil }
            return "\(a) km/h"
        case PIDCode.timingAdvance:
            guard let a = b(0) else { return nil }
            return String(format: "%.1f °", Double(a) / 2.0 - 64.0)
        case PIDCode.mafAirFlowRate:
            guard let v = ab() else { return nil }
            return String(format: "%.2f g/s", Double(v) / 100.0)
        case PIDCode.throttlePosition,
             PIDCode.commandedEGR,
             PIDCode.commandedEvapPurge,
             PIDCode.relativeThrottlePosition,
             PIDCode.commandedThrottleActuator,
             PIDCode.ethanolFuelPercent,
             PIDCode.relativeAccelPedalPos,
             PIDCode.hybridBatteryRemaining:
            guard let a = b(0) else { return nil }
            return String(format: "%.1f%%", Double(a) / 2.55)
        case PIDCode.obdStandard:
            guard let a = b(0) else { return nil }
            let standards = ["OBD-II (CARB)", "OBD (EPA)", "OBD and OBD-II", "OBD-I",
                             "Not OBD compliant", "EOBD", "EOBD and OBD-II", "EOBD and OBD",
                             "EOBD, OBD, OBD-II", "SAE J1939", "EMD"]
            return a > 0 && Int(a) <= standards.count ? standards[Int(a) - 1] : "Type \(a)"
        case PIDCode.runtimeSinceEngineStart,
             PIDCode.distanceSinceCodesCleared:
            guard let v = ab() else { return nil }
            return pidHex == PIDCode.runtimeSinceEngineStart ? "\(v) s" : "\(v) km"
        case PIDCode.distanceTraveledWithMIL:
            guard let v = ab() else { return nil }
            return "\(v) km"
        case PIDCode.fuelRailPressureRelative:
            guard let v = ab() else { return nil }
            return String(format: "%.2f kPa", Double(v) * 0.079)
        case PIDCode.fuelRailPressureAbsolute,
             PIDCode.fuelRailPressureAbsolute2:
            guard let v = ab() else { return nil }
            return "\(v * 10) kPa"
        case PIDCode.egrError:
            guard let a = b(0) else { return nil }
            return String(format: "%.1f%%", (Double(a) - 128.0) * 100.0 / 128.0)
        case PIDCode.fuelTankLevel:
            guard let a = b(0) else { return nil }
            return String(format: "%.1f%%", Double(a) / 2.55)
        case PIDCode.warmupsSinceCodesCleared:
            guard let a = b(0) else { return nil }
            return "\(a)"
        case PIDCode.catalystTempBank1Sensor1,
             PIDCode.catalystTempBank2Sensor1,
             PIDCode.catalystTempBank1Sensor2,
             PIDCode.catalystTempBank2Sensor2:
            guard let v = ab() else { return nil }
            return String(format: "%.1f °C", Double(v) / 10.0 - 40.0)
        case PIDCode.controlModuleVoltage:
            guard let v = ab() else { return nil }
            return String(format: "%.3f V", Double(v) / 1000.0)
        case PIDCode.absoluteLoad:
            guard let v = ab() else { return nil }
            return String(format: "%.1f%%", Double(v) / 2.55)
        case PIDCode.commandedAirFuelRatio:
            guard let v = ab() else { return nil }
            return String(format: "%.4f λ", Double(v) * 0.0000305)
        case PIDCode.timeRunWithMILOn,
             PIDCode.timeSinceCodesCleared:
            guard let v = ab() else { return nil }
            return "\(v) min"
        case PIDCode.fuelType:
            guard let a = b(0) else { return nil }
            let types = ["N/A", "Gasoline", "Methanol", "Ethanol", "Diesel",
                         "LPG", "CNG", "Propane", "Electric", "Bifuel Gasoline/E85",
                         "Bifuel Gasoline/Methanol", "Bifuel Gasoline/CNG",
                         "Bifuel Gasoline/LPG", "Bifuel Diesel/CNG",
                         "Bifuel Diesel/LPG", "Bifuel Gasoline/H2", "Bifuel Diesel/H2"]
            return Int(a) < types.count ? types[Int(a)] : "Type \(a)"
        case PIDCode.engineOilTemp:
            guard let a = b(0) else { return nil }
            return "\(Int(a) - 40) °C"
        case PIDCode.engineFuelRate:
            guard let v = ab() else { return nil }
            return String(format: "%.2f L/h", Double(v) / 20.0)
        default:
            return nil   // caller will use raw hex
        }
    }

    // =========================================================================
    // MARK: - Protocol Probing  (Auto Detect)
    // =========================================================================
    // When the user selects "Auto Detect", the init sequence runs WITHOUT an
    // ATSPn command. On completion, startProtocolProbing() takes over the
    // channel, sends ATSPn + 010C for each candidate, and locks on the first
    // protocol that returns a valid Mode 01 response.
    //
    // Probe order: CAN variants first (most modern vehicles), then ISO/KWP,
    // then older SAE protocols. Total worst-case time: 9 × 3 s = 27 s.
    // =========================================================================

    private let probeProtocolList: [String] = [
        "ATSP6\r",   // ISO 15765-4 CAN, 11-bit ID, 500 kbaud  ← most common modern
        "ATSP7\r",   // ISO 15765-4 CAN, 29-bit ID, 500 kbaud
        "ATSP8\r",   // ISO 15765-4 CAN, 11-bit ID, 250 kbaud
        "ATSP9\r",   // ISO 15765-4 CAN, 29-bit ID, 250 kbaud
        "ATSP5\r",   // ISO 14230-4 KWP2000 (fast init)
        "ATSP4\r",   // ISO 14230-4 KWP2000 (5-baud init)
        "ATSP3\r",   // ISO 9141-2
        "ATSP2\r",   // SAE J1850 VPW
        "ATSP1\r",   // SAE J1850 PWM
    ]

    private func startProtocolProbing() {
        probeProtocols           = probeProtocolList
        probeIndex               = 0
        isProtocolProbing        = true
        probeAwaitingPIDResponse = false
        wbLog("[Auto Detect] Starting protocol probing — \(probeProtocols.count) protocols to try")
        sendNextProbeCommand()
    }

    private func sendNextProbeCommand() {
        guard probeIndex < probeProtocols.count else {
            // All protocols exhausted — alert the user
            wbLog("[Auto Detect] ✗ All \(probeProtocols.count) protocols tried; none responded — showing failure alert")
            isProtocolProbing = false
            showAutoDetectFailAlert = true
            disconnect()
            return
        }
        let proto = probeProtocols[probeIndex].replacingOccurrences(of: "\r", with: "")
        wbLog("[Auto Detect] Trying \(proto) (\(probeIndex + 1)/\(probeProtocols.count))…")
        probeAwaitingPIDResponse = false
        write(probeProtocols[probeIndex])
    }

    /// Routes an incoming line through the probing state machine.
    /// Called from processLine() when isProtocolProbing is true.
    private func handleProbeResponse(_ clean: String) {
        if !probeAwaitingPIDResponse {
            // ── State: waiting for ATSPn acknowledgement ("OK") ──────────────
            if clean == "OK" {
                let proto = probeProtocols[probeIndex].replacingOccurrences(of: "\r", with: "")
                wbLog("[Auto Detect] \(proto) accepted — sending test PID (010C)")
                probeAwaitingPIDResponse = true
                scheduleProbeTimeout()
                write(OBDCommand.requestRPM)   // "010C\r"
            } else if clean.contains(ELM327Response.error) ||
                      clean.contains(ELM327Response.unableToConnect) {
                let proto = probeProtocols[probeIndex].replacingOccurrences(of: "\r", with: "")
                wbLog("[Auto Detect] \(proto) rejected immediately (\(clean))")
                cancelProbeTimeout()
                probeIndex += 1
                sendNextProbeCommand()
            }
            // NODATA / SEARCHING / adapter noise while awaiting OK → ignore;
            // they are stale responses from the previous protocol attempt.
        } else {
            // ── State: waiting for 010C (RPM) response ───────────────────────
            if clean.hasPrefix(ELM327Response.mode01Prefix) {
                // Any Mode 01 response confirms the protocol works
                let proto = probeProtocols[probeIndex].replacingOccurrences(of: "\r", with: "")
                wbLog("[Auto Detect] ✓ Protocol locked: \(proto)")
                cancelProbeTimeout()
                isProtocolProbing = false
                // Feed the RPM response into normal parsing so first values land immediately
                parseOBDLine(clean)
                startPIDPolling()
            } else if clean.contains(ELM327Response.noData)          ||
                      clean.contains(ELM327Response.searching)        ||
                      clean.contains(ELM327Response.stopped)          ||
                      clean.contains(ELM327Response.error)            ||
                      clean.contains(ELM327Response.unableToConnect) {
                let proto = probeProtocols[probeIndex].replacingOccurrences(of: "\r", with: "")
                wbLog("[Auto Detect] \(proto) failed (\(clean)) — trying next")
                cancelProbeTimeout()
                probeIndex += 1
                sendNextProbeCommand()
            }
            // Other adapter noise ("BUS INIT...", "CONNECTING...", byte-count
            // ISO-TP headers) → ignore; probeTimeoutWork will advance if needed.
        }
    }

    private func scheduleProbeTimeout() {
        probeTimeoutWork?.cancel()
        probeTimeoutWork = nil
        let capturedIndex = probeIndex
        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  self.isProtocolProbing,
                  self.probeIndex == capturedIndex else { return }
            let proto = self.probeProtocols[self.probeIndex].replacingOccurrences(of: "\r", with: "")
            wbLog("[Auto Detect] \(proto) timed out after \(BLEConstants.probeTimeoutPerProtocol) s — trying next")
            self.probeIndex += 1
            self.sendNextProbeCommand()
        }
        probeTimeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + BLEConstants.probeTimeoutPerProtocol, execute: work)
    }

    private func cancelProbeTimeout() {
        probeTimeoutWork?.cancel()
        probeTimeoutWork = nil
    }

    // =========================================================================
    // MARK: - BLE Write
    // =========================================================================

    private func write(_ command: String) {
        guard let p = connectedPeripheral,
              let ch = obdWriteChar,
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
        let escaped = raw.replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\n", with: "\\n")
        wbLog("[BLE Raw] \(escaped)")
        responseBuffer += raw

        guard responseBuffer.contains(ELM327Response.prompt) else { return }

        let full = responseBuffer
        responseBuffer = ""

        // Split on newlines, process each non-empty, non-prompt line
        let lines = full.components(separatedBy: CharacterSet.newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != ELM327Response.prompt else { continue }
            processLine(trimmed)
        }
    }

    private func processLine(_ line: String) {
        // Normalise: uppercase, strip spaces for hex parsing
        let clean = line.replacingOccurrences(of: " ", with: "").uppercased()

        if isInitializing {
            wbLog("[BLE Init] ← \(clean)")
            sendNextInitCommand()
            return
        }

        if isProtocolProbing {
            handleProbeResponse(clean)
            return
        }

        if isTestMode {
            testOBDResult += "← RSP: \(clean)\n"
            DispatchQueue.main.asyncAfter(deadline: .now() + BLEConstants.testCommandDelay) { [weak self] in
                self?.sendNextTestCommand()
            }
            return
        }

        if isPIDDiscoveryMode {
            wbLog("[PID Discovery] ← \(clean)")
            parsePIDSupportResponse(clean)
            DispatchQueue.main.asyncAfter(deadline: .now() + BLEConstants.discoveryCommandDelay) { [weak self] in
                self?.sendNextPIDDiscoveryCommand()
            }
            return
        }

        if isValuePollingMode {
            // Only advance when this line is the response for currentValuePollPID.
            // Stale in-flight lines from Phase 1 (or prior commands) must be discarded
            // silently — advancing on them would store the value against the wrong PID.
            let pidHex        = String(currentValuePollPID.dropFirst(2)).uppercased()
            let expectedPrefix = "41\(pidHex)"
            let isTerminal    = clean.contains(ELM327Response.noData) ||
                                clean.contains(ELM327Response.error)  ||
                                clean.contains(ELM327Response.unableToConnect)
            guard clean.hasPrefix(expectedPrefix) || isTerminal else {
                wbLog("[PID Values] ← (stale/ignored): \(clean)")
                return
            }
            // Cancel the per-command timeout — we have a real response
            valuePollingTimeoutWork?.cancel()
            valuePollingTimeoutWork = nil
            wbLog("[PID Values] ← \(currentValuePollPID): \(clean)")
            pidValueResults[currentValuePollPID] = parsePIDValue(pid: currentValuePollPID, response: clean)
            sendNextValuePollingCommand()
            return
        }

        // Ignore known non-data ELM327 responses, but still advance to the
        // next PID so a NODATA/STOPPED/ERROR doesn't stall the polling cycle.
        // SEARCHING… and STOPPED mean the ignition is off and the ELM327 can't
        // find the vehicle's CAN bus — treat them the same as NODATA.
        let isSearching = clean.contains(ELM327Response.stopped) ||
                          clean.contains(ELM327Response.searching)
        guard !clean.contains(ELM327Response.noData),
              !clean.contains(ELM327Response.error),
              !clean.contains(ELM327Response.unableToConnect),
              !isSearching,
              !clean.hasPrefix(ELM327Response.elmPrefix) else {
            if isSearching {
                consecutiveSearchingCount += 1
                // Log a diagnostic hint on first detection, then every 10 cycles
                if consecutiveSearchingCount == 1 {
                    wbLog("[OBD Diag] ⚠️  SEARCHING/STOPPED detected — vehicle ECU not responding")
                    let p = obdDataManager?.selectedProfile.obdProtocol.replacingOccurrences(of: "\r", with: "") ?? "?"
                    let d = obdDataManager?.selectedProfile.protocolDescription ?? ""
                    wbLog("[OBD Diag]    Protocol: \(p) — \(d)")
                    wbLog("[OBD Diag]    Confirm: ignition in ON/RUN position, OBD port seated")
                } else if consecutiveSearchingCount % 10 == 0 {
                    wbLog("[OBD Diag] ⚠️  Still searching (\(consecutiveSearchingCount) cycles) — ECU unresponsive")
                }
            } else {
                wbLog("[OBD Poll] ← (no data) \(clean)")
            }
            pollNextPID()   // response-driven: advance immediately even on NODATA
            return
        }

        // A response passed the guard — reset the searching counter.
        consecutiveSearchingCount = 0

        wbLog("[OBD Poll] ← \(clean)")
        parseOBDLine(clean)
        pollNextPID()   // response-driven: send next PID immediately after parsing
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
        if s.hasPrefix(ELM327Response.mode01Prefix), s.count >= 6 {
            let pidHex  = String(s.dropFirst(2).prefix(2))
            let payload = String(s.dropFirst(4))

            switch pidHex {

            case PIDCode.engineRPM:
                // Engine RPM  = ((A * 256) + B) / 4
                guard payload.count >= 4,
                      let a = UInt32(payload.prefix(2), radix: 16),
                      let b = UInt32(payload.dropFirst(2).prefix(2), radix: 16)
                else { return }
                let rpm = Int((a * 256 + b) / 4)
                obdDataManager?.updateFromOBD(key: OBDKey.rpm, value: String(rpm))

            case PIDCode.vehicleSpeed:
                // Vehicle Speed  = A km/h → mph
                guard let a = UInt32(payload.prefix(2), radix: 16) else { return }
                let mph = Double(a) * 0.621371
                obdDataManager?.updateFromOBD(key: OBDKey.speed, value: String(format: "%.1f", mph))

            case PIDCode.fuelTankLevel:
                // Fuel Tank Level  = A / 2.55  (%)
                guard let a = UInt32(payload.prefix(2), radix: 16) else { return }
                let pct = Double(a) / 2.55
                obdDataManager?.updateFromOBD(key: OBDKey.fuelLevel, value: String(format: "%.1f", pct))

            case PIDCode.engineCoolantTemp:
                // Engine Coolant Temp  = A − 40  (°C) → °F
                guard let a = UInt32(payload.prefix(2), radix: 16) else { return }
                let f = celsiusToFahrenheit(Double(a) - 40)
                obdDataManager?.updateFromOBD(key: OBDKey.coolantTemp, value: String(format: "%.1f", f))

            case PIDCode.engineOilTemp:
                // Engine Oil Temp  = A − 40  (°C) → °F
                guard let a = UInt32(payload.prefix(2), radix: 16) else { return }
                let f = celsiusToFahrenheit(Double(a) - 40)
                obdDataManager?.updateFromOBD(key: OBDKey.oilTemp, value: String(format: "%.1f", f))

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
        // ELM327 on ISO 15765-4 CAN produces multi-frame ISO-TP responses.
        // With ATH0 (headers off) the format is:
        //   "0:490201XXXXXX"  ← first frame  (frame index "0:" + "4902" marker + data)
        //   "1:XXXXXXXXXXXX"  ← continuation frame
        //   "2:XXXXXXXXXXXX"  ← continuation frame
        //   …
        // Some adapters reassemble and emit a single line "490201XXXXXX".
        // We handle both by looking for the "4902" marker and buffering frames.

        // ── Single-frame or reassembled: starts directly with "4902" ──────────
        if s.hasPrefix(ELM327Response.vinPrefix), s.count > 8 {
            wbLog("[OBD VIN] single-frame response: \(s)")
            decodeVINHex(String(s.dropFirst(6)))   // drop "490201"
            isCapturingVIN = false
            vinFrameBuffer = ""
            return
        }

        // ── Multi-frame first frame: "0:4902..." ──────────────────────────────
        if s.hasPrefix("0:"), s.contains(ELM327Response.vinPrefix) {
            let stripped = String(s.dropFirst(2))   // remove "0:"
            guard let markerRange = stripped.range(of: ELM327Response.vinPrefix) else { return }
            // Skip past "490201" (6 chars from the "4902" marker + "01" byte count)
            let afterMarker = stripped[markerRange.lowerBound...]
            guard afterMarker.count >= 6 else { return }
            let firstChunk = String(afterMarker.dropFirst(6))
            wbLog("[OBD VIN] multi-frame start: \(s)  payload so far: \(firstChunk)")
            vinFrameBuffer = firstChunk
            isCapturingVIN = true
            return
        }

        // ── Multi-frame continuation: "1:XX…", "2:XX…", etc. ─────────────────
        if isCapturingVIN,
           s.count >= 3,
           let _ = s.first.flatMap({ Int(String($0), radix: 16) }),
           s.dropFirst(1).hasPrefix(":") {
            let chunk = String(s.dropFirst(2))   // remove "N:"
            vinFrameBuffer += chunk
            wbLog("[OBD VIN] multi-frame cont \(s.prefix(2)) payload: \(vinFrameBuffer)")
            // 17 VIN bytes = 34 hex chars minimum
            if vinFrameBuffer.count >= 34 {
                decodeVINHex(vinFrameBuffer)
                isCapturingVIN = false
                vinFrameBuffer = ""
            }
            return
        }

        // ── ISO-TP byte-count header line (e.g. "014") — precedes first frame ─
        // Silently ignore; it carries no VIN data.
        if s.count <= 4,
           s.allSatisfy({ $0.isHexDigit }) {
            return
        }

        // ── Mode 03: DTCs ─────────────────────────────────────────────────────
        // Response prefix: "43" followed by groups of 4 hex chars per DTC.
        // "4300000000000000" = no faults stored.
        if s.hasPrefix(ELM327Response.dtcPrefix), s.count >= 4 {
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
            obdDataManager?.updateFromOBD(key: OBDKey.errorCodes, value: result.isEmpty ? "None" : result)
            return
        }

        // ── AT RV: Battery Voltage ─────────────────────────────────────────────
        // Response: "12.3V" or "14.2V"
        if s.hasSuffix(ELM327Response.battVoltageSuffix), let voltage = Double(s.dropLast()) {
            obdDataManager?.updateFromOBD(key: OBDKey.batteryVoltage, value: String(format: "%.2f", voltage))
        }
    }

    // =========================================================================
    // MARK: - Helpers
    // =========================================================================

    /// Decodes a raw hex string of VIN bytes into an ASCII VIN string and
    /// forwards it to OBDDataManager.  Works for both single-frame and
    /// accumulated multi-frame payloads.
    private func decodeVINHex(_ hex: String) {
        var vinStr = ""
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            // Only accept printable ASCII (0x20–0x7E).
            // 0xFF ("ÿ") and other high bytes indicate ECU fill/padding — discard them.
            if let byte = UInt8(hex[idx..<next], radix: 16), byte >= 0x20, byte < 0x7F {
                vinStr.append(Character(UnicodeScalar(byte)))
            }
            idx = next
        }
        // Real VINs are exactly 17 alphanumeric chars; accept ≥10 as a plausibility check.
        if vinStr.count >= 10 {
            wbLog("[OBD VIN] decoded: \(vinStr) (\(vinStr.count) chars)")
            obdDataManager?.updateFromOBD(key: OBDKey.vin, value: vinStr)
        } else if vinStr.isEmpty {
            // ECU returned all fill bytes (e.g. 0xFF) — VIN not stored in OBD-II Mode 09.
            wbLog("[OBD VIN] ECU returned fill bytes — VIN not available via Mode 09 on this vehicle")
            obdDataManager?.updateFromOBD(key: OBDKey.vin, value: "Not available")
        } else {
            wbLog("[OBD VIN] decode failed — only \(vinStr.count) printable chars from hex: \(hex)")
        }
    }

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
        print("===> Found: \(name)")
        if (name.lowercased().localizedCaseInsensitiveContains("vlink".lowercased())) {
            discoveredPeripherals.append(DiscoveredPeripheral(
                peripheral: peripheral,
                name:       name,
                rssi:       RSSI.intValue
            ))
        }
        else {
            return;
        }
        
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
        obdNotifyChar        = nil
        obdWriteChar         = nil
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
        guard let characteristics = service.characteristics else { return }

        for ch in characteristics {
            let canWrite  = ch.properties.contains(.write) || ch.properties.contains(.writeWithoutResponse)
            let canNotify = ch.properties.contains(.notify) || ch.properties.contains(.indicate)

            // Assign the best notify char: prefer known UUID, fall back to any notify-capable char
            if obdNotifyChar == nil && (knownNotifyUUIDs.contains(ch.uuid) || canNotify) {
                obdNotifyChar = ch
                peripheral.setNotifyValue(true, for: ch)
            }

            // Assign the best write char: prefer known UUID, fall back to any write-capable char
            if obdWriteChar == nil && (knownWriteUUIDs.contains(ch.uuid) || canWrite) {
                obdWriteChar = ch
            }
        }

        // Init will be triggered from didUpdateNotificationStateFor once the
        // notify subscription is confirmed — no fixed delay needed here.
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
        // Notification subscription confirmed on the notify characteristic.
        // This is the earliest safe moment to write AT commands — the adapter is
        // now fully ready to receive writes and send back notifications.
        guard error == nil,
              characteristic == obdNotifyChar,
              obdWriteChar != nil,
              !isInitializing else { return }
        if let mgr = obdDataManager, !mgr.isSimulatorOn {
            isInitializing = true
            initializeOBDDongle()
        }
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
