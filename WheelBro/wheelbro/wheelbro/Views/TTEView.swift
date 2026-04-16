// TTEView.swift
// Tab 0 — primary experience.
// Displays the giant Time-to-Empty countdown, Distance to Empty, and all
// live OBD telemetry cards.

import SwiftUI
import CoreBluetooth
import AudioToolbox
import Photos

struct TTEView: View {

    @Environment(OBDDataManager.self)  private var obdManager
    @Environment(BluetoothManager.self) private var bleManager
    @Environment(LocationManager.self) private var locationManager
    @Environment(MotionManager.self)   private var motionManager

    /// Binding to the root tab selection so tapping "Open Settings" navigates there.
    @Binding var selectedTab: Int

    // Controls subtle entry animation on first appear
    @State private var appeared  = false

    // Incremented every second by the .task heartbeat to force a TTE re-render
    @State private var tickCount = 0
    @State private var vinText: String?

    // White flash overlay state for the screenshot shutter effect
    @State private var isFlashing = false

    // Set to true when the user taps Ignore on the no-connection overlay
    @State private var ignoredDisconnect = false

    /// True when there is no active data source — simulator off and BLE disconnected.
    private var isDisconnected: Bool {
        !obdManager.isSimulatorOn && !bleManager.isConnected
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {

                // ── Top status banner ────────────────────────────────────
                statusBanner

                // ── Logo ─────────────────────────────────────────────────
//                Image("wheelbro_logo")
//                    .resizable()
//                    .scaledToFit()
//                    .frame(height: 72)
//                    .padding(.top, 16)
//                    .padding(.bottom, 8)

                // ── Giant TTE display ────────────────────────────────────
                tteBlock
                    .padding(.bottom, 24)
                    .onTapGesture(count: 2) { captureAndSave() }

                // ── OBD Value Card Grid ──────────────────────────────────
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 12
                ) {
//                    OBDValueCard(
//                        title: "RPM",
//                        value: "\(obdManager.rpm)",
//                        unit:  "",
//                        icon:  "gauge.with.needle"
//                    )

                    OBDValueCard(
                        title: "DTE",
                        value: String(format: "%.1f", obdManager.distanceToEmpty),
                        unit:  "Miles",
                        icon:  "gauge.with.needle"
                    )
                    OBDValueCard(
                        title: "Fuel Level",
                        value: String(format: "%.1f", obdManager.fuelLevel),
                        unit:  "%",
                        icon:  "fuelpump.fill"
                    )
                    OBDValueCard(
                        title: "Speed",
                        value: String(format: "%.0f", obdManager.speed),
                        unit:  "mph",
                        icon:  "speedometer"
                    )
                    // ── Pitch / Roll — combined card ─────────────────────
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Image(systemName: "gyroscope")
                                .font(.caption)
                                .foregroundStyle(Color.wheelBroYellow)
                            Text("Pitch / Roll")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(format: "%.1f°", motionManager.pitch))
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .monospacedDigit()
                                    .lineLimit(1)
                                Text(motionManager.pitch >= 0 ? "Up" : "Down")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Divider()
                                .frame(height: 32)
                                .background(Color.wheelBroYellow.opacity(0.3))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(format: "%.1f°", abs(motionManager.roll)))
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .monospacedDigit()
                                    .lineLimit(1)
                                Text(motionManager.roll >= 0 ? "Right" : "Left")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.wheelBroYellow.opacity(0.18), lineWidth: 1)
                    }
                    OBDValueCard(
                        title: "Heading",
                        value: headingText,
                        unit:  compassPoint,
                        icon:  "location.north.line.fill"
                    )
                    OBDValueCard(
                        title: "Altitude",
                        value: String(format: "%.0f", locationManager.altitude * VehicleConstants.metersToFeet),
                        unit:  "ft",
                        icon:  "mountain.2.fill"
                    )
                    OBDValueCard(
                        title: "Latitude",
                        value: String(format: "%.5f", locationManager.latitude),
                        unit:  locationManager.latitude >= 0 ? "N" : "S",
                        icon:  "mappin.and.ellipse"
                    )
                    OBDValueCard(
                        title: "Longitude",
                        value: String(format: "%.5f", abs(locationManager.longitude)),
                        unit:  locationManager.longitude >= 0 ? "E" : "W",
                        icon:  "mappin.and.ellipse"
                    )

