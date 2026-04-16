// SettingsView.swift
// Tab 1 — vehicle, simulator, BLE scanning, test OBD data, and logging controls.
// This is the default landing tab on first launch.

import SwiftUI
import CoreBluetooth

struct SettingsView: View {

    @Environment(OBDDataManager.self) private var obdManager
    @Environment(BluetoothManager.self) private var bleManager

    @Binding var selectedTab: Int
    
    var body: some View {
        // @Bindable lets us create two-way bindings to @Observable properties
        // without needing @StateObject / @ObservedObject.
        @Bindable var obdManager  = obdManager
        @Bindable var bleManager  = bleManager

        NavigationStack {
            List {

                    // ── Section 1: Vehicle ───────────────────────────────────
                    Section {
                        Picker("Vehicle", selection: $obdManager.selectedProfile) {
                            ForEach(VehicleProfile.all) { profile in
                                Text(profile.name).tag(profile)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Color.wheelBroYellow)
                        .foregroundStyle(.white)
                    } header: {
                        sectionHeader("Vehicle")
                    }
                    .listRowBackground(Color.cardBackground)

                    

                    // ── Section 3: BLE Devices ───────────────────────────────
                    Section {

                        // Disconnect button — visible only when connected
                        if bleManager.isConnected {
                            Button(action: { bleManager.disconnect() }) {
                                Label("Disconnect from \(bleManager.connectedPeripheral?.name ?? "Device")", systemImage: "xmark.circle.fill")
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
                        }

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

                        // Discovered device list — all BLE devices, sorted by name
                        if bleManager.discoveredPeripherals.isEmpty && !bleManager.isScanning {
                            Text("No compatible devices yet — tap \"Scan for Devices\" to search")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(bleManager.discoveredPeripherals.sorted { $0.name < $1.name }) { item in
                                Button(action: {
                                    bleManager.connect(to: item.peripheral)
                                    selectedTab = Tab.tte
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

                    // ── Section 3: Simulator ─────────────────────────────────
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
                }
                .scrollContentBackground(.hidden)
                .background(Color.black)
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
    SettingsView(selectedTab: .constant(Tab.settings))
        .environment(OBDDataManager())
        .environment(BluetoothManager())
}
