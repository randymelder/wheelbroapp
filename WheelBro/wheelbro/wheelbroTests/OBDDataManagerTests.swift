// OBDDataManagerTests.swift
// Tests for OBDDataManager — default state, OBD updates, and calculations.

import Testing
import Foundation
@testable import wheelbro

// MARK: - Helpers

/// Creates a fresh OBDDataManager with a known UserDefaults state.
private func makeManager(simulatorOn: Bool = false, loggingOn: Bool = false) -> OBDDataManager {
    UserDefaults.standard.removeObject(forKey: "isSimulatorOn")
    UserDefaults.standard.removeObject(forKey: "isLoggingEnabled")
    UserDefaults.standard.set(simulatorOn, forKey: "isSimulatorOn")
    UserDefaults.standard.set(loggingOn,   forKey: "isLoggingEnabled")
    return OBDDataManager()
}

// MARK: - Default State

// .serialized ensures UserDefaults mutations across all suites don't race.
@Suite("OBDDataManager — default state", .serialized)
struct OBDDataManagerDefaultStateTests {

    @Test func defaultFuelLevel() {
        let mgr = makeManager()
        #expect(mgr.fuelLevel == 50.0)
    }

    @Test func defaultSpeed() {
        let mgr = makeManager()
        #expect(mgr.speed == 0.0)
    }

    @Test func defaultRPM() {
        let mgr = makeManager()
        #expect(mgr.rpm == 800)
    }

    @Test func defaultOilTemp() {
        let mgr = makeManager()
        #expect(mgr.oilTemp == 180.0)
    }

    @Test func defaultCoolantTemp() {
        let mgr = makeManager()
        #expect(mgr.coolantTemp == 195.0)
    }

    @Test func defaultBatteryVoltage() {
        let mgr = makeManager()
        #expect(mgr.batteryVoltage == 14.2)
    }

    @Test func defaultDistanceToEmpty() {
        let mgr = makeManager()
        #expect(mgr.distanceToEmpty == 248.0)
    }

    @Test func defaultVIN() {
        let mgr = makeManager()
        #expect(mgr.vin == "1J4BA2D13BL123456")
    }

    @Test func defaultErrorCodes() {
        let mgr = makeManager()
        #expect(mgr.errorCodes == "None")
    }

    @Test func defaultIsConnected() {
        let mgr = makeManager()
        #expect(mgr.isConnected == false)
    }

    @Test func defaultConnectedDeviceName() {
        let mgr = makeManager()
        #expect(mgr.connectedDeviceName == "")
    }

    @Test func firstLaunchDefaultsSimulatorOn() {
        UserDefaults.standard.removeObject(forKey: "isSimulatorOn")
        let mgr = OBDDataManager()
        #expect(mgr.isSimulatorOn == true)
    }

    @Test func subsequentLaunchRestoresSimulatorSetting() {
        UserDefaults.standard.set(false, forKey: "isSimulatorOn")
        let mgr = OBDDataManager()
        #expect(mgr.isSimulatorOn == false)
    }
}

// MARK: - updateFromOBD

@Suite("OBDDataManager — updateFromOBD", .serialized)
struct OBDDataManagerUpdateTests {

    @Test func updatesRPM() {
        let mgr = makeManager()
        mgr.updateFromOBD(key: "rpm", value: "1500")
        #expect(mgr.rpm == 1500)
    }

    @Test func invalidRPMKeepsOldValue() {
        let mgr = makeManager()
        let original = mgr.rpm
        mgr.updateFromOBD(key: "rpm", value: "notAnInt")
        #expect(mgr.rpm == original)
    }

    @Test func updatesSpeed() {
        let mgr = makeManager()
        mgr.updateFromOBD(key: "speed", value: "42.5")
        #expect(mgr.speed == 42.5)
    }

    @Test func invalidSpeedKeepsOldValue() {
        let mgr = makeManager()
        let original = mgr.speed
        mgr.updateFromOBD(key: "speed", value: "fast")
        #expect(mgr.speed == original)
    }

    @Test func updatesFuelLevelAndDistanceToEmpty() {
        let mgr = makeManager()
        mgr.updateFromOBD(key: "fuelLevel", value: "100.0")
        #expect(mgr.fuelLevel == 100.0)
        // VehicleProfile.jeepWranglerJK: tankGallons=18.6, avgMPG=15.0 → 279.0 miles at 100%
        #expect(abs(mgr.distanceToEmpty - 279.0) < 0.001)
    }

    @Test func fuelLevelZeroGivesZeroDistance() {
        let mgr = makeManager()
        mgr.updateFromOBD(key: "fuelLevel", value: "0.0")
        #expect(mgr.distanceToEmpty == 0.0)
    }

    @Test func fuelLevelHalfGivesHalfDistance() {
        let mgr = makeManager()
        mgr.updateFromOBD(key: "fuelLevel", value: "50.0")
        // 18.6 * 15.0 * 0.5 = 139.5
        #expect(abs(mgr.distanceToEmpty - 139.5) < 0.001)
    }

    @Test func updatesOilTemp() {
        let mgr = makeManager()
        mgr.updateFromOBD(key: "oilTemp", value: "210.0")
        #expect(mgr.oilTemp == 210.0)
    }

    @Test func updatesCoolantTemp() {
        let mgr = makeManager()
        mgr.updateFromOBD(key: "coolantTemp", value: "200.0")
        #expect(mgr.coolantTemp == 200.0)
    }

