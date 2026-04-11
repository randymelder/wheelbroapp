// DiscoveryView.swift
// Queries the connected vehicle for every Mode-01 PID it supports and displays
// the results in a scrollable table. Results can be shared as a text report
// (Mail, Save to Files, AirDrop, etc.) via the iOS share sheet.

import SwiftUI

struct DiscoveryView: View {

    @Environment(BluetoothManager.self) private var bleManager
    @AppStorage("selectedVehicle") private var selectedVehicle = "Jeep Wrangler JK (2011-2018)"

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Status banner ─────────────────────────────────────────────
                statusBanner
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                // ── Results table (expands to fill available height) ──────────
                Group {
                    if bleManager.pidDiscoveryResults.isEmpty {
                        emptyState
                    } else {
                        resultsTable
                    }
                }
                .frame(maxHeight: .infinity)

                // ── Action bar ────────────────────────────────────────────────
                actionBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            }
        }
        .navigationTitle("PID Discovery")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // =========================================================================
    // MARK: - Sub-Views
    // =========================================================================

    private var statusBanner: some View {
        HStack(spacing: 8) {
            if bleManager.isDiscoveryRunning {
                ProgressView()
                    .tint(Color.wheelBroYellow)
                    .scaleEffect(0.85)
                Text("Querying vehicle…")
                    .font(.caption)
                    .foregroundStyle(Color.wheelBroYellow)
            } else if bleManager.discoveryFinished {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("\(bleManager.pidDiscoveryResults.count) PIDs supported")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else if !bleManager.isConnected {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.wheelBroRed)
                Text("Connect to your OBD dongle in Settings first")
                    .font(.caption)
                    .foregroundStyle(Color.wheelBroRed)
            } else {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(Color.wheelBroYellow)
                Text("Tap Rediscover to query supported PIDs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(Color.wheelBroYellow.opacity(0.4))
            Text("No results yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Tap Rediscover while connected\nto query your vehicle.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    private var resultsTable: some View {
        VStack(spacing: 0) {
            // ── Column headers ────────────────────────────────────────────────
            HStack(spacing: 0) {
                Text("PID")
                    .frame(width: 56, alignment: .leading)
                Text("Name")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(Color.wheelBroYellow)
            .tracking(1.2)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.cardBackground)

            Divider()
                .background(Color.wheelBroYellow.opacity(0.2))

            // ── Rows ──────────────────────────────────────────────────────────
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(bleManager.pidDiscoveryResults) { result in
                        HStack(spacing: 0) {
                            Text(result.pid)
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.wheelBroYellow)
                                .frame(width: 56, alignment: .leading)

                            Text(result.name)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Color.black)

                        Divider()
                            .background(Color.white.opacity(0.06))
                            .padding(.leading, 16)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.wheelBroYellow.opacity(0.18), lineWidth: 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var actionBar: some View {
        HStack(spacing: 12) {

            // Rediscover button
            Button(action: { bleManager.startPIDDiscovery() }) {
                Label(
                    bleManager.isDiscoveryRunning ? "Querying…" : "Rediscover",
                    systemImage: bleManager.isDiscoveryRunning
                        ? "arrow.2.circlepath"
                        : "arrow.clockwise"
                )
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    bleManager.isConnected && !bleManager.isDiscoveryRunning
                        ? Color.wheelBroYellow
                        : Color.wheelBroYellow.opacity(0.35)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .disabled(!bleManager.isConnected || bleManager.isDiscoveryRunning)

            // Share / Export button — only shown when results are ready
            if !bleManager.pidDiscoveryResults.isEmpty {
                ShareLink(
                    item: shareText,
                    subject: Text("WheelBro PID Discovery Report"),
                    message: Text("Supported OBD-II PIDs for \(selectedVehicle)")
                ) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.wheelBroYellow)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.wheelBroYellow.opacity(0.4), lineWidth: 1)
                        }
                }
            }
        }
    }

    // =========================================================================
    // MARK: - Share Text
    // =========================================================================

    private var shareText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .medium
        let dateString = formatter.string(from: Date())

        let pidCol  = "PID "    // 4 chars
        let sep     = String(repeating: "─", count: 6)
        let nameSep = String(repeating: "─", count: 44)

        var lines: [String] = [
            "WheelBro PID Discovery Report",
            "Vehicle : \(selectedVehicle)",
            "Generated: \(dateString)",
            "",
            "\(pidCol)  Name",
            "\(sep)  \(nameSep)",
        ]

        for result in bleManager.pidDiscoveryResults {
            let pidPadded = result.pid.padding(toLength: 4, withPad: " ", startingAt: 0)
            lines.append("\(pidPadded)  \(result.name)")
        }

        lines += [
            "",
            "Total: \(bleManager.pidDiscoveryResults.count) PIDs supported",
        ]

        return lines.joined(separator: "\n")
    }
}

// MARK: - Preview

#Preview {
    PreviewDiscoveryContainer()
}

private struct PreviewDiscoveryContainer: View {
    @State private var ble: BluetoothManager = {
        let b = BluetoothManager()
        b.pidDiscoveryResults = [
            PIDResult(pid: "01", name: "Monitor Status / MIL"),
            PIDResult(pid: "04", name: "Engine Load"),
            PIDResult(pid: "05", name: "Coolant Temperature"),
            PIDResult(pid: "0C", name: "Engine RPM"),
            PIDResult(pid: "0D", name: "Vehicle Speed"),
            PIDResult(pid: "0F", name: "Intake Air Temperature"),
            PIDResult(pid: "2F", name: "Fuel Tank Level"),
            PIDResult(pid: "5C", name: "Engine Oil Temperature"),
            PIDResult(pid: "5E", name: "Engine Fuel Rate"),
        ]
        b.discoveryFinished = true
        return b
    }()

    var body: some View {
        NavigationStack { DiscoveryView() }
            .environment(ble)
            .environment(OBDDataManager())
            .environment(DiagnosticsManager())
    }
}