//                    OBDValueCard(
//                        title: "Oil Temp",
//                        value: String(format: "%.0f", obdManager.oilTemp),
//                        unit:  "°F",
//                        icon:  "thermometer.medium"
//                    )
//                    OBDValueCard(
//                        title: "Coolant Temp",
//                        value: String(format: "%.0f", obdManager.coolantTemp),
//                        unit:  "°F",
//                        icon:  "thermometer.snowflake"
//                    )
//                    OBDValueCard(
//                        title: "Battery",
//                        value: String(format: "%.1f", obdManager.batteryVoltage),
//                        unit:  "V",
//                        icon:  "battery.100"
//                    )
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                // ── DTC / Error Codes ────────────────────────────────────
                dtcCard
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                // ── VIN ──────────────────────────────────────────────────
                vinCard
                    .padding(.horizontal, 16)
                    .padding(.bottom, 30)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.easeIn(duration: 0.35)) { appeared = true }
        }
        .overlay {
            if isDisconnected && !ignoredDisconnect {
                disconnectedOverlay
            }
        }
        // Reset the ignore flag whenever the connection state changes so the
        // overlay reappears if the user later disconnects again.
        .onChange(of: bleManager.isConnected) { _, connected in
            if connected { ignoredDisconnect = false }
        }
        // Full-screen white flash — rendered on top of everything, non-interactive
        .overlay {
            if isFlashing {
                Color.white
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .task {
            // Stable 1-second heartbeat. Unlike a Combine timer on a struct property,
            // .task persists for the view's lifetime and is NOT restarted on re-renders.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(UIConstants.tteTickInterval))
                tickCount += 1
                withAnimation {
                    vinText = obdManager.vin
                }
            }
        }
    }

    // =========================================================================
    // MARK: - Sub-Views
    // =========================================================================

    // ── Heading Helpers ───────────────────────────────────────────────────────
    /// Degrees as a formatted string, or "—" before the first GPS fix.
    private var headingText: String {
        // Show "—" until authorized AND a real GPS fix has arrived (lat & lon both non-zero).
        guard locationManager.isAuthorized,
              !(locationManager.latitude == 0.0 && locationManager.longitude == 0.0) else {
            return "—"
        }
        return String(format: "%.0f°", locationManager.heading)
    }

    /// Cardinal / intercardinal label for the heading value.
    private var compassPoint: String {
        let h = locationManager.heading
        switch h {
        case 337.5..<360, 0..<22.5:   return "N"
        case 22.5..<67.5:             return "NE"
        case 67.5..<112.5:            return "E"
        case 112.5..<157.5:           return "SE"
        case 157.5..<202.5:           return "S"
        case 202.5..<247.5:           return "SW"
        case 247.5..<292.5:           return "W"
        case 292.5..<337.5:           return "NW"
        default:                       return ""
        }
    }

    // ── Status Banner ─────────────────────────────────────────────────────────
    private var statusBanner: some View {
        HStack(spacing: 8) {

            // Connection indicator dot
            Circle()
                .fill(activeColor)
                .frame(width: 9, height: 9)
                .shadow(color: activeColor.opacity(0.6), radius: 4)

            Text(statusLabel)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(activeColor)

            Spacer()

            // Small logo in banner
            Image("wheelbro_logo")
                .resizable()
                .scaledToFit()
                .frame(height: 26)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.bannerBackground)
    }

    private var activeColor: Color {
        obdManager.isSimulatorOn || bleManager.isConnected ? Color.green : Color.wheelBroRed
    }

    private var statusLabel: String {
        if obdManager.isSimulatorOn {
            return "Simulator ON"
        } else if bleManager.isConnected,
                  let name = bleManager.connectedPeripheral?.name {
            // Battery voltage available (ATRV works ignition-off) but no ECU data yet
            // means the ignition is off — the ELM327 is returning SEARCHING/STOPPED.
            if obdManager.fuelLevel == 0 && obdManager.rpm == 0 && obdManager.speed == 0 {
                return "Connected — turn ignition ON"
            }
            return "Connected to \(name)"
        } else {
            return bleManager.connectionStatus
        }
    }

    // ── Giant TTE Block ────────────────────────────────────────────────────────
    private var tteBlock: some View {
        VStack(spacing: 4) {
            Text(obdManager.calculateTimeToEmpty(
                fuelLevel:  obdManager.fuelLevel,
                speed:      obdManager.speed,
                rpm:        obdManager.rpm,
                errorCodes: obdManager.errorCodes
            ))
            .font(.system(size: 80, weight: .bold, design: .rounded))
            .foregroundStyle(Color.wheelBroYellow)
            .monospacedDigit()
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .shadow(color: Color.wheelBroYellow.opacity(0.4), radius: 12)
            .contentTransition(.numericText())
            .animation(.spring(response: 0.4), value: tickCount)

            Text("TIME TO EMPTY")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .tracking(2)

            Divider()
                .background(Color.wheelBroYellow.opacity(0.3))
                .padding(.horizontal, 60)
                .padding(.vertical, 6)

//            Text("Distance to Empty: \(String(format: "%.0f", obdManager.distanceToEmpty)) mi")
//                .font(.title3)
//                .fontWeight(.medium)
//                .foregroundStyle(.white)
        }
        .padding(.vertical, 10)
    }

    // ── DTC Card ──────────────────────────────────────────────────────────────
    private var dtcCard: some View {
        let hasFaults = obdManager.errorCodes != "None"

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: hasFaults ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                    .foregroundStyle(hasFaults ? Color.wheelBroRed : Color.green)
                Text("Diagnostic Trouble Codes")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }

            Text(obdManager.errorCodes)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(hasFaults ? Color.wheelBroRed : Color.green)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    hasFaults ? Color.wheelBroRed.opacity(0.4) : Color.wheelBroYellow.opacity(0.18),
                    lineWidth: 1
                )
        }
    }

    // ── No-Connection Overlay ─────────────────────────────────────────────────
    private var disconnectedOverlay: some View {
        ZStack {
            Color.black.opacity(0.82)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "bolt.slash.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.wheelBroRed)
                    .shadow(color: Color.wheelBroRed.opacity(0.5), radius: 12)

                Text("No Device Connected")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                Text("Connect an OBD-II adapter in Settings\nto start receiving live vehicle data.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    selectedTab = Tab.settings
                } label: {
                    Label("Open Settings", systemImage: "gearshape.fill")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.wheelBroYellow)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.horizontal, 40)
                .padding(.top, 4)

                Button {
                    ignoredDisconnect = true
                } label: {
                    Text("Ignore")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(32)
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.25), value: isDisconnected)
    }

    // ── VIN Card ──────────────────────────────────────────────────────────────
    private var vinCard: some View {
        
        VStack(alignment: .leading, spacing: 4) {
            Text("VIN")
                .font(.caption)
                .foregroundStyle(.secondary)
                .tracking(1)

            Text(vinText ?? obdManager.vin)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.wheelBroYellow.opacity(0.18), lineWidth: 1)
        }
    }
    // =========================================================================
    // MARK: - Screenshot
    // =========================================================================

    /// Triggered by a swipe-down gesture. Captures the full screen, plays the
    /// shutter sound, flashes the display, then saves the image to Photos.
    private func captureAndSave() {
        // 1. Grab the key window from the active scene
        guard let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) else {
            print("[Screenshot] could not locate key window")
            return
        }

        // 2. Render the full window hierarchy into a UIImage.
        //    afterScreenUpdates:false captures the CURRENT frame before the
        //    flash overlay is applied, so the screenshot itself stays clean.
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }

        // 3. Shutter sound (respects the device's silent switch — iOS enforces this)
        AudioServicesPlaySystemSound(1108)

        // 4. Screen flash: quick white burst, then fade out
        withAnimation(.linear(duration: 0.05))  { isFlashing = true  }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeIn(duration: 0.3)) { isFlashing = false }
        }

        // 5. Request add-only Photos permission then save
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            // .authorized = full access granted; .limited also permits writing new assets.
            guard status == .authorized || status == .limited else {
                print("[Screenshot] Photos permission denied (status \(status.rawValue))")
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset()
                    .addResource(with: .photo,
                                 data: image.pngData() ?? Data(),
                                 options: nil)
            } completionHandler: { success, error in
                if let error {
                    print("[Screenshot] save failed: \(error.localizedDescription)")
                } else {
                    print("[Screenshot] saved to Photos")
                }
            }
        }
    }
}

// MARK: - Preview
#Preview {
    let mgr = OBDDataManager()
    let ble = BluetoothManager()
    let loc = LocationManager()
    let mot = MotionManager()
    return TTEView(selectedTab: .constant(Tab.tte))
        .environment(mgr)
        .environment(ble)
        .environment(loc)
        .environment(mot)
}
