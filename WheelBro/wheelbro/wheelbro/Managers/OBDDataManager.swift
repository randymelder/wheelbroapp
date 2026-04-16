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
    var isConnected: Bool = false {
        didSet { handleLoggingChange() }
    }
    var connectedDeviceName: String = ""

    // =========================================================================
    // MARK: - Settings  (persisted in UserDefaults)
    // =========================================================================
    // Simulator defaults to ON per spec.
    var isSimulatorOn: Bool {
        didSet { UserDefaults.standard.set(isSimulatorOn, forKey: UserDefaultsKey.isSimulatorOn)
                 handleSimulatorChange() }
    }
    var isLoggingEnabled: Bool {
        didSet { UserDefaults.standard.set(isLoggingEnabled, forKey: UserDefaultsKey.isLoggingEnabled)
                 handleLoggingChange() }
    }
    var selectedProfile: VehicleProfile {
        didSet { UserDefaults.standard.set(selectedProfile.id, forKey: UserDefaultsKey.selectedVehicle) }
    }

    // =========================================================================
    // MARK: - Private State
    // =========================================================================
    private var simulatorTimer: Timer?
    private var loggingTimer:   Timer?
    private var modelContext:   ModelContext?

    // Tracks which OBD keys have been received at least once from the vehicle.
    // Values that have never been updated stay at their initial defaults and
    // should not be logged — they would pollute the dataset with meaningless zeros.
    private var receivedKeys: Set<String> = []

    // Pool used for simulated DTC rotation
    private let dtcPool: [String] = [
        "None", "None", "None", "None",
        "P0300", "P0171", "P0300,P0171", "P0420"
    ]

    // =========================================================================
    // MARK: - Init
    // =========================================================================
    init() {
        // Restore persisted vehicle profile; default to JK on first launch.
        let savedID = UserDefaults.standard.string(forKey: UserDefaultsKey.selectedVehicle)
        self.selectedProfile = VehicleProfile.all.first { $0.id == savedID } ?? .default

        // Restore persisted settings; default simulator to true on first launch
        if UserDefaults.standard.object(forKey: UserDefaultsKey.isSimulatorOn) == nil {
            UserDefaults.standard.set(true, forKey: UserDefaultsKey.isSimulatorOn)
            self.isSimulatorOn = true
        } else {
            self.isSimulatorOn = UserDefaults.standard.bool(forKey: UserDefaultsKey.isSimulatorOn)
        }
        // Logging defaults to OFF on first launch.
        // UserDefaults.bool returns false when the key is absent, but we write
        // the key explicitly so the intent is unambiguous.
        if UserDefaults.standard.object(forKey: UserDefaultsKey.isLoggingEnabled) == nil {
            UserDefaults.standard.set(false, forKey: UserDefaultsKey.isLoggingEnabled)
            self.isLoggingEnabled = false
        } else {
            self.isLoggingEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKey.isLoggingEnabled)
        }
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
        simulatorTimer = Timer.scheduledTimer(withTimeInterval: VehicleConstants.simulatorUpdateInterval, repeats: true) { [weak self] _ in
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
        vin            = VehicleConstants.simulatedVIN
        errorCodes     = dtcPool.randomElement() ?? "None"
        distanceToEmpty = calculateDistanceToEmpty(fuelLevel: fuelLevel)
    }

    // =========================================================================
    // MARK: - Real OBD Updates  (called by BluetoothManager after parsing)
    // =========================================================================
    func updateFromOBD(key: String, value: String) {
        wbLog("[OBD DataMgr] key=\(key) value=\(value)")
        switch key {
        case OBDKey.rpm:
            rpm = Int(value) ?? rpm
        case OBDKey.speed:
            speed = Double(value) ?? speed
        case OBDKey.fuelLevel:
            fuelLevel = Double(value) ?? fuelLevel
            distanceToEmpty = calculateDistanceToEmpty(fuelLevel: fuelLevel)
            receivedKeys.insert(OBDKey.distanceToEmpty)
        case OBDKey.oilTemp:
            oilTemp = Double(value) ?? oilTemp
        case OBDKey.coolantTemp:
            coolantTemp = Double(value) ?? coolantTemp
        case OBDKey.batteryVoltage:
            batteryVoltage = Double(value) ?? batteryVoltage
        case OBDKey.vin:
            vin = value
        case OBDKey.errorCodes:
            errorCodes = value.isEmpty ? "None" : value
        default:
            break
        }
        receivedKeys.insert(key)
    }

    // =========================================================================
    // MARK: - Logging  (one row per key every 10 s; rows older than 1 h purged)
    // =========================================================================
    func startLoggingIfNeeded() {
        guard isLoggingEnabled, (isConnected || isSimulatorOn) else {
            stopLogging()   // ensure timer is killed when conditions are no longer met
            return
        }
        stopLogging()
        loggingTimer = Timer.scheduledTimer(withTimeInterval: VehicleConstants.loggingInterval, repeats: true) { [weak self] _ in
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
        df.dateFormat = DateFormat.date
        let dateStr = df.string(from: now)
        df.dateFormat = DateFormat.time
        let timeStr = df.string(from: now)

        let deviceName = isSimulatorOn ? "Simulator" : connectedDeviceName

        // One LogEntry row per telemetry key (denormalized schema per spec).
        // Each tuple: (key, value, pid) where pid is the OBD-II command that produced the reading.
        let pairs: [(String, String, String)] = [
            (OBDKey.fuelLevel,       String(format: "%.1f", fuelLevel),       OBDLogPID.fuelLevel),
            (OBDKey.speed,           String(format: "%.1f", speed),           OBDLogPID.speed),
            (OBDKey.rpm,             String(rpm),                             OBDLogPID.rpm),
            (OBDKey.oilTemp,         String(format: "%.1f", oilTemp),         OBDLogPID.oilTemp),
            (OBDKey.coolantTemp,     String(format: "%.1f", coolantTemp),      OBDLogPID.coolantTemp),
            (OBDKey.batteryVoltage,  String(format: "%.2f", batteryVoltage),   OBDLogPID.batteryVoltage),
            (OBDKey.distanceToEmpty, String(format: "%.1f", distanceToEmpty),  OBDLogPID.distanceToEmpty),
            (OBDKey.vin,             vin,                                      OBDLogPID.vin),
            (OBDKey.errorCodes,      errorCodes,                               OBDLogPID.errorCodes),
        ]

        for (key, value, pid) in pairs {
            // In simulator mode all values are always valid.
            // In live mode, skip any key we've never received from the vehicle —
            // it means the vehicle doesn't support that PID and the value is a default.
            guard isSimulatorOn || receivedKeys.contains(key) else { continue }
            ctx.insert(LogEntry(
                date:          dateStr,
                time:          timeStr,
                key:           key,
                value:         value,
                bleDeviceName: deviceName,
                vinNumber:     vin,
                pid:           pid
            ))
        }

        pruneOldEntries(ctx: ctx)
        try? ctx.save()
    }

    /// Deletes LogEntry rows whose timestamp is older than 1 hour.
    private func pruneOldEntries(ctx: ModelContext) {
        let cutoff   = Date().addingTimeInterval(-VehicleConstants.logRetentionSeconds)
        let combined = DateFormatter()
        combined.dateFormat = DateFormat.dateTime

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

    /// Approximate distance to empty based on the selected vehicle profile.
    private func calculateDistanceToEmpty(fuelLevel: Double) -> Double {
        return (fuelLevel / 100.0) * selectedProfile.tankGallons * selectedProfile.avgMPG
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
        let speedFactor      = speed > 0 ? (1.0 + (speed / VehicleConstants.tteSpeedRefMPH) * 0.6) : 0.5
        let rpmFactor        = 1.0 + (Double(rpm) / VehicleConstants.tteRPMRef) * 0.3
        let adjustedGPH      = VehicleConstants.tteBaseGPH * speedFactor * rpmFactor
        let remainingGallons = (fuelLevel / 100.0) * selectedProfile.tankGallons

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
        receivedKeys    = []   // clear so a new connection starts with a clean slate
    }

    private func handleLoggingChange() {
        if isLoggingEnabled {
            startLoggingIfNeeded()
        } else {
            stopLogging()
        }
    }
}
