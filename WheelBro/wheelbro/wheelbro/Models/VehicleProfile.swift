// VehicleProfile.swift
// Describes a supported vehicle and its OBD-II configuration.
// Add entries to `all` to support additional vehicles — no other code changes needed.

import Foundation

struct VehicleProfile: Identifiable, Hashable {

    /// Stable identifier used for UserDefaults persistence.
    let id: String

    /// Display name shown in the vehicle picker.
    let name: String

    /// Usable fuel tank capacity in gallons — used for DTE and TTE calculations.
    let tankGallons: Double

    /// Conservative average fuel economy in MPG — used for DTE calculation.
    let avgMPG: Double

    /// ELM327 ATSP command (including \r terminator) that locks the adapter to
    /// the correct OBD-II physical-layer protocol for this vehicle.
    /// Use "ATSP0\r" for auto-detect on vehicles where ELM327 detection is reliable.
    let obdProtocol: String

    /// Human-readable protocol label used in diagnostic log output.
    let protocolDescription: String

    // =========================================================================
    // MARK: - Supported Vehicles
    // =========================================================================

    /// True when this profile uses ATSP0 auto-detection rather than a fixed protocol.
    var isAutoDetect: Bool { id == "auto_detect" }

    /// Master list — drives the vehicle picker and all profile lookups.
    /// Add new VehicleProfile entries here to expand support.
    static let all: [VehicleProfile] = [
        jeepWranglerJK,
        autoDetect,
    ]

    /// Fallback used when no persisted selection is found.
    static let `default` = jeepWranglerJK

    // ── Jeep Wrangler JK (2011–2018) ─────────────────────────────────────────
    // ATSP0 (auto-detect) stalls indefinitely on this vehicle — the ELM327
    // returns SEARCHING/STOPPED without locking in. ATSP6 sets the protocol
    // explicitly: ISO 15765-4 CAN, 11-bit ID, 500 kbaud.
    static let jeepWranglerJK = VehicleProfile(
        id:                  "jeep_wrangler_jk",
        name:                "Jeep® Wrangler \"JK\"",
        tankGallons:         18.6,
        avgMPG:              15.0,
        obdProtocol:         "ATSP6\r",
        protocolDescription: "ISO 15765-4 CAN, 11-bit ID, 500 kbaud"
    )

    // ── Auto Detect ───────────────────────────────────────────────────────────
    // Uses ATSP0 so the ELM327 probes all protocols automatically.
    // TTE/DTE fall back to generic values (18.6 gal / 15 MPG).
    // A 10-second timeout fires an alert if no protocol is found.
    static let autoDetect = VehicleProfile(
        id:                  "auto_detect",
        name:                "Auto Detect",
        tankGallons:         18.6,
        avgMPG:              15.0,
        obdProtocol:         "ATSP0\r",
        protocolDescription: "Auto Detect (ATSP0)"
    )
}
