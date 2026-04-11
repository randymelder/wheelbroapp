// DiagnosticsView.swift
// Displays the live diagnostic event stream captured by DiagnosticsManager.
// Accessible from Settings → Tools → Diagnostics.
//
// LAYOUT:
//   ┌─ NavigationBar: "Diagnostics"  [X events / Y total] ──────────────────┐
//   │  Filter bar — category chips + level chips                             │
//   │  ────────────────────────────────────────────────────────────────────  │
//   │  Event list (newest first, tap row to expand raw data)                 │
//   │                                                                        │
//   │  [  Clear  ]  [  Export  ]                                             │
//   └────────────────────────────────────────────────────────────────────────┘

import SwiftUI

struct DiagnosticsView: View {

    @Environment(DiagnosticsManager.self) private var diag
    @State private var expandedIDs: Set<UUID> = []

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                filterBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                Divider()
                    .background(Color.wheelBroYellow.opacity(0.2))

                Group {
                    if diag.filtered.isEmpty {
                        emptyState
                    } else {
                        eventList
                    }
                }
                .frame(maxHeight: .infinity)

                actionBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Text("\(diag.filtered.count) / \(diag.events.count)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    // =========================================================================
    // MARK: - Filter Bar
    // =========================================================================

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {

            // ── Category row ──────────────────────────────────────────────────
            HStack(spacing: 6) {
                filterLabel("CATEGORY")
                ForEach(DiagCategory.allCases, id: \.self) { cat in
                    DiagFilterChip(
                        label:       cat.rawValue,
                        isActive:    diag.categoryFilter.contains(cat),
                        activeColor: cat.color
                    ) {
                        if diag.categoryFilter.contains(cat) {
                            diag.categoryFilter.remove(cat)
                        } else {
                            diag.categoryFilter.insert(cat)
                        }
                    }
                }
                Spacer()
            }

            // ── Level row ─────────────────────────────────────────────────────
            HStack(spacing: 6) {
                filterLabel("LEVEL")
                DiagFilterChip(label: "ALL", isActive: diag.levelFilter == nil, activeColor: .white) {
                    diag.levelFilter = nil
                }
                ForEach(DiagLevel.allCases, id: \.self) { level in
                    DiagFilterChip(
                        label:       level.rawValue,
                        isActive:    diag.levelFilter == level,
                        activeColor: level.badgeColor
                    ) {
                        diag.levelFilter = (diag.levelFilter == level) ? nil : level
                    }
                }
                Spacer()
            }
        }
    }

    private func filterLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(1)
            .frame(width: 62, alignment: .leading)
    }

    // =========================================================================
    // MARK: - Event List
    // =========================================================================

    private var eventList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(diag.filtered.reversed()) { event in
                    DiagEventRow(
                        event:      event,
                        isExpanded: expandedIDs.contains(event.id)
                    ) {
                        if expandedIDs.contains(event.id) {
                            expandedIDs.remove(event.id)
                        } else {
                            expandedIDs.insert(event.id)
                        }
                    }
                    Divider()
                        .background(Color.white.opacity(0.06))
                        .padding(.leading, 16)
                }
            }
        }
    }

    // =========================================================================
    // MARK: - Empty State
    // =========================================================================

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(Color.wheelBroYellow.opacity(0.4))
            Text("No events")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Connect to your OBD dongle to start\ncapturing diagnostic events.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // =========================================================================
    // MARK: - Action Bar
    // =========================================================================

    private var actionBar: some View {
        HStack(spacing: 12) {

            Button {
                diag.clear()
                expandedIDs.removeAll()
            } label: {
                Label("Clear", systemImage: "trash")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(diag.events.isEmpty ? .secondary : Color.wheelBroRed)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                diag.events.isEmpty
                                    ? Color.white.opacity(0.1)
                                    : Color.wheelBroRed.opacity(0.4),
                                lineWidth: 1
                            )
                    }
            }
            .disabled(diag.events.isEmpty)

            ShareLink(
                item: diag.exportText,
                subject: Text("WheelBro Diagnostic Log"),
                message: Text("OBD-II diagnostic events captured by WheelBro")
            ) {
                Label("Export", systemImage: "square.and.arrow.up")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(diag.events.isEmpty ? .secondary : Color.wheelBroYellow)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                diag.events.isEmpty
                                    ? Color.white.opacity(0.1)
                                    : Color.wheelBroYellow.opacity(0.4),
                                lineWidth: 1
                            )
                    }
            }
            .disabled(diag.events.isEmpty)
        }
    }
}

