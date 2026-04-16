// Constants.swift
// App-wide named constants replacing magic numbers.
// Grouped by domain so call sites read as self-documenting expressions.

import Foundation

// =============================================================================
// MARK: - BLE / OBD Adapter Timing
// =============================================================================

enum BLEConstants {

    /// Seconds before the BLE scan auto-stops to save battery.
    static let scanTimeout: Double = 10

    /// Watchdog interval (seconds) for normal live-data polling.
    /// Under normal conditions polling is response-driven (each response
    /// immediately triggers the next send). This timer only fires when
    /// the adapter hasn't responded within the window — e.g. NODATA with
    /// no prompt, lost packet — so the cycle doesn't stall.
    static let pidPollInterval: Double = 1.5

    /// Overall safety timeout (seconds) for the full PID discovery sequence
    /// (Phase 1 bitmask queries + Phase 2 per-PID value queries).
    static let discoveryTimeout: Double = 90

    /// Delay (seconds) between consecutive Phase 1 range-support commands.
    static let discoveryCommandDelay: Double = 0.5

    /// Delay (seconds) between consecutive Test OBD commands.
    static let testCommandDelay: Double = 0.3

    /// Per-PID timeout (seconds) in Phase 2: if the vehicle doesn't respond
    /// within this window the PID is skipped and the queue advances.
    static let valuePollTimeout: Double = 1.5

    /// Seconds allowed per candidate protocol during application-level probing.
    /// After sending ATSPn + the test PID (010C), if no valid response arrives
    /// within this window the prober moves on to the next candidate.
    /// 9 protocols × 3 s = 27 s maximum total probing time.
    static let probeTimeoutPerProtocol: Double = 3.0

    /// Number of usable bits in each SAE J1979 Mode 01 PID-support bitmask.
    /// Each 4-byte (32-bit) response encodes bits 1–31 as supported PIDs;
    /// bit 0 (LSB) is the "next range supported" indicator and is skipped.
    static let pidBitmaskBits: Int = 31
}

// =============================================================================
// MARK: - Vehicle / Telemetry
// =============================================================================

enum VehicleConstants {

    /// Seconds between simulated OBD data refreshes.
    static let simulatorUpdateInterval: Double = 5.0

    /// Seconds between log-entry writes when data logging is enabled.
    static let loggingInterval: Double = 10.0

    /// Seconds between GPS snapshots written to the log.
    /// Independent of OBD logging — location is always collected when authorized.
    static let locationLoggingInterval: Double = 10.0

    /// Age threshold (seconds) beyond which log entries are pruned — 1 hour.
    static let logRetentionSeconds: Double = 3_600

    /// Reference speed (mph) used to scale the TTE speed-consumption factor.
    static let tteSpeedRefMPH: Double = 55.0

    /// Reference RPM used to scale the TTE RPM-consumption factor.
    static let tteRPMRef: Double = 2_000.0

    /// Base idle fuel consumption (gallons/hour) for Time-to-Empty calculation.
    static let tteBaseGPH: Double = 1.2

    /// VIN string injected when the simulator is running.
    static let simulatedVIN: String = "1J4BA2D13BL123456"

    /// Conversion factor: metres (GPS) → feet (display).
    static let metersToFeet: Double = 3.28084
}

// =============================================================================
// MARK: - ELM327 AT Initialisation Commands
// =============================================================================

enum ATCommand {
    static let reset          = "ATZ\r"    // Reset chip (~1 s)
    static let echoOff        = "ATE0\r"   // Stop echoing commands
    static let linefeedsOff   = "ATL0\r"   // Suppress linefeed characters
    static let spacesOff      = "ATS0\r"   // Remove spaces from hex responses
    static let headersOff     = "ATH0\r"   // Omit OBD header bytes
    static let adaptiveTiming = "ATAT1\r"  // Adaptive timeout mode 1
    static let batteryVoltage = "ATRV\r"   // Read battery voltage (returns e.g. "12.3V")
}

// =============================================================================
// MARK: - OBD-II Commands  (full ELM327 command strings including \r terminator)
// =============================================================================

