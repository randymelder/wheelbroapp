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
    @Environment(OBDDataManager.self)  private var obdManager
    @Environment(BluetoothManager.self) private var bleManager
    @Environment(\.modelContext) private var modelContext

    // Log export share sheet
    @State private var exportURL:       URL?
    @State private var showShareSheet:  Bool = false
    @State private var exportError:     String?
    @State private var showErrorAlert:  Bool = false

    // PID discovery sheet
    @State private var showDiscoverySheet: Bool = false

    // Persisted user preference — clear log automatically after a successful export
    @AppStorage("clearAfterExport") private var clearAfterExport: Bool = false

    // Simple stats
    private var uniqueSessions: Int {
        // sessionID is empty for rows logged before the v2 schema — fall back to
        // counting unique dates so the badge remains meaningful on migrated stores.
        let ids = Set(entries.map(\.sessionID)).filter { !$0.isEmpty }
        return ids.isEmpty ? Set(entries.map(\.date)).count : ids.count
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

                    // ── Clear after export toggle ─────────────────────────────
                    Toggle(isOn: $clearAfterExport) {
                        Label {
                            Text("Clear log after export")
                                .font(.subheadline)
                                .foregroundStyle(.white)
                        } icon: {
                            Image(systemName: "trash")
                                .foregroundStyle(clearAfterExport ? Color.wheelBroRed : .secondary)
                        }
                    }
                    .tint(Color.wheelBroRed)
                    .padding(.horizontal, 28)
                    .padding(.top, 14)

                    if entries.isEmpty {
                        Text("No log data yet — enable logging in Settings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }

                    // ── Discover PIDs button ──────────────────────────────────
                    // Yellow styling is always applied; SwiftUI's .disabled()
                    // reduces opacity (~0.3) so the button stays visible but
                    // clearly inactive when not connected.
                    Button(action: { showDiscoverySheet = true }) {
                        Label("Discover PIDs", systemImage: "list.bullet.rectangle.portrait")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.wheelBroYellow)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.wheelBroYellow.opacity(0.5), lineWidth: 1)
                            }
                    }
                    .disabled(!bleManager.isConnected)
                    .padding(.horizontal, 24)
                    .padding(.top, 10)

                    if !bleManager.isConnected {
                        Text("Connect to your OBD dongle to run PID discovery")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
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
        // Log export share sheet
        .sheet(isPresented: $showShareSheet) {
            if let url = exportURL {
                ActivityView(items: [url])
            }
        }
        // PID discovery sheet
        .sheet(isPresented: $showDiscoverySheet) {
            PIDDiscoverySheet()
                .environment(bleManager)
        }
        // After the share sheet closes, delete all entries if the toggle is on
        .onChange(of: showShareSheet) { _, isShowing in
            guard !isShowing, clearAfterExport else { return }
            deleteAllEntries()
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
            statBadge(value: "\(uniqueSessions)", label: "Sessions")
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
            // Key
            Text(entry.key)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.wheelBroYellow)
                .frame(width: 100, alignment: .leading)

            // PID badge — hidden for computed rows with no PID
            if !entry.pid.isEmpty {
                Text(entry.pid)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(Color.wheelBroYellow.opacity(0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            }

            // Value + unit
            HStack(spacing: 3) {
                Text(entry.value)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white)
                if !entry.unit.isEmpty {
                    Text(entry.unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Timestamp
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

    private func deleteAllEntries() {
        for entry in entries {
            modelContext.delete(entry)
        }
        try? modelContext.save()
    }

    // ── CSV helpers ───────────────────────────────────────────────────────────

    /// Wraps a field in double-quotes and escapes any interior double-quotes
    /// per RFC 4180.  Applied to every field so the output is always safe,
    /// regardless of whether the value contains commas, quotes, or newlines.
    private func csvField(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private func exportCSV() {
        // Column order matches LogEntry field declaration order.
        let header = [
            "id", "date", "time", "sessionID",
            "key", "pid", "unit", "value",
            "bleDeviceName", "vinNumber",
        ].map { csvField($0) }.joined(separator: ",")

        var lines = [header]

        for e in entries {
            let row = [
                e.id.uuidString,
                e.date,
                e.time,
                e.sessionID,
                e.key,
                e.pid,
                e.unit,
                e.value,
                e.bleDeviceName,
                e.vinNumber,
            ].map { csvField($0) }.joined(separator: ",")
            lines.append(row)
        }

        let csv = lines.joined(separator: "\n") + "\n"

        // Write to app's Documents directory (iCloud Drive / Files app compatible)
        let docs    = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let ts      = Int(Date().timeIntervalSince1970)
        let fileURL = docs.appendingPathComponent("WheelBro_Logs_\(ts).csv")

        do {
            try csv.write(to: fileURL, atomically: true, encoding: .utf8)
            exportURL      = fileURL
            showShareSheet = true
        } catch {
            exportError    = error.localizedDescription
            showErrorAlert = true
        }
    }
}

// =============================================================================
// MARK: - PID Discovery Sheet
// =============================================================================
/// Presented as a sheet from DataView when the user taps "Discover PIDs".
/// Starts PID discovery automatically on appear (if connected), shows the
/// results in a scrollable table, and exports them as a CSV file named
/// wheelbro_discovery_<unix-timestamp>.csv.
private struct PIDDiscoverySheet: View {

    @Environment(BluetoothManager.self) private var bleManager
    @Environment(\.dismiss) private var dismiss

    @State private var exportURL:      URL?
    @State private var showShareSheet: Bool   = false
    @State private var exportError:    String?
    @State private var showErrorAlert: Bool   = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {

                    // ── Status banner ─────────────────────────────────────────
                    statusBanner
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                    // ── Results / empty state ─────────────────────────────────
                    Group {
                        if bleManager.pidDiscoveryResults.isEmpty {
                            emptyState
                        } else {
                            resultsTable
                        }
                    }
                    .frame(maxHeight: .infinity)

                    // ── Action bar ────────────────────────────────────────────
                    actionBar
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }
            }
            .navigationTitle("PID Discovery")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.wheelBroYellow)
                }
            }
        }
        .onAppear {
            // Auto-start if connected and idle so the user doesn't need a
            // second tap after opening the sheet.
            if bleManager.isConnected && !bleManager.isDiscoveryRunning {
                bleManager.startPIDDiscovery()
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportURL { ActivityView(items: [url]) }
        }
        .alert("Export Failed", isPresented: $showErrorAlert) {
            Button("OK") {}
        } message: {
            Text(exportError ?? "Unknown error")
        }
    }

    // ── Status banner ─────────────────────────────────────────────────────────
    private var statusBanner: some View {
        HStack(spacing: 8) {
            if bleManager.isDiscoveryRunning {
                ProgressView().tint(Color.wheelBroYellow).scaleEffect(0.85)
                Text("Querying vehicle…")
                    .font(.caption).foregroundStyle(Color.wheelBroYellow)
            } else if bleManager.discoveryFinished {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("\(bleManager.pidDiscoveryResults.count) PIDs supported")
                    .font(.caption).foregroundStyle(.green)
            } else if !bleManager.isConnected {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.wheelBroRed)
                Text("Connect to your OBD dongle first")
                    .font(.caption).foregroundStyle(Color.wheelBroRed)
            } else {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(Color.wheelBroYellow)
                Text("Tap Rediscover to re-run the query")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // ── Empty state ───────────────────────────────────────────────────────────
    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(Color.wheelBroYellow.opacity(0.4))
            Text("No results yet")
                .font(.headline).foregroundStyle(.secondary)
            Text("Connect to your vehicle and tap Rediscover.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    // ── Results table ─────────────────────────────────────────────────────────
    private var resultsTable: some View {
        VStack(spacing: 0) {
            // Column headers
            HStack(spacing: 0) {
                Text("PID")
                    .frame(width: 56, alignment: .leading)
                Text("Name")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption).fontWeight(.semibold)
            .foregroundStyle(Color.wheelBroYellow)
            .tracking(1.2)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Color.cardBackground)

            Divider().background(Color.wheelBroYellow.opacity(0.2))

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
                        .padding(.horizontal, 16).padding(.vertical, 9)
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

    // ── Action bar ────────────────────────────────────────────────────────────
    private var actionBar: some View {
        HStack(spacing: 12) {

            // Rediscover
            Button(action: { bleManager.startPIDDiscovery() }) {
                Label(
                    bleManager.isDiscoveryRunning ? "Querying…" : "Rediscover",
                    systemImage: bleManager.isDiscoveryRunning
                        ? "arrow.2.circlepath" : "arrow.clockwise"
                )
                .font(.subheadline).fontWeight(.semibold)
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

            // Export CSV — only shown when results exist
            if !bleManager.pidDiscoveryResults.isEmpty {
                Button(action: exportDiscoveryCSV) {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                        .font(.subheadline).fontWeight(.semibold)
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

    // ── Export ────────────────────────────────────────────────────────────────

    private func csvField(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private func exportDiscoveryCSV() {
        let header = ["pid", "name"].map { csvField($0) }.joined(separator: ",")
        var lines  = [header]

        for result in bleManager.pidDiscoveryResults {
            let row = [result.pid, result.name].map { csvField($0) }.joined(separator: ",")
            lines.append(row)
        }

        let csv     = lines.joined(separator: "\n") + "\n"
        let docs    = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let ts      = Int(Date().timeIntervalSince1970)
        let fileURL = docs.appendingPathComponent("wheelbro_discovery_\(ts).csv")

        do {
            try csv.write(to: fileURL, atomically: true, encoding: .utf8)
            exportURL      = fileURL
            showShareSheet = true
        } catch {
            exportError    = error.localizedDescription
            showErrorAlert = true
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
        .environment(BluetoothManager())
}