// =============================================================================
// MARK: - DiagEventRow
// =============================================================================

private struct DiagEventRow: View {

    let event:      DiagEvent
    let isExpanded: Bool
    let onTap:      () -> Void

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 5) {

                // ── Header row ───────────────────────────────────────────────
                HStack(spacing: 6) {
                    Text(Self.timeFmt.string(from: event.timestamp))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)

                    // Level badge
                    Text(event.level.rawValue)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(event.level.badgeColor)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))

                    // Category badge
                    Text(event.category.rawValue)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(event.category.color)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(event.category.color.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))

                    Spacer()

                    if event.raw != nil {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                // ── Message ──────────────────────────────────────────────────
                Text(event.message)
                    .font(.caption)
                    .foregroundStyle(event.level.textColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)

                // ── Raw data (expanded) ───────────────────────────────────────
                if isExpanded, let raw = event.raw {
                    Text(raw)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Color.wheelBroYellow.opacity(0.85))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// =============================================================================
// MARK: - DiagFilterChip
// =============================================================================

private struct DiagFilterChip: View {
    let label:       String
    let isActive:    Bool
    let activeColor: Color
    let action:      () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isActive ? Color.black : Color.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isActive ? activeColor : Color.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// =============================================================================
// MARK: - DiagLevel helpers
// =============================================================================

extension DiagLevel {
    /// Fill color for the compact badge.
    var badgeColor: Color {
        switch self {
        case .info:    return Color(hex: "4FC3F7")  // sky blue — calm / informational
        case .warning: return Color.wheelBroYellow
        case .error:   return Color.wheelBroRed
        }
    }
    /// Color applied to the message text.
    var textColor: Color {
        switch self {
        case .info:    return .white
        case .warning: return Color.wheelBroYellow
        case .error:   return Color.wheelBroRed
        }
    }
}

// =============================================================================
// MARK: - DiagCategory helpers
// =============================================================================

extension DiagCategory {
    var color: Color {
        switch self {
        case .ble:    return Color(hex: "4FC3F7")  // sky blue
        case .obd:    return Color(hex: "81C784")  // green
        case .parse:  return Color(hex: "CE93D8")  // purple
        case .system: return Color(hex: "90A4AE")  // blue-grey
        }
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#Preview {
    PreviewDiagnosticsContainer()
}

private struct PreviewDiagnosticsContainer: View {
    @State private var diag: DiagnosticsManager = {
        let d = DiagnosticsManager()
        d.log(.info,    .system, "App started")
        d.log(.info,    .ble,    "Scan started")
        d.log(.info,    .ble,    "Found: IOS-Vlink (RSSI: -65 dBm)")
        d.log(.info,    .ble,    "Connecting → IOS-Vlink")
        d.log(.info,    .ble,    "Connected: IOS-Vlink")
        d.log(.info,    .system, "AT init sequence started")
        d.log(.info,    .obd,    "→ ATZ")
        d.log(.info,    .obd,    "← ELM327 v1.5", raw: "454C4D33323720763135")
        d.log(.info,    .obd,    "→ 010C")
        d.log(.info,    .obd,    "← 410C0FA0", raw: "410C0FA0")
        d.log(.info,    .parse,  "RPM: 1000 rpm")
        d.log(.warning, .obd,    "← NO DATA for 015E")
        d.log(.info,    .obd,    "→ ATRV")
        d.log(.info,    .obd,    "← 12.6V", raw: "31322E3656")
        d.log(.error,   .ble,    "Disconnected unexpectedly: CBError 6")
        return d
    }()

    var body: some View {
        NavigationStack {
            DiagnosticsView()
        }
        .environment(diag)
    }
}
