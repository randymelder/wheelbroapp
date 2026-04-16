// DataView.swift
// Tab 1 — log browser and PID discovery export.

import SwiftUI
import SwiftData

struct DataView: View {

    // Fetch ALL log entries, newest first
    @Query(sort: \LogEntry.date, order: .reverse) private var entries: [LogEntry]
    @Environment(OBDDataManager.self) private var obdManager
    @Environment(BluetoothManager.self) private var bleManager
    @Environment(\.modelContext) private var modelContext

    // Discovery share sheet
    @State private var discoveryItems:    [Any] = []
    @State private var showDiscoverySheet: Bool = false
    @State private var isDiscovering:      Bool = false

    // Error / info alerts
    @State private var showNoPIDsAlert: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── Header logo ──────────────────────────────────────────
                Image("wheelbro_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 68)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                // ── Discover PIDs button ─────────────────────────────────
                Button(action: startDiscovery) {
                    HStack(spacing: 10) {
                        if isDiscovering {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.85)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.headline)
                        }
                        Text(isDiscovering ? "Discovering…" : "Vehicle Data")
                            .font(.headline)
                            .fontWeight(.bold)
                    }
                    .foregroundStyle(bleManager.isConnected && !isDiscovering ? .white : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.wheelBroYellow.opacity(
                                bleManager.isConnected && !isDiscovering ? 0.5 : 0.15
                            ), lineWidth: 1)
                    }
                }
                .disabled(!bleManager.isConnected || isDiscovering)
                .padding(.horizontal, 24)

                if entries.isEmpty {
                    Text("No log data yet — enable logging in Settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }

                Divider()
                    .background(Color.wheelBroYellow.opacity(0.2))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)

                // ── Recent log preview (last 30 entries) ─────────────────
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(entries.prefix(30)) { entry in
                            logRow(entry)
                        }
                        if entries.count > 30 {
                            Text("… and \(entries.count - 30) more rows")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                Spacer()

                // ── Copyright ────────────────────────────────────────────
                Text(AppInfo.copyrightFull)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 12)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        // Discovery results share sheet
        .sheet(isPresented: $showDiscoverySheet) {
            if !discoveryItems.isEmpty {
                ActivityView(items: discoveryItems)
            }
        }
        // No PIDs found
        .alert("No PIDs Found", isPresented: $showNoPIDsAlert) {
            Button("OK") { }
        } message: {
            Text("The vehicle didn't respond to any PID range queries. Make sure the ignition is on and the OBD adapter is fully initialised before running discovery.")
        }
        // Detect PID discovery completion
        .onChange(of: bleManager.isDiscoveringPIDs) { _, discovering in
            if !discovering && isDiscovering {
                isDiscovering = false
                exportDiscoveryCSV()
            }
        }
    }

    // =========================================================================
    // MARK: - Sub-Views
    // =========================================================================

    private func logRow(_ entry: LogEntry) -> some View {
        HStack(spacing: 8) {
            Text(entry.key)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.wheelBroYellow)
                .frame(width: 110, alignment: .leading)

            Text(entry.value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(entry.date) \(entry.time)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.cardBackground.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // =========================================================================
    // MARK: - PID Discovery Export
    // =========================================================================

    private func startDiscovery() {
        isDiscovering = true
        bleManager.discoverSupportedPIDs()
    }

    private func exportDiscoveryCSV() {
        guard !bleManager.discoveredPIDs.isEmpty else {
            showNoPIDsAlert = true
            return
        }
        // Human-readable descriptions for SAE J1979 Mode 01 PIDs
        let pidDescriptions: [String: String] = [
            "0101": "Monitor status since DTCs cleared",
            "0102": "Freeze DTC",
            "0103": "Fuel system status",
            "0104": "Calculated engine load",
            "0105": "Engine coolant temperature",
            "0106": "Short term fuel trim (Bank 1)",
            "0107": "Long term fuel trim (Bank 1)",
            "0108": "Short term fuel trim (Bank 2)",
            "0109": "Long term fuel trim (Bank 2)",
            "010A": "Fuel pressure (gauge)",
            "010B": "Intake manifold absolute pressure",
            "010C": "Engine RPM",
            "010D": "Vehicle speed",
            "010E": "Timing advance",
            "010F": "Intake air temperature",
            "0110": "MAF air flow rate",
            "0111": "Throttle position",
            "0112": "Commanded secondary air status",
            "0113": "Oxygen sensors present (2 banks)",
            "0114": "O2 Sensor 1 voltage / STFT (Bank 1)",
            "0115": "O2 Sensor 2 voltage / STFT (Bank 1)",
            "0116": "O2 Sensor 3 voltage / STFT (Bank 1)",
            "0117": "O2 Sensor 4 voltage / STFT (Bank 1)",
            "0118": "O2 Sensor 1 voltage / STFT (Bank 2)",
            "0119": "O2 Sensor 2 voltage / STFT (Bank 2)",
            "011A": "O2 Sensor 3 voltage / STFT (Bank 2)",
            "011B": "O2 Sensor 4 voltage / STFT (Bank 2)",
            "011C": "OBD standards this vehicle conforms to",
            "011D": "Oxygen sensors present (4 banks)",
            "011E": "Auxiliary input status",
            "011F": "Run time since engine start",
            "0121": "Distance traveled with MIL on",
            "0122": "Fuel rail pressure (relative to manifold)",
            "0123": "Fuel rail gauge pressure",
            "0124": "O2 Sensor 1 (wide-range) equivalence / current",
            "0125": "O2 Sensor 2 (wide-range) equivalence / current",
            "012C": "Commanded EGR",
            "012D": "EGR error",
            "012E": "Commanded evaporative purge",
            "012F": "Fuel tank level input",
            "0130": "Warm-ups since codes cleared",
            "0131": "Distance traveled since codes cleared",
            "0132": "Evap system vapor pressure",
            "0133": "Absolute barometric pressure",
            "0134": "O2 Sensor 1 (wide-range) equivalence / current (Bank 1)",
            "013C": "Catalyst temperature (Bank 1, Sensor 1)",
            "013D": "Catalyst temperature (Bank 2, Sensor 1)",
            "013E": "Catalyst temperature (Bank 1, Sensor 2)",
            "013F": "Catalyst temperature (Bank 2, Sensor 2)",
            "0141": "Monitor status this drive cycle",
            "0142": "Control module voltage",
            "0143": "Absolute load value",
            "0144": "Commanded air-fuel equivalence ratio",
            "0145": "Relative throttle position",
            "0146": "Ambient air temperature",
            "0147": "Absolute throttle position B",
            "0148": "Absolute throttle position C",
            "0149": "Accelerator pedal position D",
            "014A": "Accelerator pedal position E",
            "014B": "Accelerator pedal position F",
            "014C": "Commanded throttle actuator",
            "014D": "Time run with MIL on",
            "014E": "Time since trouble codes cleared",
            "0151": "Fuel type",
            "0152": "Ethanol fuel percentage",
            "0159": "Fuel rail absolute pressure",
            "015A": "Relative accelerator pedal position",
            "015B": "Hybrid/EV battery pack remaining life",
            "015C": "Engine oil temperature",
            "015D": "Fuel injection timing",
            "015E": "Engine fuel rate",
            "015F": "Emission requirements to which vehicle is designed",
        ]

        var csv = "pid,description,value\n"
        let sorted = bleManager.discoveredPIDs.sorted()
        for pid in sorted {
            let desc  = pidDescriptions[pid.uppercased()] ?? "Unknown PID"
            let value = bleManager.pidValueResults[pid] ?? ""
            let safeDesc  = desc.replacingOccurrences(of: "\"", with: "\"\"")
            let safeValue = value.replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\"\(pid)\",\"\(safeDesc)\",\"\(safeValue)\"\n"
        }
        if sorted.isEmpty {
            csv += "// No PIDs discovered — ensure vehicle is connected and ignition is on\n"
        }

        let ts = Int(Date().timeIntervalSince1970)
        let provider = NSItemProvider(item: csv as NSString, typeIdentifier: "public.plain-text")
        provider.suggestedName = "wheelbro_discovery_\(ts).txt"
        discoveryItems     = [provider]
        showDiscoverySheet = true
    }
}

// =============================================================================
// MARK: - UIActivityViewController wrapper
// =============================================================================

/// Wraps UIActivityViewController for use in SwiftUI sheets.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview
#Preview {
    DataView()
        .modelContainer(for: LogEntry.self, inMemory: true)
        .environment(OBDDataManager())
        .environment(BluetoothManager())
}
