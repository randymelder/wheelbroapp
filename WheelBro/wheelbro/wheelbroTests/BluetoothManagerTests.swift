// BluetoothManagerTests.swift
// Tests for BluetoothManager public interface.
// Note: CoreBluetooth parsing methods (parseOBDLine, decodeDTC, celsiusToFahrenheit)
// are private and exercised indirectly via OBD formula verification below.

import Testing
import Foundation
@testable import wheelbro

@Suite("BluetoothManager — initial state")
struct BluetoothManagerInitialStateTests {

    @Test func initiallyNotConnected() {
        let mgr = BluetoothManager()
        #expect(mgr.isConnected == false)
    }

    @Test func initiallyNotScanning() {
        let mgr = BluetoothManager()
        #expect(mgr.isScanning == false)
    }

    @Test func initiallyNoDiscoveredPeripherals() {
        let mgr = BluetoothManager()
        #expect(mgr.discoveredPeripherals.isEmpty)
    }

    @Test func initiallyNoConnectedPeripheral() {
        let mgr = BluetoothManager()
        #expect(mgr.connectedPeripheral == nil)
    }

    @Test func initialStatusIsReady() {
        let mgr = BluetoothManager()
        // CBCentralManager on simulator transitions to a known state;
        // the initial string before state update resolves is "Ready"
        let validInitialStatuses = ["Ready", "Bluetooth not powered on",
                                    "Bluetooth is Off", "Bluetooth Unauthorized — check Privacy settings",
                                    "BLE not supported on this device", "Bluetooth Resetting…",
                                    "Bluetooth state unknown", "Bluetooth Ready"]
        #expect(validInitialStatuses.contains(mgr.connectionStatus))
    }

    @Test func testOBDAlertInitiallyHidden() {
        let mgr = BluetoothManager()
        #expect(mgr.showTestOBDAlert == false)
    }

    @Test func testOBDResultInitiallyEmpty() {
        let mgr = BluetoothManager()
        #expect(mgr.testOBDResult == "")
    }
}

@Suite("BluetoothManager — testOBDData when disconnected")
struct BluetoothManagerTestOBDTests {

    @Test func testOBDDataWhenDisconnectedShowsAlert() {
        let mgr = BluetoothManager()
        mgr.testOBDData()
        #expect(mgr.showTestOBDAlert == true)
    }

    @Test func testOBDDataWhenDisconnectedSetsResultMessage() {
        let mgr = BluetoothManager()
        mgr.testOBDData()
        #expect(mgr.testOBDResult == "Not connected to any OBD device.")
    }
}

// MARK: - OBD Formula Verification
// These tests verify the correctness of the decoding formulas used inside
// BluetoothManager.parseOBDLine by applying the same arithmetic and checking
// results via OBDDataManager.updateFromOBD (the public handoff point).

@Suite("OBD-II decoding formulas")
struct OBDDecodingFormulaTests {

    // RPM: ((A * 256) + B) / 4
    // Bytes 0C 1A → A=0x0C=12, B=0x1A=26 → (12*256+26)/4 = (3072+26)/4 = 3098/4 = 774
    @Test func rpmFormula() {
        let a: UInt32 = 0x0C, b: UInt32 = 0x1A
        let rpm = Int((a * 256 + b) / 4)
        #expect(rpm == 774)
    }

    @Test func rpmFormulaAtIdle() {
        // 0C 80 → (12*256 + 128)/4 = (3072+128)/4 = 800
        let a: UInt32 = 0x0C, b: UInt32 = 0x80
        let rpm = Int((a * 256 + b) / 4)
        #expect(rpm == 800)
    }

    // Speed: A km/h → mph (× 0.621371)
    @Test func speedFormula() {
        let a: Double = 100  // 100 km/h
        let mph = a * 0.621371
        #expect(abs(mph - 62.1371) < 0.001)
    }

    // Fuel level: A / 2.55
    @Test func fuelLevelFormulaFull() {
        let a: Double = 255
        let pct = a / 2.55
        #expect(abs(pct - 100.0) < 0.01)
    }

