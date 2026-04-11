// OBDDataManager.swift
// Central data model for live OBD-II readings.
// Handles both Simulator mode (fake data every 5 s) and real BLE mode
// (values pushed in by BluetoothManager after PID parsing).
// Also owns the 10-second logging timer and the 1-hour retention sweep.

import Foundation
import SwiftData
import Observation

@Observable
final class OBDDataManager {

    // =========================================================================
    // MARK: - Live OBD Readings
    // =========================================================================
    var fuelLevel:       Double = 0.0       // percent (0–100)
    var speed:           Double = 0.0       // mph
    var rpm:             Int    = 0         // engine RPM
    var oilTemp:         Double = 0.0       // °F
    var coolantTemp:     Double = 0.0       // °F
    var batteryVoltage:  Double = 0.0       // V
    var fuelRate:        Double = 0.0       // L/hr from PID 5E; 0 = not available
    var distanceToEmpty: Double = 0.0       // miles
    var vin:             String = "—"
    var errorCodes:      String = "None"    // comma-separated DTCs or "None"

    // =========================================================================
    // MARK: - Connection State  (written by BluetoothManager)
    // =========================================================================
    var isConnected: Bool = false {
        didSet { if isConnected { currentSessionID = UUID().uuidString } }
    }
    var connectedDeviceName: String = ""

    // =========================================================================
    // MARK: - Session Tracking
    // =========================================================================
    /// Regenerated each time a BLE device connects or the simulator starts.
    /// Written to every LogEntry so rows from the same session can be grouped.
    private(set) var currentSessionID: String = UUID().uuidString

    // =========================================================================
    // MARK: - Settings  (persisted in UserDefaults)
    // =========================================================================
    // Simulator defaults to ON per spec.
    var isSimulatorOn: Bool {
        didSet { UserDefaults.standard.set(isSimulatorOn, forKey: "isSimulatorOn")
                 handleSimulatorChange() }
    }
    var isLoggingEnabled: Bool {
        didSet { UserDefaults.standard.set(isLoggingEnabled, forKey: "isLoggingEnabled")
                 handleLoggingChange() }
    }

    // =========================================================================
    // MARK: - Private State
    // =========================================================================
    private var simulatorTimer: Timer?
    private var loggingTimer:   Timer?
    private var modelContext:   ModelContext?

    // Pool used for simulated DTC rotation
    private let dtcPool: [String] = [
        "None", "None", "None", "None",
        "P0300", "P0171", "P0300,P0171", "P0420"
    ]

    // =========================================================================
    // MARK: - Init
    // =========================================================================
    init() {
        // Restore persisted settings; default simulator to true on first launch
        if UserDefaults.standard.object(forKey: "isSimulatorOn") == nil {
            UserDefaults.standard.set(true, forKey: "isSimulatorOn")
            self.isSimulatorOn = true
        } else {
            self.isSimulatorOn = UserDefaults.standard.bool(forKey: "isSimulatorOn")
        }
        self.isLoggingEnabled = UserDefaults.standard.bool(forKey: "isLoggingEnabled")
    }

