// WheelBroApp.swift
// WheelBro — iOS OBD-II Time to Empty Monitor for Jeep Wrangler JK (2011-2018)
//
// XCODE PROJECT SETUP NOTES:
// 1. Create a new iOS App project in Xcode named "WheelBro"
// 2. Set minimum deployment target to iOS 26 (or iOS 17 if building pre-release)
// 3. Add wheelbro_logo.png to Assets.xcassets as "wheelbro_logo" (image set)
// 4. Add AppIcon to Assets.xcassets using wheelbro_logo.png resized to all required icon sizes
// 5. Add the following key to Info.plist:
//    <key>NSBluetoothAlwaysUsageDescription</key>
//    <string>WheelBro needs Bluetooth to connect to your OBD-II dongle and read live vehicle data.</string>
// 6. Enable "Background Modes" capability → check "Uses Bluetooth LE accessories" if you want
//    BLE to stay alive when the app is backgrounded.
// 7. Drag all .swift files from this folder into the Xcode project navigator.

import SwiftUI
import SwiftData

@main
struct WheelBroApp: App {

    // MARK: - SwiftData Model Container
    // LogEntry is the only persistent model in this app.
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([LogEntry.self])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none   // set to .automatic to enable CloudKit sync
        )
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("WheelBro: Could not create SwiftData ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)   // Force dark theme across the entire app
        }
        .modelContainer(sharedModelContainer)
    }
}
