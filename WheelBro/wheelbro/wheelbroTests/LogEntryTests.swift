// LogEntryTests.swift
// Tests for the LogEntry SwiftData model.

import Testing
import Foundation
@testable import wheelbro

@Suite("LogEntry — initialisation")
struct LogEntryInitTests {

    @Test func allFieldsSetCorrectly() {
        let id  = UUID()
        let entry = LogEntry(
            id:            id,
            date:          "2026-04-08",
            time:          "14:32:00",
            key:           "fuelLevel",
            value:         "48.3",
            bleDeviceName: "Vgate iCar Pro",
            vinNumber:     "1J4BA2D13BL123456"
        )
        #expect(entry.id           == id)
        #expect(entry.date         == "2026-04-08")
        #expect(entry.time         == "14:32:00")
        #expect(entry.key          == "fuelLevel")
        #expect(entry.value        == "48.3")
        #expect(entry.bleDeviceName == "Vgate iCar Pro")
        #expect(entry.vinNumber    == "1J4BA2D13BL123456")
    }

    @Test func defaultIDIsGenerated() {
        let a = LogEntry(date: "2026-04-08", time: "00:00:00",
                         key: "rpm", value: "800",
                         bleDeviceName: "Simulator", vinNumber: "1J4BA2D13BL123456")
        let b = LogEntry(date: "2026-04-08", time: "00:00:00",
                         key: "rpm", value: "800",
                         bleDeviceName: "Simulator", vinNumber: "1J4BA2D13BL123456")
        // Each instance gets its own UUID by default
        #expect(a.id != b.id)
    }

    @Test func customIDIsPreserved() {
        let id = UUID(uuidString: "12345678-1234-1234-1234-123456789012")!
        let entry = LogEntry(id: id, date: "2026-04-08", time: "00:00:00",
                             key: "speed", value: "42.0",
                             bleDeviceName: "Simulator", vinNumber: "")
        #expect(entry.id == id)
    }

    @Test func emptyVINIsAllowed() {
        let entry = LogEntry(date: "2026-04-08", time: "00:00:00",
                             key: "vin", value: "",
                             bleDeviceName: "Simulator", vinNumber: "")
        #expect(entry.vinNumber == "")
        #expect(entry.value     == "")
    }

    @Test func simulatorDeviceName() {
        let entry = LogEntry(date: "2026-04-08", time: "10:00:00",
                             key: "batteryVoltage", value: "13.5",
                             bleDeviceName: "Simulator", vinNumber: "1J4BA2D13BL123456")
        #expect(entry.bleDeviceName == "Simulator")
    }

    @Test func allTelemetryKeysAreAccepted() {
        let keys = ["fuelLevel", "speed", "rpm", "oilTemp", "coolantTemp",
                    "batteryVoltage", "distanceToEmpty", "vin", "errorCodes"]
        for key in keys {
            let entry = LogEntry(date: "2026-04-08", time: "00:00:00",
                                 key: key, value: "0",
                                 bleDeviceName: "Simulator", vinNumber: "")
            #expect(entry.key == key)
        }
    }
}

@Suite("LogEntry — value formats")
struct LogEntryValueFormatTests {

    @Test func fuelLevelFormat() {
        let value = String(format: "%.1f", 48.3)
        let entry = LogEntry(date: "2026-04-08", time: "00:00:00",
                             key: "fuelLevel", value: value,
                             bleDeviceName: "Simulator", vinNumber: "")
        #expect(entry.value == "48.3")
    }

    @Test func rpmFormat() {
        let value = String(800)
        let entry = LogEntry(date: "2026-04-08", time: "00:00:00",
                             key: "rpm", value: value,
                             bleDeviceName: "Simulator", vinNumber: "")
        #expect(entry.value == "800")
    }

    @Test func batteryVoltageFormat() {
        let value = String(format: "%.2f", 13.57)
        let entry = LogEntry(date: "2026-04-08", time: "00:00:00",
                             key: "batteryVoltage", value: value,
                             bleDeviceName: "Simulator", vinNumber: "")
        #expect(entry.value == "13.57")
    }

    @Test func errorCodesMultiple() {
        let entry = LogEntry(date: "2026-04-08", time: "00:00:00",
                             key: "errorCodes", value: "P0300,P0171",
                             bleDeviceName: "Simulator", vinNumber: "")
        let codes = entry.value.components(separatedBy: ",")
        #expect(codes.count == 2)
        #expect(codes.contains("P0300"))
        #expect(codes.contains("P0171"))
    }
}