enum OBDCommand {
    // Live-data polling (Mode 01)
    static let requestRPM         = "010C\r"
    static let requestSpeed       = "010D\r"
    static let requestFuelLevel   = "012F\r"
    static let requestCoolantTemp = "0105\r"
    static let requestOilTemp     = "015C\r"
    static let requestFaultCodes  = "03\r"    // Mode 03 — stored DTCs
    // Vehicle info (Mode 09)
    static let requestVIN         = "0902\r"  // Mode 09 PID 02 — 17-char VIN
    // PID-support discovery (Mode 01 range queries)
    static let discoverPIDs00     = "0100\r"  // Supported PIDs 01–20
    static let discoverPIDs20     = "0120\r"  // Supported PIDs 21–40
    static let discoverPIDs40     = "0140\r"  // Supported PIDs 41–60
    static let discoverPIDs60     = "0160\r"  // Supported PIDs 61–80
}

// =============================================================================
// MARK: - ELM327 Response Tokens
// =============================================================================

enum ELM327Response {
    static let noData          = "NODATA"
    static let error           = "ERROR"
    static let unableToConnect = "UNABLETOCONNECT"
    /// Emitted while the ELM327 is scanning for the vehicle's OBD protocol.
    /// Indicates the ECU hasn't responded yet — ignition may be off.
    static let searching       = "SEARCHING"
    /// Emitted when the ELM327 gives up protocol detection after timeout.
    /// Treat identically to NODATA — vehicle is not communicating.
    static let stopped         = "STOPPED"
    static let prompt          = ">"           // ELM327 ready prompt
    static let elmPrefix       = "ELM"         // Version banner (e.g. "ELM327 v1.5")
    static let mode01Prefix    = "41"          // Mode 01 response prefix
    static let vinPrefix       = "4902"        // Mode 09 PID 02 response prefix
    static let dtcPrefix       = "43"          // Mode 03 DTC response prefix
    static let battVoltageSuffix = "V"         // AT RV response suffix (e.g. "12.3V")
}

// =============================================================================
// MARK: - OBD Telemetry Keys  (strings forwarded via updateFromOBD / LogEntry)
// =============================================================================

enum OBDKey {
    static let rpm            = "rpm"
    static let speed          = "speed"
    static let fuelLevel      = "fuelLevel"
    static let oilTemp        = "oilTemp"
    static let coolantTemp    = "coolantTemp"
    static let batteryVoltage = "batteryVoltage"
    static let vin            = "vin"
    static let errorCodes     = "errorCodes"
    static let distanceToEmpty = "distanceToEmpty"
    // GPS
    static let latitude       = "latitude"
    static let longitude      = "longitude"
    static let heading        = "heading"
    static let altitude       = "altitude"
}

// =============================================================================
// MARK: - OBD Log PID Labels  (stored in LogEntry.pid; not terminated with \r)
// =============================================================================

enum OBDLogPID {
    static let fuelLevel       = "012F"
    static let speed           = "010D"
    static let rpm             = "010C"
    static let oilTemp         = "015C"
    static let coolantTemp     = "0105"
    static let batteryVoltage  = "ATRV"
    static let distanceToEmpty = "derived"
    static let vin             = "0902"
    static let errorCodes      = "03"
    // GPS — all four location fields share this source label
    static let gps             = "GPS"
}

// =============================================================================
// MARK: - Date / Time Format Strings
// =============================================================================

enum DateFormat {
    static let date     = "yyyy-MM-dd"
    static let time     = "HH:mm:ss"
    static let dateTime = "yyyy-MM-dd HH:mm:ss"
}

// =============================================================================
// MARK: - UserDefaults Keys
// =============================================================================

enum UserDefaultsKey {
    static let isSimulatorOn     = "isSimulatorOn"
    static let isLoggingEnabled  = "isLoggingEnabled"
    static let hasLaunchedBefore = "hasLaunchedBefore"
    static let selectedVehicle   = "selectedVehicle"
}

// =============================================================================
// MARK: - Tab Indices
// =============================================================================

enum Tab {
    static let tte      = 0
    static let data     = 1   // reserved — DataView hidden from tab bar, kept for future use
    static let broCam   = 2   // centre tab — camera
    static let settings = 3
    static let about    = 4
    static let map      = 5   // full-screen map with live location
}

// =============================================================================
// MARK: - App Info
// =============================================================================