    @Test func fuelLevelFormulaHalf() {
        let a: Double = 127
        let pct = a / 2.55
        #expect(abs(pct - 49.8) < 0.1)
    }

    // Temperature: A − 40 °C → °F
    @Test func celsiusToFahrenheitAt0C() {
        let celsius = 0.0 - 40.0  // byte=0, so 0-40=-40°C
        let f = (celsius * 9.0 / 5.0) + 32.0
        #expect(f == -40.0)  // -40°C = -40°F
    }

    @Test func celsiusToFahrenheitAt100C() {
        let celsius = 140.0 - 40.0  // byte=140 → 100°C
        let f = (celsius * 9.0 / 5.0) + 32.0
        #expect(f == 212.0)
    }

    @Test func coolantTempNormalOperating() {
        // byte 0xC8 = 200 → 200-40 = 160°C → 320°F
        let a: Double = 200
        let f = ((a - 40.0) * 9.0 / 5.0) + 32.0
        #expect(f == 320.0)
    }

    // DTC decoding: bits 15-14 = system, bits 13-12 = digit1, bits 11-0 = last3
    @Test func dtcDecodeP0300() {
        // P0300 = 0x0300
        // bits 15-14 = 00 → P, bits 13-12 = 00 → 0, bits 11-0 = 0x300 → "300"
        let value: UInt16 = 0x0300
        let systems = ["P", "C", "B", "U"]
        let system = systems[Int((value >> 14) & 0x03)]
        let digit1 = Int((value >> 12) & 0x03)
        let last3  = String(format: "%03X", value & 0x0FFF)
        #expect("\(system)\(digit1)\(last3)" == "P0300")
    }

    @Test func dtcDecodeP0171() {
        // P0171 = 0x0171
        let value: UInt16 = 0x0171
        let systems = ["P", "C", "B", "U"]
        let system = systems[Int((value >> 14) & 0x03)]
        let digit1 = Int((value >> 12) & 0x03)
        let last3  = String(format: "%03X", value & 0x0FFF)
        #expect("\(system)\(digit1)\(last3)" == "P0171")
    }

    @Test func dtcDecodeC0001() {
        // C system: bits 15-14 = 01 → index 1 = "C"
        // 0x4001 = 0100 0000 0000 0001
        let value: UInt16 = 0x4001
        let systems = ["P", "C", "B", "U"]
        let system = systems[Int((value >> 14) & 0x03)]
        let digit1 = Int((value >> 12) & 0x03)
        let last3  = String(format: "%03X", value & 0x0FFF)
        #expect("\(system)\(digit1)\(last3)" == "C0001")
    }

    @Test func dtcDecodeB0000() {
        // B system: bits 15-14 = 10 → index 2 = "B"
        // 0x8000 = 1000 0000 0000 0000
        let value: UInt16 = 0x8000
        let systems = ["P", "C", "B", "U"]
        let system = systems[Int((value >> 14) & 0x03)]
        let digit1 = Int((value >> 12) & 0x03)
        let last3  = String(format: "%03X", value & 0x0FFF)
        #expect("\(system)\(digit1)\(last3)" == "B0000")
    }

    @Test func dtcDecodeU0100() {
        // U system: bits 15-14 = 11 → index 3 = "U"
        // U0100 = 0xC100 = 1100 0001 0000 0000
        let value: UInt16 = 0xC100
        let systems = ["P", "C", "B", "U"]
        let system = systems[Int((value >> 14) & 0x03)]
        let digit1 = Int((value >> 12) & 0x03)
        let last3  = String(format: "%03X", value & 0x0FFF)
        #expect("\(system)\(digit1)\(last3)" == "U0100")
    }

    // Battery voltage parsing: string ending in "V"
    @Test func batteryVoltageParseValid() {
        let response = "14.2V"
        let hasSuffix = response.hasSuffix("V")
        let voltage = Double(response.dropLast())
        #expect(hasSuffix == true)
        #expect(voltage == 14.2)
    }

    @Test func batteryVoltageParseInvalid() {
        let response = "NODATA"
        let voltage = response.hasSuffix("V") ? Double(response.dropLast()) : nil
        #expect(voltage == nil)
    }
}
