// DiagnosticsManager.swift
// Collects timestamped diagnostic events from BluetoothManager and the OBD
// pipeline so connection and parsing problems can be reproduced and reported.
//
// EVENT FLOW:
//   BluetoothManager calls log() at every meaningful lifecycle point.
//   DiagnosticsView reads events and applies category / level filters.
//   The user can export the full log via the iOS share sheet.

import Foundation
import Observation

// =============================================================================
// MARK: - Enumerations
// =============================================================================

enum DiagLevel: String, Hashable, CaseIterable {
    case info    = "INFO"
    case warning = "WARN"
    case error   = "ERR"
}

enum DiagCategory: String, Hashable, CaseIterable {
    case ble    = "BLE"     // Bluetooth scanning / connection lifecycle
    case obd    = "OBD"     // Raw ELM327 writes and responses
    case parse  = "PARSE"   // OBD response decoding
    case system = "SYS"     // AT init, polling, discovery, app lifecycle
}

// =============================================================================
// MARK: - DiagEvent
// =============================================================================

struct DiagEvent: Identifiable {
    let id        = UUID()
    let timestamp : Date
    let level     : DiagLevel
    let category  : DiagCategory
    let message   : String
    let raw       : String?     // optional hex payload or raw response string

    init(_ level: DiagLevel, _ category: DiagCategory, _ message: String, raw: String? = nil) {
        self.timestamp = Date()
        self.level     = level
        self.category  = category
        self.message   = message
        self.raw       = raw
    }
}

// =============================================================================
// MARK: - DiagnosticsManager
// =============================================================================

@Observable
final class DiagnosticsManager {

    // ── Observable state ──────────────────────────────────────────────────────
    private(set) var events: [DiagEvent] = []

    /// Active category set — events whose category is NOT in this set are hidden.
    var categoryFilter: Set<DiagCategory> = Set(DiagCategory.allCases)

    /// Level filter — nil shows all levels.
    var levelFilter: DiagLevel? = nil

    // ── Configuration ─────────────────────────────────────────────────────────
    private let maxEvents = 1_000   // circular cap; oldest events dropped first

    // ── Derived ───────────────────────────────────────────────────────────────
    var filtered: [DiagEvent] {
        events.filter {
            categoryFilter.contains($0.category) &&
            (levelFilter == nil || $0.level == levelFilter)
        }
    }

    // =========================================================================
    // MARK: - Logging
    // =========================================================================

    func log(_ level: DiagLevel,
             _ category: DiagCategory,
             _ message: String,
             raw: String? = nil) {
        events.append(DiagEvent(level, category, message, raw: raw))
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
    }

    func clear() { events.removeAll() }

    // =========================================================================
    // MARK: - Export
    // =========================================================================

    var exportText: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        var lines: [String] = [
            "WheelBro Diagnostic Log",
            "Exported : \(fmt.string(from: Date()))",
            "Events   : \(events.count)",
            String(repeating: "─", count: 64),
            "",
        ]

        for e in events {
            lines.append(
                "[\(fmt.string(from: e.timestamp))]"
                + " [\(e.level.rawValue)]"
                + " [\(e.category.rawValue)]"
                + " \(e.message)"
            )
            if let r = e.raw {
                lines.append("  RAW: \(r)")
            }
        }

        return lines.joined(separator: "\n")
    }
}