enum AppInfo {
    static let copyrightHolder = "© 2026 RCMAZ Software, LLC"
    static let copyrightRights = "All Rights Reserved."
    static let copyrightFull   = "© 2026 RCMAZ Software, LLC. All Rights Reserved."
    static let appDisplayName  = "WheelBro™"
    static let appDisplayDesc  = "OBD-II Data Displays for the fun."
}

// =============================================================================
// MARK: - SAE J1979 Mode 01 PID Hex Codes  (2-char, used after stripping "01" prefix)
// These are the values matched inside decodePIDValue(pidHex:data:).
// =============================================================================

enum PIDCode {
    // ── Single-byte temperature sensors ─────────────────────────────────────
    static let engineCoolantTemp        = "05"  // A − 40 °C
    static let intakeAirTemp            = "0F"  // A − 40 °C
    static let ambientAirTemp           = "46"  // A − 40 °C
    static let engineOilTemp            = "5C"  // A − 40 °C

    // ── Single-byte percentage / load ────────────────────────────────────────
    static let calculatedEngineLoad     = "04"  // A / 2.55 %
    static let throttlePosition         = "11"  // A / 2.55 %
    static let commandedEGR             = "2C"  // A / 2.55 %
    static let commandedEvapPurge       = "2E"  // A / 2.55 %
    static let relativeThrottlePosition = "45"  // A / 2.55 %
    static let commandedThrottleActuator = "4C" // A / 2.55 %
    static let ethanolFuelPercent       = "52"  // A / 2.55 %
    static let relativeAccelPedalPos    = "5A"  // A / 2.55 %
    static let hybridBatteryRemaining   = "5B"  // A / 2.55 %
    static let fuelTankLevel            = "2F"  // A / 2.55 %
    static let absoluteLoad             = "43"  // (A*256+B) / 2.55 %

    // ── Fuel trims (signed %) ────────────────────────────────────────────────
    static let shortTermFuelTrimBank1   = "06"  // (A − 128) × 100 / 128 %
    static let longTermFuelTrimBank1    = "07"
    static let shortTermFuelTrimBank2   = "08"
    static let longTermFuelTrimBank2    = "09"
    static let egrError                 = "2D"  // same formula

    // ── Pressure (single-byte) ───────────────────────────────────────────────
    static let fuelPressureGauge        = "0A"  // A × 3 kPa
    static let intakeManifoldPressure   = "0B"  // A kPa
    static let barometricPressure       = "33"  // A kPa

    // ── Two-byte engine metrics ──────────────────────────────────────────────
    static let engineRPM                = "0C"  // (A*256+B) / 4 RPM
    static let mafAirFlowRate           = "10"  // (A*256+B) / 100 g/s
    static let fuelRailPressureRelative = "22"  // (A*256+B) × 0.079 kPa
    static let controlModuleVoltage     = "42"  // (A*256+B) / 1000 V
    static let commandedAirFuelRatio    = "44"  // (A*256+B) × 0.0000305 λ
    static let engineFuelRate           = "5E"  // (A*256+B) / 20 L/h

    // ── Single-byte speed / timing ───────────────────────────────────────────
    static let vehicleSpeed             = "0D"  // A km/h
    static let timingAdvance            = "0E"  // A/2 − 64 °

    // ── Two-byte pressure (×10 kPa) ─────────────────────────────────────────
    static let fuelRailPressureAbsolute = "23"
    static let fuelRailPressureAbsolute2 = "59"

    // ── Two-byte distance / time counters ────────────────────────────────────
    static let runtimeSinceEngineStart  = "1F"  // A*256+B seconds
    static let distanceSinceCodesCleared = "31" // A*256+B km
    static let distanceTraveledWithMIL  = "21"  // A*256+B km
    static let warmupsSinceCodesCleared = "30"  // A count
    static let timeRunWithMILOn         = "4D"  // A*256+B minutes
    static let timeSinceCodesCleared    = "4E"  // A*256+B minutes

    // ── Catalyst temperatures ────────────────────────────────────────────────
    static let catalystTempBank1Sensor1 = "3C"  // (A*256+B)/10 − 40 °C
    static let catalystTempBank2Sensor1 = "3D"
    static let catalystTempBank1Sensor2 = "3E"
    static let catalystTempBank2Sensor2 = "3F"

