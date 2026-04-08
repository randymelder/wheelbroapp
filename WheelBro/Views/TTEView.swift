// TTEView.swift
// Tab 0 — primary experience.
// Displays the giant Time-to-Empty countdown, Distance to Empty, and all
// live OBD telemetry cards.

import SwiftUI

struct TTEView: View {

    @Environment(OBDDataManager.self) private var obdManager
    @Environment(BluetoothManager.self) private var bleManager

    // Controls subtle entry animation on first appear
    @State private var appeared = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {

                    // ── Top status banner ────────────────────────────────────
                    statusBanner

                    // ── Logo ─────────────────────────────────────────────────
                    Image("wheelbro_logo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 72)
                        .padding(.top, 16)
                        .padding(.bottom, 8)

                    // ── Giant TTE display ────────────────────────────────────
                    tteBlock
                        .padding(.bottom, 24)

                    // ── OBD Value Card Grid ──────────────────────────────────
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 12
                    ) {
                        OBDValueCard(
                            title: "RPM",
                            value: "\(obdManager.rpm)",
                            unit:  "",
                            icon:  "gauge.with.needle"
                        )
                        OBDValueCard(
                            title: "Speed",
                            value: String(format: "%.0f", obdManager.speed),
                            unit:  "mph",
                            icon:  "speedometer"
                        )
                        OBDValueCard(
                            title: "Fuel Level",
                            value: String(format: "%.1f", obdManager.fuelLevel),
                            unit:  "%",
                            icon:  "fuelpump.fill"
                        )
                        OBDValueCard(
                            title: "Oil Temp",
                            value: String(format: "%.0f", obdManager.oilTemp),
                            unit:  "°F",
                            icon:  "thermometer.medium"
                        )
                        OBDValueCard(
                            title: "Coolant Temp",
                            value: String(format: "%.0f", obdManager.coolantTemp),
                            unit:  "°F",
                            icon:  "thermometer.snowflake"
                        )
                        OBDValueCard(
                            title: "Battery",
                            value: String(format: "%.1f", obdManager.batteryVoltage),
                            unit:  "V",
                            icon:  "battery.100"
                        )
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
        }
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.easeIn(duration: 0.35)) { appeared = true }
        }
    }

    // =========================================================================
    // MARK: - Sub-Views
    // =========================================================================

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
            .animation(.spring(response: 0.4), value: obdManager.fuelLevel)

            Text("TIME TO EMPTY")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .tracking(2)

            Divider()
                .background(Color.wheelBroYellow.opacity(0.3))
                .padding(.horizontal, 60)
                .padding(.vertical, 6)

            Text("Distance to Empty: \(String(format: "%.0f", obdManager.distanceToEmpty)) mi")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(.white)
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

    // ── VIN Card ──────────────────────────────────────────────────────────────
    private var vinCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("VIN")
                .font(.caption)
                .foregroundStyle(.secondary)
                .tracking(1)

            Text(obdManager.vin)
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
}

// MARK: - Preview
#Preview {
    let mgr = OBDDataManager()
    let ble = BluetoothManager()
    return TTEView()
        .environment(mgr)
        .environment(ble)
}
