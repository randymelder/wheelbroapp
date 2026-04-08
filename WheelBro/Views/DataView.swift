// DataView.swift
// Tab 2 — log browser and CSV export.
// Queries SwiftData for all LogEntry rows and lets the user export them
// as a CSV via the native share sheet (UIActivityViewController).
// The generated file is iCloud Drive compatible via the Files app.

import SwiftUI
import SwiftData

struct DataView: View {

    // Fetch ALL log entries, newest first
    @Query(sort: \LogEntry.date, order: .reverse) private var entries: [LogEntry]
    @Environment(OBDDataManager.self) private var obdManager

    // Share sheet state
    @State private var exportURL:       URL?
    @State private var showShareSheet:  Bool = false
    @State private var exportError:     String?
    @State private var showErrorAlert:  Bool = false

    // Simple stats
    private var uniqueDates: Int {
        Set(entries.map(\.date)).count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {

                    // ── Header logo ──────────────────────────────────────────
                    Image("wheelbro_logo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 68)
                        .padding(.top, 20)
                        .padding(.bottom, 12)

                    // ── Stats strip ──────────────────────────────────────────
                    statsStrip
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)

                    // ── Export button ────────────────────────────────────────
                    Button(action: exportCSV) {
                        HStack(spacing: 10) {
                            Image(systemName: "square.and.arrow.up.fill")
                                .font(.headline)
                            Text("Export Logs")
                                .font(.headline)
                                .fontWeight(.bold)
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.wheelBroYellow)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(entries.isEmpty)
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
                    Text("© 2026 WheelBro LLC. All Rights Reserved.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 12)
                }
            }
            .navigationTitle("Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        // Native share sheet
        .sheet(isPresented: $showShareSheet) {
            if let url = exportURL {
                ActivityView(items: [url])
            }
        }
        // Export error
        .alert("Export Failed", isPresented: $showErrorAlert) {
            Button("OK") { }
        } message: {
            Text(exportError ?? "Unknown error")
        }
    }

    // =========================================================================
    // MARK: - Sub-Views
    // =========================================================================

    private var statsStrip: some View {
        HStack(spacing: 12) {
            statBadge(value: "\(entries.count)", label: "Rows")
            statBadge(value: "\(uniqueDates)", label: "Sessions")
            statBadge(
                value: obdManager.isSimulatorOn ? "SIM" : (obdManager.isConnected ? "LIVE" : "—"),
                label: "Source"
            )
        }
    }

    private func statBadge(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Color.wheelBroYellow)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

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
    // MARK: - CSV Export
    // =========================================================================

    private func exportCSV() {
        // Build CSV string
        var csv = "id,date,time,key,value,bleDeviceName,vinNumber\n"
        for e in entries {
            // Escape any commas or quotes in values
            let safeValue    = e.value.replacingOccurrences(of: "\"", with: "\"\"")
            let safeDevice   = e.bleDeviceName.replacingOccurrences(of: "\"", with: "\"\"")
            let safeVIN      = e.vinNumber.replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\(e.id),\(e.date),\(e.time),\(e.key),\"\(safeValue)\",\"\(safeDevice)\",\"\(safeVIN)\"\n"
        }

        // Write to app's Documents directory (iCloud Drive compatible)
        let docs   = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let ts     = Int(Date().timeIntervalSince1970)
        let fileURL = docs.appendingPathComponent("WheelBro_Logs_\(ts).csv")

        do {
            try csv.write(to: fileURL, atomically: true, encoding: .utf8)
            exportURL      = fileURL
            showShareSheet = true
        } catch {
            exportError     = error.localizedDescription
            showErrorAlert  = true
        }
    }
}

// =============================================================================
// MARK: - UIActivityViewController wrapper
// =============================================================================

/// Wraps UIActivityViewController for use in SwiftUI sheets.
/// Supports any combination of items (URLs, strings, images, etc.).
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
}