    // ── Lookup-table PIDs ────────────────────────────────────────────────────
    static let monitorStatus            = "01"  // bitfield → MIL ON/OFF
    static let obdStandard              = "1C"  // index into standards table
    static let fuelType                 = "51"  // index into fuel-type table
}

// =============================================================================
// MARK: - UI
// =============================================================================

enum UIConstants {

    /// Seconds between TTE / DTE display refresh ticks.
    static let tteTickInterval: Double = 1.0
}

// =============================================================================
// MARK: - Motion / IMU
// =============================================================================

enum MotionConstants {

    /// CMMotionManager device-motion update interval (seconds).
    /// 10 Hz is smooth enough for pitch/roll display without hammering the CPU.
    static let updateInterval: Double = 1.0 / 10.0
}

// =============================================================================
// MARK: - App-Wide Behaviour Flags
// =============================================================================

enum AppConstants {

    /// Master switch for all debug console output.
    /// Set to `false` before shipping to silence every `wbLog` call at zero cost.
    static let verboseLogging: Bool = true
}

// =============================================================================
// MARK: - Bro Cam
// =============================================================================

enum CameraConstants {

    // ── Video pipeline ─────────────────────────────────────────────────────────
    /// H.264 target bitrate (bits/s) for recorded video.
    static let videoBitRate: Int = 4_000_000
    /// Audio sample rate (Hz).
    static let audioSampleRate: Int = 44_100
    /// Mono audio channel count.
    static let audioChannels: Int = 1
    /// JPEG compression quality for saved photos (0–1).
    static let jpegQuality: CGFloat = 0.92
    /// Seconds before the save-status toast is dismissed.
    static let saveStatusResetDelay: Double = 2.0
    /// Interval (seconds) between HUD value pushes to CameraManager (~4 fps).
    static let hudUpdateInterval: Double = 0.25

    // ── HUD proportional layout (fractions of the video frame dimension) ───────
    /// Top/bottom bar height as a fraction of frame height.
    static let hudBarHeightRatio: CGFloat = 0.085
    /// Left/right strip width as a fraction of frame width.
    static let hudSideWidthRatio: CGFloat = 0.30
    /// Inner padding as a fraction of frame width.
    static let hudPadRatio: CGFloat = 0.04
    /// Semi-transparent background alpha for all HUD strips (CoreGraphics + SwiftUI).
    static let hudBgAlpha: CGFloat = 0.62
    /// X position of the STATUS cell as a fraction of frame width.
    static let hudStatusXRatio: CGFloat = 0.38
    /// X position of the LATITUDE cell as a fraction of frame width.
    static let hudLatXRatio: CGFloat = 0.30
    /// X position of the LONGITUDE cell as a fraction of frame width.
    static let hudLonXRatio: CGFloat = 0.63
    /// Vertical spacing between cells in side strips as a fraction of frame height.
    static let hudCellSpacingRatio: CGFloat = 0.13
    /// Y offset of content within the top/bottom bar as a fraction of bar height.
    static let hudBarTopOffsetRatio: CGFloat = 0.08
    /// Key-label font size as a fraction of frame width.
    static let hudKeyFontRatio: CGFloat = 0.022
    /// Value-label font size as a fraction of frame width.
    static let hudValFontRatio: CGFloat = 0.040
    /// Small value-label font size (used for the status cell) as a fraction of frame width.
    static let hudSmlFontRatio: CGFloat = 0.034
    /// Vertical gap (points) between the key string and value string in a cell.
    static let hudKeyValGap: CGFloat = 1.0

    // ── SwiftUI HUD overlay font sizes (points) ────────────────────────────────
    /// Key-label point size in the SwiftUI HUD overlay.
    static let hudKeyFontPt: CGFloat = 9
    /// Value-label point size in the SwiftUI HUD overlay.
    static let hudValFontPt: CGFloat = 13

    // ── SwiftUI HUD overlay dimensions (points) ────────────────────────────────
    /// Width of the left/right telemetry strips.
    static let hudStripWidth: CGFloat = 108
    /// Horizontal padding inside each strip.
    static let hudStripHPad: CGFloat = 10
    /// Vertical padding inside each strip.
    static let hudStripVPad: CGFloat = 14
    /// Spacing between cells inside a strip.
    static let hudStripSpacing: CGFloat = 14
    /// Horizontal padding inside the top/bottom bars.
    static let hudBarHPad: CGFloat = 12
    /// Vertical padding inside the top/bottom bars.
    static let hudBarVPad: CGFloat = 8