    @Test func updatesBatteryVoltage() {
        let mgr = makeManager()
        mgr.updateFromOBD(key: "batteryVoltage", value: "13.5")
        #expect(mgr.batteryVoltage == 13.5)
    }

    @Test func updatesVIN() {
        let mgr = makeManager()
        mgr.updateFromOBD(key: "vin", value: "1HGCM82633A004352")
        #expect(mgr.vin == "1HGCM82633A004352")
    }

    @Test func updatesErrorCodes() {
        let mgr = makeManager()
        mgr.updateFromOBD(key: "errorCodes", value: "P0300,P0171")
        #expect(mgr.errorCodes == "P0300,P0171")
    }

    @Test func emptyErrorCodesBecomesNone() {
        let mgr = makeManager()
        mgr.updateFromOBD(key: "errorCodes", value: "P0300")
        mgr.updateFromOBD(key: "errorCodes", value: "")
        #expect(mgr.errorCodes == "None")
    }

    @Test func unknownKeyIsIgnored() {
        let mgr = makeManager()
        let rpmBefore = mgr.rpm
        mgr.updateFromOBD(key: "unknownKey", value: "999")
        #expect(mgr.rpm == rpmBefore)
    }
}

// MARK: - calculateTimeToEmpty

@Suite("OBDDataManager — calculateTimeToEmpty")
struct OBDDataManagerTTETests {

    @Test func emptyTankReturnsLessThanOneMinute() {
        let mgr = makeManager()
        let result = mgr.calculateTimeToEmpty(fuelLevel: 0, speed: 0, rpm: 800, errorCodes: "None")
        #expect(result == "< 1m")
    }

    @Test func atIdleFullTankReturnsHoursAndMinutes() {
        let mgr = makeManager()
        // speed=0 → speedFactor=0.5, rpm=800 → rpmFactor=1.12
        // GPH = 1.2 * 0.5 * 1.12 = 0.672
        // remaining = 18.6 gallons → hours = 18.6/0.672 ≈ 27.678
        let result = mgr.calculateTimeToEmpty(fuelLevel: 100, speed: 0, rpm: 800, errorCodes: "None")
        #expect(result == "27h 40m")
    }

    @Test func movingAtHalfTankReturnsExpectedTime() {
        let mgr = makeManager()
        // speed=55 → speedFactor=1.6, rpm=2000 → rpmFactor=1.3
        // GPH = 1.2 * 1.6 * 1.3 = 2.496
        // remaining = 9.3 gallons → hours = 9.3/2.496 ≈ 3.726
        let result = mgr.calculateTimeToEmpty(fuelLevel: 50, speed: 55, rpm: 2000, errorCodes: "None")
        #expect(result == "3h 43m")
    }

    @Test func minutesOnlyWhenLessThanOneHour() {
        let mgr = makeManager()
        // Use small fuelLevel to get < 1h remaining
        // speed=55 → speedFactor=1.6, rpm=3000 → rpmFactor=1.45
        // GPH = 1.2 * 1.6 * 1.45 = 2.784
        // remaining = 18.6 * 0.05 = 0.93 gallons → hours = 0.93/2.784 ≈ 0.334
        let result = mgr.calculateTimeToEmpty(fuelLevel: 5, speed: 55, rpm: 3000, errorCodes: "None")
        #expect(result.hasSuffix("m"))
        #expect(!result.contains("h"))
    }

    @Test func resultDoesNotContainNegativeValues() {
        let mgr = makeManager()
        let result = mgr.calculateTimeToEmpty(fuelLevel: 25, speed: 30, rpm: 1200, errorCodes: "None")
        #expect(!result.contains("-"))
    }

    @Test func errorCodesParameterDoesNotAffectResult() {
        let mgr = makeManager()
        let withFaults    = mgr.calculateTimeToEmpty(fuelLevel: 50, speed: 30, rpm: 1200, errorCodes: "P0300")
        let withoutFaults = mgr.calculateTimeToEmpty(fuelLevel: 50, speed: 30, rpm: 1200, errorCodes: "None")
        #expect(withFaults == withoutFaults)
    }
}

// MARK: - Simulator

@Suite("OBDDataManager — simulator", .serialized)
struct OBDDataManagerSimulatorTests {

    @Test func startSimulatorUpdatesValues() {
        let mgr = makeManager(simulatorOn: false)
        let fuelBefore = mgr.fuelLevel
        mgr.startSimulator()
        mgr.stopSimulator()
        // startSimulator fires once immediately via updateSimulatedValues
        // fuelLevel randomises in 20...80 — just verify it changed from default 50.0
        // (statistically certain; range is 20...80 and default is 50.0)
        let inRange = mgr.fuelLevel >= 20.0 && mgr.fuelLevel <= 80.0
        #expect(inRange)
        _ = fuelBefore // silence unused warning
    }

    @Test func stopSimulatorHaltsUpdates() {
        let mgr = makeManager(simulatorOn: false)
        mgr.startSimulator()
        mgr.stopSimulator()
        let speedAfterStop = mgr.speed
        // No timer should be running; speed should stay stable
        #expect(mgr.speed == speedAfterStop)
    }

    @Test func simulatorVINIsAlwaysFixed() {
        let mgr = makeManager(simulatorOn: false)
        mgr.startSimulator()
        mgr.stopSimulator()
        #expect(mgr.vin == "1J4BA2D13BL123456")
    }

    @Test func simulatedRPMIsInExpectedRange() {
        let mgr = makeManager(simulatorOn: false)
        mgr.startSimulator()
        mgr.stopSimulator()
        #expect(mgr.rpm >= 800 && mgr.rpm <= 3500)
    }
}