    // =========================================================================
    // MARK: - Setup  (called from ContentView after environment is ready)
    // =========================================================================
    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
        if isSimulatorOn {
            startSimulator()
        }
        startLoggingIfNeeded()
    }

    // =========================================================================
    // MARK: - Simulator
    // =========================================================================
    func startSimulator() {
        stopSimulator()
        currentSessionID = UUID().uuidString   // new session each simulator start
        // Fire once immediately so the UI isn't blank on first load
        updateSimulatedValues()
        simulatorTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateSimulatedValues()
        }
    }

    func stopSimulator() {
        simulatorTimer?.invalidate()
        simulatorTimer = nil
    }

    private func updateSimulatedValues() {
        fuelLevel      = Double.random(in: 20...80)
        speed          = Double.random(in: 0...80)
        rpm            = Int.random(in: 800...3500)
        oilTemp        = Double.random(in: 80...220)
        coolantTemp    = Double.random(in: 180...220)
        batteryVoltage = Double.random(in: 12.0...14.5)
        fuelRate       = Double.random(in: 4.0...18.0)   // L/hr; typical JK range
        vin            = "1J4BA2D13BL123456"              // Simulated VIN
        errorCodes     = dtcPool.randomElement() ?? "None"
        distanceToEmpty = calculateDistanceToEmpty(fuelLevel: fuelLevel, speed: speed, fuelRate: fuelRate)
    }

    // =========================================================================
    // MARK: - Real OBD Updates  (called by BluetoothManager after parsing)
    // =========================================================================
    func updateFromOBD(key: String, value: String) {
        switch key {
        case "rpm":
            rpm = Int(value) ?? rpm
        case "speed":
            speed = Double(value) ?? speed
            distanceToEmpty = calculateDistanceToEmpty(fuelLevel: fuelLevel, speed: speed, fuelRate: fuelRate)
        case "fuelRate":
            fuelRate = Double(value) ?? fuelRate
            distanceToEmpty = calculateDistanceToEmpty(fuelLevel: fuelLevel, speed: speed, fuelRate: fuelRate)
        case "fuelLevel":
            fuelLevel = Double(value) ?? fuelLevel
            distanceToEmpty = calculateDistanceToEmpty(fuelLevel: fuelLevel, speed: speed, fuelRate: fuelRate)
        case "oilTemp":
            oilTemp = Double(value) ?? oilTemp
        case "coolantTemp":
            coolantTemp = Double(value) ?? coolantTemp
        case "batteryVoltage":
            batteryVoltage = Double(value) ?? batteryVoltage
        case "vin":
            vin = value
        case "errorCodes":
            errorCodes = value.isEmpty ? "None" : value
        default:
            break
        }
    }

    // =========================================================================
    // MARK: - Logging  (one row per key every 10 s; rows older than 1 h purged)
    // =========================================================================
    func startLoggingIfNeeded() {
        guard isLoggingEnabled, (isConnected || isSimulatorOn) else { return }
        stopLogging()
        loggingTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.logCurrentValues()
        }
    }

    func stopLogging() {
        loggingTimer?.invalidate()
        loggingTimer = nil
    }

    private func logCurrentValues() {
        guard let ctx = modelContext else { return }

        let now = Date()
        let df  = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let dateStr = df.string(from: now)
        df.dateFormat = "HH:mm:ss"
        let timeStr = df.string(from: now)

        let deviceName = isSimulatorOn ? "Simulator" : connectedDeviceName
        let sid        = currentSessionID

        // Maps each telemetry key to its OBD PID/command and engineering unit.
        // pid  — raw ELM327 command without mode prefix (or AT command for ATRV)
        // unit — display unit written into every row for self-describing CSV export
        let pidForKey:  [String: String] = [
            "fuelLevel":       "2F",
            "speed":           "0D",
            "rpm":             "0C",
            "oilTemp":         "5C",
            "coolantTemp":     "05",
            "batteryVoltage":  "ATRV",
            "fuelRate":        "5E",
            "distanceToEmpty": "",      // computed — no single PID
            "vin":             "0902",
            "errorCodes":      "03",
        ]
        let unitForKey: [String: String] = [
            "fuelLevel":       "%",
            "speed":           "mph",
            "rpm":             "rpm",
            "oilTemp":         "°F",
            "coolantTemp":     "°F",
            "batteryVoltage":  "V",
            "fuelRate":        "L/hr",
            "distanceToEmpty": "mi",
            "vin":             "",
            "errorCodes":      "",
        ]

        // One LogEntry row per telemetry key (denormalized schema per spec)
        let pairs: [(String, String)] = [
            ("fuelLevel",       String(format: "%.1f", fuelLevel)),
            ("speed",           String(format: "%.1f", speed)),
            ("rpm",             String(rpm)),
            ("oilTemp",         String(format: "%.1f", oilTemp)),
            ("coolantTemp",     String(format: "%.1f", coolantTemp)),
            ("batteryVoltage",  String(format: "%.2f", batteryVoltage)),
            ("fuelRate",        String(format: "%.3f", fuelRate)),
            ("distanceToEmpty", String(format: "%.1f", distanceToEmpty)),
            ("vin",             vin),
            ("errorCodes",      errorCodes),
        ]

        for (key, value) in pairs {
            ctx.insert(LogEntry(
                date:          dateStr,
                time:          timeStr,
                sessionID:     sid,
                key:           key,
                pid:           pidForKey[key]  ?? "",
                unit:          unitForKey[key] ?? "",
                value:         value,
                bleDeviceName: deviceName,
                vinNumber:     vin
            ))
        }

        pruneOldEntries(ctx: ctx)
        try? ctx.save()
    }

    /// Deletes LogEntry rows whose timestamp is older than 1 hour.
    private func pruneOldEntries(ctx: ModelContext) {
        let cutoff   = Date().addingTimeInterval(-3600)
        let combined = DateFormatter()
        combined.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let descriptor = FetchDescriptor<LogEntry>()
        guard let all = try? ctx.fetch(descriptor) else { return }

        for entry in all {
            let stamp = "\(entry.date) \(entry.time)"
            if let d = combined.date(from: stamp), d < cutoff {
                ctx.delete(entry)
            }
        }
    }

    // =========================================================================
    // MARK: - Derived Calculations
    // =========================================================================

    /// Distance to empty (miles) for Jeep Wrangler JK (18.6 gal tank).
    ///
    /// When PID 5E fuel rate is available and the vehicle is moving, uses
    /// instantaneous MPG (speed ÷ GPH) for accuracy. Falls back to a static
    /// 15 MPG average when the vehicle is stopped or fuel rate is unavailable.
    private func calculateDistanceToEmpty(fuelLevel: Double, speed: Double, fuelRate: Double) -> Double {
        let tankGallons      = 18.6
        let remainingGallons = (fuelLevel / 100.0) * tankGallons

        if fuelRate > 0, speed > 5 {
            let gph = fuelRate / 3.78541
            let instantaneousMPG = speed / gph
            return remainingGallons * instantaneousMPG
        }

        // Fallback: conservative static average for JK
        return remainingGallons * 15.0
    }

    // -------------------------------------------------------------------------
    /// Time to empty using PID 5E (fuel rate in L/hr) as the primary source.
    ///
    /// When PID 5E is available (fuelRate > 0), the ECU's own fuel flow
    /// measurement is used directly — it already accounts for load, enrichment,
    /// deceleration cutoff, etc. Falls back to a speed/RPM heuristic model
    /// when PID 5E returns no data.
    func calculateTimeToEmpty(fuelLevel: Double, speed: Double, rpm: Int, errorCodes: String) -> String {
        let tankGallons      = 18.6
        let remainingGallons = (fuelLevel / 100.0) * tankGallons

        guard remainingGallons > 0 else { return "0h 0m" }

        let gph: Double
        if fuelRate > 0 {
            // Primary: ECU-measured fuel flow (PID 5E)
            gph = fuelRate / 3.78541
        } else {
            // Fallback: speed/RPM heuristic
            let speedFactor = speed > 0 ? (1.0 + (speed / 55.0) * 0.6) : 0.5
            let rpmFactor   = 1.0 + (Double(rpm) / 2000.0) * 0.3
            gph = 1.2 * speedFactor * rpmFactor   // 1.2 GPH base ≈ JK idle
        }

        guard gph > 0 else { return "—" }

        let hoursRemaining = remainingGallons / gph
        let h = Int(hoursRemaining)
        let m = Int((hoursRemaining - Double(h)) * 60)

        switch (h, m) {
        case (0, 0): return "< 1m"
        case (0, _): return "\(m)m"
        default:     return "\(h)h \(m)m"
        }
    }

    // =========================================================================
    // MARK: - Settings-Change Handlers
    // =========================================================================
    private func handleSimulatorChange() {
        if isSimulatorOn {
            startSimulator()
            // Reset to simulated VIN
            vin = "1J4BA2D13BL123456"
        } else {
            stopSimulator()
            resetValues()
        }
        // Re-evaluate logging (it only runs when connected or in sim mode)
        handleLoggingChange()
    }

    func resetValues() {
        fuelLevel       = 0.0
        speed           = 0.0
        rpm             = 0
        oilTemp         = 0.0
        coolantTemp     = 0.0
        batteryVoltage  = 0.0
        fuelRate        = 0.0
        distanceToEmpty = 0.0
        vin             = "—"
        errorCodes      = "None"
    }

    private func handleLoggingChange() {
        if isLoggingEnabled {
            startLoggingIfNeeded()
        } else {
            stopLogging()
        }
    }
}
