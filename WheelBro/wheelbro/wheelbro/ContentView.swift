// ContentView.swift
// Root navigation shell — five-tab layout with first-launch routing logic.

import SwiftUI
import SwiftData

struct ContentView: View {

    // MARK: - First-Launch Detection
    // @AppStorage persists "hasLaunchedBefore" in UserDefaults automatically.
    // First launch  → start on Settings tab (index 2) so the user configures their setup.
    // Subsequent    → start on TTE tab (index 0) — the main experience.
    @AppStorage(UserDefaultsKey.hasLaunchedBefore) private var hasLaunchedBefore = false
    @State private var selectedTab: Int

    // MARK: - Shared Managers (created once, injected via environment)
    @State private var obdDataManager    = OBDDataManager()
    @State private var bluetoothManager  = BluetoothManager()
    @State private var locationManager   = LocationManager()
    @State private var motionManager     = MotionManager()

    // SwiftData model context — passed into OBDDataManager for log writes
    @Environment(\.modelContext)   private var modelContext
    @Environment(\.scenePhase)     private var scenePhase

    // MARK: - Init
    init() {
        // Read the persistent flag synchronously so we can set the initial tab
        // before the first render. @AppStorage is not available in init, so we
        // read UserDefaults directly here.
        let launched = UserDefaults.standard.bool(forKey: UserDefaultsKey.hasLaunchedBefore)
        _selectedTab = State(initialValue: launched ? Tab.tte : Tab.settings)
    }

    // MARK: - Body
    var body: some View {
        @Bindable var bluetoothManager = bluetoothManager

        TabView(selection: $selectedTab) {

            // ── Tab 0: TTE (Time to Empty) ──────────────────────────────
            TTEView(selectedTab: $selectedTab)
                .tabItem {
                    Label("Dash", systemImage: "gauge.with.dots.needle.bottom.50percent")
                }
                .tag(Tab.tte)

            // ── Tab 5: Map ───────────────────────────────────────────────
            MapView(selectedTab: $selectedTab)
                .tabItem {
                    Label("Map", systemImage: "map.fill")
                }
                .tag(Tab.map)

            // ── Tab 2: Bro Cam ───────────────────────────────────────────
            BroCamView(selectedTab: $selectedTab)
                .tabItem {
                    Label("Bro Cam", systemImage: "person.crop.square.badge.camera")
                }
                .tag(Tab.broCam)

            // ── Tab 3: Settings ──────────────────────────────────────────
            SettingsView(selectedTab: $selectedTab)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.2")
                }
                .tag(Tab.settings)

            // ── Tab 4: About ─────────────────────────────────────────────
            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle.fill")
                }
                .tag(Tab.about)

        }
        // Yellow accent color matches WheelBro brand
        .tint(Color.wheelBroYellow)
        // Auto-detect failure alert — shown when ATSP0 times out without locking in
        .alert("Protocol Detection Failed", isPresented: $bluetoothManager.showAutoDetectFailAlert) {
            Button("Open Settings") { selectedTab = Tab.settings }
            Button("Dismiss", role: .cancel) { }
        } message: {
            Text("None of the supported OBD-II protocols responded. Please select your vehicle manually in Settings.")
        }
        // Inject all managers into the SwiftUI environment so child views
        // can access them without explicit prop-drilling.
        .environment(obdDataManager)
        .environment(bluetoothManager)
        .environment(locationManager)
        .environment(motionManager)
        .task {
            // Wire BLE → OBD bridge and start simulator / logging
            bluetoothManager.obdDataManager = obdDataManager
            obdDataManager.setup(modelContext: modelContext)

            // Start GPS collection (requests permission on first launch)
            locationManager.setup(modelContext: modelContext)

            // Start IMU pitch/roll (no permissions required)
            motionManager.startUpdates()

            // Mark first launch complete so subsequent launches open TTE
            if !hasLaunchedBefore {
                hasLaunchedBefore = true
            }
        }
        // Pause IMU and GPS when the app leaves the foreground. Stopping GPS
        // clears the system location-in-use indicator (blue arrow/pill) and
        // saves battery. Location also stops on .inactive so transient states
        // (notification center, app switcher, call banner) release location;
        // IMU only stops on full .background.
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                motionManager.startUpdates()
                locationManager.startUpdating()
            case .inactive:
                locationManager.stopUpdating()
            case .background:
                motionManager.stopUpdates()
                locationManager.stopUpdating()
            @unknown default:
                break
            }
        }
    }
}

// MARK: - Preview
#Preview {
    // ContentView owns all four @State managers and injects them itself —
    // no explicit .environment() calls needed here.
    ContentView()
        .modelContainer(for: LogEntry.self, inMemory: true)
}
