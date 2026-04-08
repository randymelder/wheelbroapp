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
    var distanceToEmpty: Double = 0.0       // miles
    var vin:             String = "—"
    var errorCodes:      String = "None"    // comma-separated DTCs or "None"

    // =========================================================================
    // MARK: - Connection State  (written by BluetoothManager)
    // =========================================================================
    var isConnected:        Bool   = false
    var connectedDeviceName: String = ""

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
        vin            = "1J4BA2D13BL123456"   // Simulated VIN
        errorCodes     = dtcPool.randomElement() ?? "None"
        distanceToEmpty = calculateDistanceToEmpty(fuelLevel: fuelLevel)
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
        case "fuelLevel":
            fuelLevel = Double(value) ?? fuelLevel
            distanceToEmpty = calculateDistanceToEmpty(fuelLevel: fuelLevel)
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

        // One LogEntry row per telemetry key (denormalized schema per spec)
        let pairs: [(String, String)] = [
            ("fuelLevel",       String(format: "%.1f", fuelLevel)),
            ("speed",           String(format: "%.1f", speed)),
            ("rpm",             String(rpm)),
            ("oilTemp",         String(format: "%.1f", oilTemp)),
            ("coolantTemp",     String(format: "%.1f", coolantTemp)),
            ("batteryVoltage",  String(format: "%.2f", batteryVoltage)),
            ("distanceToEmpty", String(format: "%.1f", distanceToEmpty)),
            ("vin",             vin),
            ("errorCodes",      errorCodes)
        ]

        for (key, value) in pairs {
            ctx.insert(LogEntry(
                date:          dateStr,
                time:          timeStr,
                key:           key,
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

    /// Approximate distance to empty for Jeep Wrangler JK.
    /// Tank: 18.6 gal  |  Average MPG: ~15 (conservative off-road estimate)
    private func calculateDistanceToEmpty(fuelLevel: Double) -> Double {
        let tankGallons = 18.6
        let avgMPG      = 15.0
        return (fuelLevel / 100.0) * tankGallons * avgMPG
    }

    // -------------------------------------------------------------------------
    /// Calculates "Time to Empty" from live OBD readings.
    ///
    /// - Parameters:
    ///   - fuelLevel:  Current fuel level, 0–100 %
    ///   - speed:      Current vehicle speed, mph
    ///   - rpm:        Current engine RPM
    ///   - errorCodes: Active DTCs as comma-separated string or "None"
    /// - Returns: Formatted string such as "2h 45m" or "—" when indeterminate.
    ///
    /// **STUB — replace with real implementation:**
    /// The production version should maintain a rolling circular buffer of
    /// (timestamp, fuelLevel) pairs (e.g., last 60 s) and compute the derivative
    /// Δfuel/Δtime as the instantaneous consumption rate in % per second.
    /// Convert that rate to gallons/hour using tank capacity, then divide the
    /// remaining fuel volume by the rate to obtain time remaining in hours.
    func calculateTimeToEmpty(fuelLevel: Double, speed: Double, rpm: Int, errorCodes: String) -> String {
        // Consumption scales with speed and RPM above idle
        let speedFactor = speed > 0 ? (1.0 + (speed / 55.0) * 0.6) : 0.5
        let rpmFactor   = 1.0 + (Double(rpm) / 2000.0) * 0.3

        let tankGallons        = 18.6
        let baseGallonsPerHour = 1.2                      // ~idle consumption
        let adjustedGPH        = baseGallonsPerHour * speedFactor * rpmFactor
        let remainingGallons   = (fuelLevel / 100.0) * tankGallons

        guard adjustedGPH > 0 else { return "—" }
        guard remainingGallons > 0 else { return "0h 0m" }

        let hoursRemaining = remainingGallons / adjustedGPH
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

    private func resetValues() {
        fuelLevel       = 0.0
        speed           = 0.0
        rpm             = 0
        oilTemp         = 0.0
        coolantTemp     = 0.0
        batteryVoltage  = 0.0
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
