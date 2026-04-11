// ContentView.swift
// Root navigation shell — four-tab layout with first-launch routing logic.

import SwiftUI
import SwiftData

struct ContentView: View {

    // MARK: - First-Launch Detection
    // @AppStorage persists "hasLaunchedBefore" in UserDefaults automatically.
    // First launch  → start on Settings tab (index 2) so the user configures their setup.
    // Subsequent    → start on TTE tab (index 0) — the main experience.
    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore = false
    @State private var selectedTab: Int

    // MARK: - Shared Managers (created once, injected via environment)
    @State private var obdDataManager     = OBDDataManager()
    @State private var bluetoothManager   = BluetoothManager()
    @State private var diagnosticsManager = DiagnosticsManager()

    // SwiftData model context — passed into OBDDataManager for log writes
    @Environment(\.modelContext) private var modelContext

    // MARK: - Init
    init() {
        // Read the persistent flag synchronously so we can set the initial tab
        // before the first render. @AppStorage is not available in init, so we
        // read UserDefaults directly here.
        let launched = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        _selectedTab = State(initialValue: launched ? 0 : 2)
    }

    // MARK: - Body
    var body: some View {
        TabView(selection: $selectedTab) {

            // ── Tab 0: TTE (Time to Empty) ──────────────────────────────
            TTEView()
                .tabItem {
                    Label("TTE", systemImage: "gauge.with.needle.fill")
                }
                .tag(0)

            // ── Tab 1: Data ──────────────────────────────────────────────
            DataView()
                .tabItem {
                    Label("Data", systemImage: "chart.bar.doc.horizontal.fill")
                }
                .tag(1)

            // ── Tab 2: Settings ──────────────────────────────────────────
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(2)

            // ── Tab 3: About ─────────────────────────────────────────────
            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle.fill")
                }
                .tag(3)
        }
        // Yellow accent color matches WheelBro brand
        .tint(Color.wheelBroYellow)
        // Inject both managers into the SwiftUI environment so all child views
        // can access them without explicit prop-drilling.
        .environment(obdDataManager)
        .environment(bluetoothManager)
        .environment(diagnosticsManager)
        .task {
            // Wire BLE → OBD bridge and start simulator / logging
            bluetoothManager.obdDataManager = obdDataManager
            bluetoothManager.diagnostics    = diagnosticsManager
            diagnosticsManager.log(.info, .system, "WheelBro started")
            obdDataManager.setup(modelContext: modelContext)

            // Mark first launch complete so subsequent launches open TTE
            if !hasLaunchedBefore {
                hasLaunchedBefore = true
            }
        }
    }
}

// MARK: - Preview
#Preview {
    ContentView()
        .modelContainer(for: LogEntry.self, inMemory: true)
}
