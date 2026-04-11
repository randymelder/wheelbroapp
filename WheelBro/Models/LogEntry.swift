// LogEntry.swift
// SwiftData persistent model for OBD-II telemetry logging.
// Schema is denormalized: one row per key per logging interval.
//
// SCHEMA HISTORY
//   v1 — id, date, time, key, value, bleDeviceName, vinNumber
//   v2 — added pid, unit, sessionID  (inferred lightweight migration)

import Foundation
import SwiftData

@Model
final class LogEntry {

    // MARK: - Identity

    /// Unique row identifier — auto-generated on init.
    var id: UUID

    // MARK: - Timestamp

    /// Calendar date of the reading, formatted "YYYY-MM-DD".
    var date: String

    /// Wall-clock time of the reading, formatted "HH:MM:SS".
    var time: String

    // MARK: - Session

    /// UUID string that groups all rows from the same connection or simulator session.
    /// Generated fresh each time a BLE device connects or the simulator starts.
    var sessionID: String = ""

    // MARK: - Telemetry

    /// Telemetry key, e.g. "fuelLevel", "speed", "rpm", "oilTemp",
    /// "coolantTemp", "batteryVoltage", "fuelRate", "distanceToEmpty", "vin", "errorCodes".
    var key: String

    /// OBD-II PID or AT command that produced this reading.
    /// Examples: "0C" (RPM), "2F" (fuel level), "5E" (fuel rate), "ATRV" (battery),
    /// "0902" (VIN), "03" (DTCs). Empty for computed values (distanceToEmpty).
    var pid: String = ""

    /// Engineering unit for the value. Examples: "rpm", "mph", "%", "°F", "L/hr", "V", "mi".
    /// Empty for dimensionless fields (vin, errorCodes).
    var unit: String = ""

    /// String-encoded reading value (e.g. "48.3", "1200", "P0300,P0171").
    var value: String

    // MARK: - Device Context

    /// BLE peripheral name at the time of logging ("Simulator" when in sim mode).
    var bleDeviceName: String

    /// VIN string at the time of logging.
    var vinNumber: String

    // MARK: - Init
    init(
        id:            UUID   = UUID(),
        date:          String,
        time:          String,
        sessionID:     String = "",
        key:           String,
        pid:           String = "",
        unit:          String = "",
        value:         String,
        bleDeviceName: String,
        vinNumber:     String
    ) {
        self.id            = id
        self.date          = date
        self.time          = time
        self.sessionID     = sessionID
        self.key           = key
        self.pid           = pid
        self.unit          = unit
        self.value         = value
        self.bleDeviceName = bleDeviceName
        self.vinNumber     = vinNumber
    }
}
