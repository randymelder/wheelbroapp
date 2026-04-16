// LogEntry.swift
// SwiftData persistent model for OBD-II telemetry logging.
// Schema is denormalized: one row per key per logging interval.

import Foundation
import SwiftData

@Model
final class LogEntry {

    // MARK: - Required Columns (per spec)

    /// Unique row identifier — auto-generated on init.
    var id: UUID

    /// Calendar date of the reading, formatted "YYYY-MM-DD".
    var date: String

    /// Wall-clock time of the reading, formatted "HH:MM:SS".
    var time: String

    /// Telemetry key, e.g. "fuelLevel", "speed", "rpm", "oilTemp",
    /// "coolantTemp", "batteryVoltage", "distanceToEmpty", "vin", "errorCodes".
    var key: String

    /// String-encoded reading value (e.g. "48.3", "1200", "P0300,P0171").
    var value: String

    /// BLE peripheral name at the time of logging ("Simulator" when in sim mode).
    var bleDeviceName: String

    /// VIN string at the time of logging.
    var vinNumber: String

    /// OBD-II PID or AT command that produced this reading.
    /// Examples: "010C" (RPM), "012F" (fuel level), "ATRV" (battery voltage),
    /// "0902" (VIN), "03" (DTCs), "derived" (calculated values like distanceToEmpty).
    var pid: String = ""

    // MARK: - Init
    init(
        id: UUID = UUID(),
        date: String,
        time: String,
        key: String,
        value: String,
        bleDeviceName: String,
        vinNumber: String,
        pid: String = ""
    ) {
        self.id           = id
        self.date         = date
        self.time         = time
        self.key          = key
        self.value        = value
        self.bleDeviceName = bleDeviceName
        self.vinNumber    = vinNumber
        self.pid          = pid
    }
}
