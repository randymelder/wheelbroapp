// LocationManager.swift
// Wraps CLLocationManager to provide live GPS data: latitude, longitude,
// heading (true north), and altitude.
//
// COLLECTION MODEL:
//   - GPS runs only while the app is in the foreground. ContentView observes
//     scenePhase and calls stopUpdating() on .inactive/.background and
//     startUpdating() on .active. Stopping updates clears the system
//     location-in-use indicator (blue arrow/pill) and saves battery.
//   - allowsBackgroundLocationUpdates = true and the UIBackgroundModes/location
//     entitlement are retained but currently unused — the capability is kept
//     available in case the foreground-only policy is revisited.
//   - pausesLocationUpdatesAutomatically = false prevents CoreLocation from
//     suspending updates when motion is not detected while in foreground.
//   - A 10-second timer snapshots the latest values to SwiftData. It is
//     currently disabled (startLocationLogging() call sites commented out).
//
// PERMISSIONS REQUIRED IN Info.plist:
//   NSLocationWhenInUseUsageDescription
//   NSLocationAlwaysAndWhenInUseUsageDescription
//   UIBackgroundModes → location  (retained, currently unused)

import Foundation
import CoreLocation
import SwiftData
import Observation

@Observable
final class LocationManager: NSObject {

    // =========================================================================
    // MARK: - Public State  (observed by SwiftUI views)
    // =========================================================================
    var latitude:            Double = 0.0   // decimal degrees, WGS84
    var longitude:           Double = 0.0   // decimal degrees, WGS84
    var heading:             Double = 0.0   // degrees clockwise from true north (0–360)
    var altitude:            Double = 0.0   // metres above sea level
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var isAuthorized:        Bool   = false

    // =========================================================================
    // MARK: - Private State
    // =========================================================================
    private let clManager        = CLLocationManager()
    private var locationLogTimer: Timer?
    private var modelContext:     ModelContext?

    // =========================================================================
    // MARK: - Init
    // =========================================================================
    override init() {
        super.init()
        clManager.delegate                   = self
        clManager.desiredAccuracy            = kCLLocationAccuracyBest
        clManager.distanceFilter             = kCLDistanceFilterNone
        // Required for collection to continue while the app is backgrounded.
        // The Info.plist UIBackgroundModes/location key enables this entitlement.
        clManager.allowsBackgroundLocationUpdates = true
        clManager.pausesLocationUpdatesAutomatically = false
    }

    // =========================================================================
    // MARK: - Setup  (called from ContentView after SwiftData is ready)
    // =========================================================================
    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
        // Trigger the iOS permission prompt if not yet determined.
        // Once the user grants access, locationManagerDidChangeAuthorization
        // fires and startUpdating() is called automatically.
        if clManager.authorizationStatus == .notDetermined {
            clManager.requestWhenInUseAuthorization()
        } else {
            handleAuthorizationChange(clManager.authorizationStatus)
        }
    }

    // =========================================================================
    // MARK: - Start / Stop
    // =========================================================================
    func startUpdating() {
        clManager.startUpdatingLocation()
        clManager.startUpdatingHeading()
        //startLocationLogging()
        print("[Location] started — accuracy: best, background: enabled")
    }

    func stopUpdating() {
        clManager.stopUpdatingLocation()
        clManager.stopUpdatingHeading()
        //stopLocationLogging()
        print("[Location] stopped")
    }

    // =========================================================================
    // MARK: - 10-Second GPS Logging Timer
    // =========================================================================
    private func startLocationLogging() {
        stopLocationLogging()
        locationLogTimer = Timer.scheduledTimer(
            withTimeInterval: VehicleConstants.locationLoggingInterval,
            repeats: true
        ) { [weak self] _ in
            self?.logCurrentLocation()
        }
    }

    private func stopLocationLogging() {
        locationLogTimer?.invalidate()
        locationLogTimer = nil
    }

    private func logCurrentLocation() {
        // Skip if no fix yet — both coords stay at 0.0 until CLLocationManager delivers the first update.
        guard let ctx = modelContext, !(latitude == 0.0 && longitude == 0.0) else { return }

        let now = Date()
        let df  = DateFormatter()
        df.dateFormat = DateFormat.date
        let dateStr = df.string(from: now)
        df.dateFormat = DateFormat.time
        let timeStr = df.string(from: now)

        let rows: [(String, String)] = [
            (OBDKey.latitude,  String(format: "%.6f", latitude)),
            (OBDKey.longitude, String(format: "%.6f", longitude)),
            (OBDKey.heading,   String(format: "%.1f",  heading)),
            (OBDKey.altitude,  String(format: "%.1f",  altitude)),
        ]

        for (key, value) in rows {
            ctx.insert(LogEntry(
                date:          dateStr,
                time:          timeStr,
                key:           key,
                value:         value,
                bleDeviceName: OBDLogPID.gps,
                vinNumber:     "",
                pid:           OBDLogPID.gps
            ))
        }

        try? ctx.save()
        print("[Location] logged — lat=\(String(format: "%.5f", latitude)) lon=\(String(format: "%.5f", longitude)) hdg=\(String(format: "%.0f", heading))° alt=\(String(format: "%.0f", altitude))m")
    }

    // =========================================================================
    // MARK: - Private Helpers
    // =========================================================================
    private func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        authorizationStatus = status
        isAuthorized = (status == .authorizedWhenInUse || status == .authorizedAlways)
        if isAuthorized {
            startUpdating()
        } else {
            stopUpdating()
        }
    }
}

// =============================================================================
// MARK: - CLLocationManagerDelegate
// =============================================================================
extension LocationManager: CLLocationManagerDelegate {

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        print("[Location] authorization changed → \(manager.authorizationStatus.rawValue)")
        handleAuthorizationChange(manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        latitude  = loc.coordinate.latitude
        longitude = loc.coordinate.longitude
        altitude  = loc.altitude
        
        print("[Location] lat=\(String(format: "%.5f", latitude)) lon=\(String(format: "%.5f", longitude)) alt=\(String(format: "%.0f", altitude))m")
    }

    func locationManager(_ manager: CLLocationManager,
                         didUpdateHeading newHeading: CLHeading) {
        // Use true heading when calibrated (>= 0); fall back to magnetic.
        heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        print("[Location] heading=\(String(format: "%.1f", heading))°")
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[Location] error: \(error.localizedDescription)")
    }
}