    // ── Exit button ────────────────────────────────────────────────────────────
    static let exitButtonSize: CGFloat = 56   // xmark.circle.fill icon diameter

    // ── Capture button ─────────────────────────────────────────────────────────
    static let captureButtonOuter: CGFloat = 72    // outer ring diameter
    static let captureButtonStroke: CGFloat = 3    // outer ring stroke width
    static let shutterInner: CGFloat = 60          // photo mode: solid white inner circle
    static let recordInner: CGFloat = 56           // video idle: red inner circle
    static let stopSquareSize: CGFloat = 28        // video recording: red stop square
    static let stopSquareRadius: CGFloat = 6       // stop square corner radius

    // ── Recording indicator ────────────────────────────────────────────────────
    static let recDotSize: CGFloat = 9
    static let recDotStroke: CGFloat = 1.5
    static let recFontSize: CGFloat = 11
    static let recBlinkDuration: Double = 0.7
    /// Trailing padding for the REC badge — keeps it clear of the right HUD strip.
    static let recTrailingPad: CGFloat = 116

    // ── Controls bar ──────────────────────────────────────────────────────────
    static let controlsVPad: CGFloat = 18
    static let modeToggleDuration: Double = 0.15
    /// Width of the floating controls strip in landscape mode.
    static let landscapeControlsWidth: CGFloat = 88
    /// Fraction of landscape frame width reserved for the floating controls strip
    /// in the CoreGraphics HUD compositor. Matches landscapeControlsWidth relative
    /// to a ~390 pt reference screen width (88 / 390 ≈ 0.23, rounded to 0.25).
    static let hudLandscapeControlsRatio: CGFloat = 0.25
    /// Opacity of the floating controls background (both portrait and landscape).
    static let controlsOverlayAlpha: Double = 0.30

    // ── Save toast ─────────────────────────────────────────────────────────────
    static let toastTopPad: CGFloat = 56
    static let toastHPad: CGFloat = 18
    static let toastVPad: CGFloat = 10
    static let toastIconSpacing: CGFloat = 8
    static let toastBgAlpha: CGFloat = 0.78
    /// Duration of the save-toast fade animation.
    static let toastFadeDuration: Double = 0.2

    // ── Permission denied view ─────────────────────────────────────────────────
    static let permissionIconSize: CGFloat = 52
    static let permissionViewSpacing: CGFloat = 24

    // ── HUD logo ───────────────────────────────────────────────────────────────
    /// Side length (points/pixels) of the WheelBro logo drawn in the HUD.
    static let hudLogoSize: CGFloat = 64

    // ── Compositor scale factors (saved photos & video only) ───────────────────
    /// Scale multiplier applied to top-bar fonts, side-strip fonts, and the logo
    /// in the CoreGraphics compositor. Bottom bar uses a separate, smaller scale
    /// because coordinate values at 2× would overflow the 720-px frame width.
    static let hudCompositorMainScale: CGFloat = 2.0
    /// Scale multiplier applied to bottom-bar fonts in the compositor.
    /// Keeps full-precision coordinates (e.g. "122.33207 W") within frame bounds.
    static let hudCompositorBottomScale: CGFloat = 1.4

    // ── HUD cell (SwiftUI) ─────────────────────────────────────────────────────
    /// Minimum scale factor applied to HUD value labels before they truncate.
    static let hudValMinScale: CGFloat = 0.65
    /// Color(white:) value for the "No Device" status in the HUD.
    static let hudNoDeviceWhite: Double = 0.45
    /// Color(white:) value for the "CLEAR" diagnostics label.
    static let hudDiagClearWhite: Double = 0.40
}

// =============================================================================
// MARK: - Conditional Logging Helper
// =============================================================================

/// Drop-in replacement for `print` gated on `AppConstants.verboseLogging`.
/// All debug output in the app routes through this function so it can be
/// silenced globally by flipping one constant.
@inline(__always)
func wbLog(_ message: String) {
    if AppConstants.verboseLogging { print(message) }
}
