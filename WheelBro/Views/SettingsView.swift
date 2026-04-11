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

    /// Filtered peripheral list evaluated as a view property so that
    /// SwiftUI's @Observable tracking registers the dependency correctly.
    /// A let binding inside a @ViewBuilder closure can miss re-evaluations.
    private var supportedPeripherals: [DiscoveredPeripheral] {
        bleManager.discoveredPeripherals.filter(\.isVgateCompatible)
    }

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

                        // Discovered device list — only Vgate-compatible devices shown
                        if supportedPeripherals.isEmpty && !bleManager.isScanning {
                            Text(bleManager.discoveredPeripherals.isEmpty
                                 ? "No devices found — tap Scan to search"
                                 : "No compatible Vgate devices found — unsupported adapters are hidden")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(supportedPeripherals) { item in
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

                    // ── Section 5: Tools ─────────────────────────────────────
                    Section {
                        NavigationLink(destination: DiscoveryView()) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("PID Discovery")
                                        .foregroundStyle(.white)
                                    Text("Query which OBD-II PIDs your vehicle supports")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "list.bullet.rectangle.portrait")
                                    .foregroundStyle(Color.wheelBroYellow)
                            }
                        }

                        NavigationLink(destination: DiagnosticsView()) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Diagnostics")
                                        .foregroundStyle(.white)
                                    Text("Live BLE and OBD event log — export to diagnose issues")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "stethoscope")
                                    .foregroundStyle(Color.wheelBroYellow)
                            }
                        }
                    } header: {
                        sectionHeader("Tools")
                    }
                    .listRowBackground(Color.cardBackground)

                    // ── Section 6: Connection Control (only shown when connected) ──
                    if bleManager.isConnected {
                        Section {
                            // Connected device name
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bleManager.connectedPeripheral?.name ?? "Unknown Device")
                                        .fontWeight(.medium)
                                        .foregroundStyle(.white)
                                    Text(bleManager.connectedPeripheral.map {
                                        String($0.identifier.uuidString.prefix(8)).uppercased()
                                    } ?? "")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                            .listRowBackground(Color.cardBackground)

                            // Full-width red Disconnect button
                            Button(action: { bleManager.disconnect() }) {
                                Label("Disconnect", systemImage: "xmark.circle.fill")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(Color.wheelBroRed)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        } header: {
                            sectionHeader("Connection")
                        }
                    }
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
