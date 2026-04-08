// SettingsView.swift
// Tab 1 — vehicle, simulator, BLE scanning, test OBD data, and logging controls.
// This is the default landing tab on first launch.

import SwiftUI

struct SettingsView: View {

    @Environment(OBDDataManager.self) private var obdManager
    @Environment(BluetoothManager.self) private var bleManager

    // Supported vehicles — only one option per spec
    private let vehicles = ["Jeep Wrangler JK (2011-2018)"]
    @AppStorage("selectedVehicle") private var selectedVehicle = "Jeep Wrangler JK (2011-2018)"

    var body: some View {
        // @Bindable lets us create two-way bindings to @Observable properties
        // without needing @StateObject / @ObservedObject.
        @Bindable var obdManager  = obdManager
        @Bindable var bleManager  = bleManager

        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                List {

                    // ── Section 1: Vehicle ───────────────────────────────────
                    Section {
                        Picker("Vehicle", selection: $selectedVehicle) {
                            ForEach(vehicles, id: \.self) { v in
                                Text(v).tag(v)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Color.wheelBroYellow)
                        .foregroundStyle(.white)
                    } header: {
                        sectionHeader("Vehicle")
                    }
                    .listRowBackground(Color.cardBackground)

                    // ── Section 2: Simulator ─────────────────────────────────
                    Section {
                        Toggle(isOn: $obdManager.isSimulatorOn) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Simulator Mode")
                                        .foregroundStyle(.white)
                                    Text("Generates realistic fake OBD data every 5 s")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "play.display")
                                    .foregroundStyle(Color.wheelBroYellow)
                            }
                        }
                        .tint(Color.wheelBroYellow)
                    } header: {
                        sectionHeader("Simulator")
                    }
                    .listRowBackground(Color.cardBackground)

                    // ── Section 3: BLE Devices ───────────────────────────────
                    Section {

                        // Scan button
                        Button(action: { bleManager.startScanning() }) {
                            HStack {
                                Image(systemName: bleManager.isScanning ? "antenna.radiowaves.left.and.right" : "magnifyingglass")
                                    .foregroundStyle(Color.wheelBroYellow)
                                    .symbolEffect(.pulse, isActive: bleManager.isScanning)
                                Text(bleManager.isScanning ? "Scanning…" : "Scan for Devices")
                                    .foregroundStyle(.white)
                                Spacer()
                                if bleManager.isScanning {
                                    ProgressView()
                                        .tint(Color.wheelBroYellow)
                                }
                            }
                        }
                        .disabled(bleManager.isScanning)

                        // Discovered device list
                        if bleManager.discoveredPeripherals.isEmpty && !bleManager.isScanning {
                            Text("No devices found — tap Scan to search")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(bleManager.discoveredPeripherals) { item in
                                Button(action: {
                                    bleManager.connect(to: item.peripheral)
                                }) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "cable.connector")
                                            .foregroundStyle(Color.wheelBroYellow)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.name)
                                                .foregroundStyle(.white)
                                                .fontWeight(.medium)
                                            Text("RSSI: \(item.rssi) dBm  ·  \(item.id.uuidString.prefix(8).uppercased())")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        if bleManager.connectedPeripheral?.identifier == item.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                        }
                                    }
                                }
                            }
                        }

                        // "Test OBD Data" button — only visible when connected
                        if bleManager.isConnected {
                            Button(action: { bleManager.testOBDData() }) {
                                Label("Test OBD Data", systemImage: "stethoscope")
                                    .foregroundStyle(Color.wheelBroYellow)
                                    .fontWeight(.semibold)
                            }
                        }

                        // Connection status text
                        Label {
                            Text(bleManager.connectionStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } icon: {
                            Circle()
                                .fill(bleManager.isConnected ? Color.green : Color.gray)
                                .frame(width: 8, height: 8)
                        }

                    } header: {
                        sectionHeader("BLE Devices")
                    }
                    .listRowBackground(Color.cardBackground)
                    // "Test OBD Data" results alert
                    .alert("OBD-II Test Results", isPresented: $bleManager.showTestOBDAlert) {
                        Button("OK") { bleManager.showTestOBDAlert = false }
                    } message: {
                        Text(bleManager.testOBDResult)
                    }

                    // ── Section 4: Logging ───────────────────────────────────
                    Section {
                        Toggle(isOn: $obdManager.isLoggingEnabled) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Enable Data Logging")
                                        .foregroundStyle(.white)
                                    Text("Logs one row per key every 10 s; purges data older than 1 h")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "externaldrive.fill")
                                    .foregroundStyle(Color.wheelBroYellow)
                            }
                        }
                        .tint(Color.wheelBroYellow)
                    } header: {
                        sectionHeader("Logging")
                    }
                    .listRowBackground(Color.cardBackground)

                    // ── Section 5: Connection Control ────────────────────────
                    Section {
                        Button(action: {
                            if bleManager.isConnected {
                                bleManager.disconnect()
                            }
                        }) {
                            HStack {
                                Image(systemName: bleManager.isConnected ? "xmark.circle.fill" : "cable.connector.slash")
                                    .foregroundStyle(bleManager.isConnected ? Color.wheelBroRed : .secondary)
                                Text(bleManager.isConnected ? "Disconnect" : "Not Connected")
                                    .foregroundStyle(bleManager.isConnected ? Color.wheelBroRed : .secondary)
                                    .fontWeight(bleManager.isConnected ? .semibold : .regular)
                            }
                        }
                        .disabled(!bleManager.isConnected)

                        if bleManager.isConnected {
                            Label {
                                Text("Connected to: \(bleManager.connectedPeripheral?.name ?? "Unknown")")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } icon: {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    } header: {
                        sectionHeader("Connection")
                    }
                    .listRowBackground(Color.cardBackground)
                }
                .scrollContentBackground(.hidden)
                .background(Color.black)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    // MARK: - Helpers
    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(Color.wheelBroYellow)
            .tracking(1.5)
    }
}

// MARK: - Preview
#Preview {
    SettingsView()
        .environment(OBDDataManager())
        .environment(BluetoothManager())
}
