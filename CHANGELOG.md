# WheelBro — Changelog

All notable changes to WheelBro are documented here.

---

## [Unreleased]

### Changed
- **Data tab hidden** — `DataView` removed from the tab bar; the file is retained for future use. Tab bar is now four tabs: TTE (0), Bro Cam (2), Settings (3), About (4).
- **Settings tab order** — Simulator section moved below BLE Devices (Vehicle → BLE Devices → Simulator).
- **`SettingsView` — `selectedTab` binding wired up** — `ContentView` now passes `$selectedTab` to `SettingsView`. Tapping a BLE device in the list connects and navigates directly to the TTE tab (`Tab.tte`).

### Added
- **Map tab** — new 2nd-position tab (tag 5) presenting a full-screen satellite map with live location tracking. Features: system blue-dot `UserAnnotation` auto-recentering via `MapCameraPosition.userLocation`; satellite/standard style toggle; two share buttons (Google Maps URL + plain-text coordinates via `ShareLink`); "Location not found" banner with disabled share when GPS is unavailable; tab bar hidden while active; Close button returns to TTE tab. Google Maps URL used in place of `maps.apple.com` — iMessage on macOS hard-codes the Apple Maps domain to a non-interactive card; a `google.com/maps?q=lat,lon` URL renders as a standard clickable hyperlink on all platforms and still offers to open in Maps on iOS.
- **Bro Cam tab** — new centre tab (index 2) with a `camera.aperture` icon. Provides a full-screen camera view with a live telemetry HUD overlaid as a border around the frame. Settings and About shift to tabs 3 and 4.
- **HUD border overlay** — semi-transparent edge strips display live telemetry over the camera preview:
  - *Top bar*: Time to Empty, connection status, speed
  - *Left strip*: Fuel Level, Distance to Empty, Diagnostics (CLEAR / FAULT)
  - *Right strip*: Pitch, Roll, Heading
  - *Bottom bar*: Altitude, Latitude, Longitude
- **Photo capture with HUD compositing** — tapping the shutter button captures a full-resolution photo and composites the HUD image directly onto it before saving to Photos.
- **Video recording with HUD compositing** — tapping the record button starts `AVCaptureVideoDataOutput` + `AVAssetWriter` recording at 720p. The HUD is rendered via `UIGraphicsImageRenderer` at 4 fps and composited onto every video frame using `CIFilter.sourceOverCompositing()` before writing. Audio is captured and muxed into the `.mov` file.
- **Mode toggle** — switches between Photo and Video capture. Disabled while recording.
- **Camera flip** — toggles front/back camera. Disabled while recording.
- **Recording indicator** — blinking red "REC" capsule appears in the top-right corner during video recording.
- **Save status toast** — animated top banner confirms "Saving…", "Saved to Photos", or "Save Failed" after each capture.
- **Camera permission denied view** — if camera access is denied, a full-screen prompt with an "Open iOS Settings" button is shown.
- **`CameraManager`** — new `@Observable` manager owning `AVCaptureSession`, photo output, video data output, audio data output, and `AVAssetWriter`. HUD compositing runs on a dedicated serial write queue; the pixel buffer pool from `AVAssetWriterInputPixelBufferAdaptor` is used for zero-allocation frame output.
- **`HUDValues` struct** — lightweight value bundle passed from `BroCamView` to `CameraManager` at ~4 fps. Decouples the SwiftUI view layer from the video pipeline.
- **`CameraPreviewView`** — `UIViewRepresentable` wrapping `AVCaptureVideoPreviewLayer` via `layerClass` override.
- **`Info.plist`**: `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`
- **GPS location collection** — `LocationManager` wraps `CLLocationManager` and collects latitude, longitude, heading, and altitude continuously in the foreground and background (while app is running). A 10-second timer snapshots values to SwiftData as `LogEntry` rows (key/value/pid pattern, `pid = "GPS"`). Collection is independent of the OBD logging toggle — it starts automatically once location permission is granted.
  - `Info.plist`: `NSLocationWhenInUseUsageDescription`, `NSLocationAlwaysAndWhenInUseUsageDescription`, `UIBackgroundModes → location`
  - `CLLocationManager` settings: `desiredAccuracy = kCLLocationAccuracyBest`, `allowsBackgroundLocationUpdates = true`, `pausesLocationUpdatesAutomatically = false`
  - Uses true heading when calibrated; falls back to magnetic heading
  - New constants: `VehicleConstants.locationLoggingInterval`, `OBDKey.latitude/longitude/heading/altitude`, `OBDLogPID.gps`
- **Pitch / Roll (IMU)** — `MotionManager` wraps `CMMotionManager` and exposes device pitch and roll in degrees at 10 Hz. No permissions required. Pitch positive = nose up (climbing); roll unit label shows Right/Left based on sign.
- **Double-tap screenshot on TTE view** — double-tapping the large TTE countdown captures the full window, plays the system camera shutter sound, triggers a white screen flash, and saves the image to the user's Photo Library.
  - `Info.plist`: `NSPhotoLibraryAddUsageDescription` (add-only; no read access requested)
  - Permission requested at save time via `PHPhotoLibrary.requestAuthorization(for: .addOnly)`; both `.authorized` and `.limited` statuses are accepted
  - Screenshot captured with `UIGraphicsImageRenderer` + `drawHierarchy(afterScreenUpdates: false)` before the flash overlay is applied, so the saved image is clean
  - Shutter sound via `AudioServicesPlaySystemSound(1108)`; respects the device silent switch (iOS-enforced)
  - Flash: `Color.white` overlay animates in over 0.05 s, holds 0.15 s, fades out over 0.3 s
- **TTE view — GPS and IMU cards** — Heading (with cardinal compass point as unit), Altitude (ft), Latitude (N/S), and Longitude (E/W) cards added to the grid. Heading shows `—` before the first GPS fix. Pitch and Roll share a single combined card (see Changed).
- **No-connection overlay on TTE tab** — when BLE is disconnected and Simulator is off, a full-screen overlay with a red indicator appears with two options: "Open Settings" (navigates to the Settings tab) and "Ignore" (dismisses the overlay and stays on TTE). The overlay reappears on the next disconnect after a device has been connected.
- **`AppConstants.verboseLogging`** — single bool constant in `Constants.swift` that gates all console debug output. Set to `false` to silence every `wbLog()` call at zero cost (`@inline(__always)`).
- **`wbLog()` helper** — drop-in replacement for `print()` throughout both manager files. All 38 call sites replaced.
- **About tab** — displays app version, build number, vehicle compatibility, and copyright information. Tab order: TTE (0), Data (1), Settings (2), About (3).
- **`Constants.swift`** — centralised file replacing all magic numbers and string literals with named constants across `BLEConstants`, `VehicleConstants`, `UIConstants`, `AppConstants`, `ATCommand`, `OBDCommand`, `ELM327Response`, `OBDKey`, `OBDLogPID`, `PIDCode`, `DateFormat`, `UserDefaultsKey`, `Tab`, `AppInfo`.
- **PID Discovery (Phase 1 + Phase 2)** — bitmask range queries identify supported PIDs; each discovered PID is then polled for its current value. Export includes `pid`, `description`, and `value` columns.
- **`pid` column in log entries** — `LogEntry.pid` stores the OBD command string that produced each row (e.g. `010C`, `012F`, `ATRV`, `derived`). Included in CSV export header.
- **Disconnect button in Settings** — full-width red button, visible only when a BLE device is connected. Displays the connected device name ("Disconnect from &lt;name&gt;").
- **Clear log after export** — confirmation alert offered when the log export sheet is dismissed.
- **1-second TTE heartbeat** — `.task`-based async loop increments `tickCount` every second, triggering a numeric content transition on the TTE display. Stable across re-renders (not restarted by state changes).

### Added
- **Auto-orientation for Bro Cam** — `CameraManager` registers for `UIDevice.orientationDidChangeNotification` when the session starts and automatically applies the correct `videoRotationAngle` (portrait 90°, landscapeLeft 0°, landscapeRight 180°, portraitUpsideDown 270°) to the `AVCaptureVideoDataOutput` and `AVCapturePhotoOutput` connections and to the `AVCaptureVideoPreviewLayer`. Face-up, face-down, and unknown orientations are ignored. Orientation changes are blocked during recording (asset writer dimensions are fixed for the clip duration). Tracking starts after `session.startRunning()` and is torn down in `stopSession()` and `deinit`.
- **`CaptureManager.captureRotationAngle`** — new observed `CGFloat` property exposed to `BroCamView`; tracks the exact rotation angle independently from the `CaptureOrientation` enum (which only governs asset writer pixel dimensions). `CameraPreviewView` binds to this value so the live preview rotates in sync.

### Changed
- **HUD background panels removed** — the semi-transparent black fills behind all four HUD regions (top bar, bottom bar, left strip, right strip) have been removed from both the SwiftUI live preview and the CoreGraphics compositor used for saved photos and video frames. Telemetry text is rendered directly over the camera image.
- **Orientation flip button hidden** — the portrait ↔ landscape toggle button is no longer shown in the controls bar. `CameraManager.toggleOrientation()` and `applyRotationAngle(_:to:)` are preserved for future use; orientation is now handled automatically by the device orientation observer.
- **`applyOrientation(_:to:)` → `applyRotationAngle(_:to:)`** — helper refactored to accept a raw `CGFloat` angle instead of a `CaptureOrientation` enum value, making it usable for all four device orientations.
- **`CameraConstants` enum** — centralised all magic numbers from `CameraManager.swift` and `BroCamView.swift` (video bitrate, audio sample rate, HUD proportional ratios, capture button dimensions, recording indicator geometry, toast layout, permission view layout, etc.). `VehicleConstants.metersToFeet` replaces the `3.28084` literal previously scattered across three files.
- **Landscape HUD compositor** — `CameraManager.renderHUDImage` now branches on frame dimensions (`w > h`) to render a landscape-specific layout that matches the live SwiftUI `landscapeHUDOverlay` exactly: top bar carries 5 cells (TTE, STATUS, SPEED, PITCH, ROLL); bottom bar carries 4 cells (ALT, LAT, LON, HEADING); left strip (FUEL, DTE, DIAG) is unchanged; right strip is omitted. All cells are inset from the trailing edge by `hudLandscapeControlsRatio` (25% of frame width) to stay clear of the floating controls strip. Portrait compositing is unchanged.
- **HUD font and padding sizing** — `renderHUDImage` now scales fonts and padding from `min(width, height)` instead of frame width. In portrait this is unchanged (min = 720). In landscape it prevents text from being 78% oversized (width was 1280; min is still 720), keeping composited HUD text consistent in size across both orientations.
- **`CameraConstants.hudLandscapeControlsRatio`** — new constant (`0.25`) used by the CoreGraphics HUD compositor to match the proportion of frame width reserved by the floating controls strip in landscape mode.
- **WheelBro logo added to HUD** — a 64 pt logo appears in the bottom bar of the live SwiftUI overlay (trailing element, both portrait and landscape). In saved photos and video the logo is rendered at 128 px and placed above the bottom bar, horizontally centred in the inner camera area (between the side strips in portrait; between the left strip and the controls inset in landscape), avoiding overlap with any telemetry text.
- **Compositor HUD scale** — fonts and logo in saved photos and video are now larger for readability:
  - Top bar, side strips, logo: **×2** (`hudCompositorMainScale = 2.0`)
  - Bottom bar (altitude, lat, lon): **×1.4** (`hudCompositorBottomScale = 1.4`) — full-precision 5-decimal coordinates at ×2 would overflow the 720 px frame width
  - `CameraConstants.hudCompositorMainScale` and `hudCompositorBottomScale` constants added
- **Adaptive strip cell spacing in compositor** — `renderHUDImage` now derives strip cell positions from actual font line heights (`cellGap = (stripHeight − 3 × cellHeight) / 4`) instead of the fixed `h × hudCellSpacingRatio` formula. Prevents cell overlap in landscape at ×2 font size (where the original spacing of 93 px was less than the 108 px cell height).
- **"DIAGNOSTICS" → "DTCs"** — label shortened in both the live SwiftUI HUD overlay and the CoreGraphics compositor (portrait and landscape, left strip).

### Fixed
- **`AVCapturePhotoOutput.isHighResolutionCaptureEnabled` deprecation** — replaced with `maxPhotoDimensions` set from `device.activeFormat.supportedMaxPhotoDimensions.last` (deprecated in iOS 16, required update for iOS 17+ target).

### Fixed (debug pass)
- **`LocationManager` — guard logic for no-fix state** (`logCurrentLocation`): `latitude != 0.0 || longitude != 0.0` used `||`, meaning entries were logged whenever *either* coordinate was non-zero (e.g. valid locations on the equator or prime meridian would pass the wrong branch). Changed to `!(latitude == 0.0 && longitude == 0.0)` so nothing is written until a real GPS fix arrives.
- **`TTEView` — heading guard condition** (`headingText`): guard used `||` and checked `latitude != 0` as a proxy for a GPS fix, which is not reliable (negative latitudes are valid). Replaced with `isAuthorized && !(latitude == 0.0 && longitude == 0.0)` — heading shows `—` until the first real fix.
- **`MotionManager` — double-start guard** (`startUpdates`): calling `startUpdates()` twice registered a second `CMDeviceMotion` update handler while the first remained active, leaking update callbacks and doubling CPU work. Added `guard !cmManager.isDeviceMotionActive` early exit.
- **`ContentView` preview — spurious `LocationManager` override**: the `#Preview` block explicitly injected `.environment(LocationManager())`, overriding the `@State private var locationManager` that `ContentView` already owns and starts. The injected instance was never started, so preview GPS state would always be uninitialized. Removed the redundant injection.
- **`ContentView` — `MotionManager` ran at 10 Hz in the background**: no scene-phase observer existed to pause the IMU when the app was backgrounded. Added `.onChange(of: scenePhase)` — `MotionManager.stopUpdates()` on `.background`, `startUpdates()` on `.active`. `LocationManager` is intentionally left running in the background via the `UIBackgroundModes/location` entitlement.

### Changed
- **Pitch / Roll — combined card** — Pitch and Roll are now displayed in a single grid card side-by-side, separated by a faint yellow divider. Values use a smaller 22pt font with Up/Down and Right/Left labels underneath each reading. Frees one grid slot and reduces vertical scroll length.
- **Screenshot trigger: swipe-down → double-tap TTE** — the screenshot action moved from a swipe-down drag gesture (which caused the ScrollView to rubber-band/bounce) to a double-tap on the large TTE countdown display.
- **TTE logo removed** — the `wheelbro_logo` image between the status banner and TTE display has been hidden to reduce vertical height on the primary screen.
- **Disconnect button repositioned** — moved from a standalone "Connection" section at the bottom of Settings into the top of the BLE Devices section, just above the Scan button and device list. Hidden when no device is connected; the separate Connection section has been removed.
- **OBD protocol: `ATSP0` → `ATSP6`** — hardcoded to ISO 15765-4 CAN, 11-bit ID, 500 kbaud (the correct protocol for Jeep Wrangler JK). `ATSP0` (auto-detect) caused indefinite `SEARCHING…` / `STOPPED` responses on the IOS-Vlink adapter with this vehicle.
- **Response-driven PID polling** — each valid OBD response immediately triggers the next `pollNextPID()` call. The 5-second timer is replaced by a 1.5-second watchdog that fires only when the adapter goes silent (lost packet, `NODATA` without prompt). Cycles through all PIDs as fast as the adapter responds.
- **VIN integrated into poll cycle** — `OBDCommand.requestVIN` added as the 8th entry in `pidSequence`. Eliminates the race condition where a simultaneous one-shot `readVIN()` + `pollNextPID()` caused the ELM327 to drop the multi-frame ISO-TP VIN response.
- **BLE device list shows all peripherals** — device filtering removed; all discovered BLE peripherals are shown, sorted alphabetically. Resolves missing IOS-Vlink entries caused by service-UUID filtering.
- **Split RX/TX BLE characteristics** — `obdCharacteristic` split into `obdNotifyChar` (subscribe, UUIDs: FFE1, 2AF0, FFF1, BEF1, 18F1) and `obdWriteChar` (write, UUIDs: FFE1, 2AF1, FFF1, BEF1, 18F1). Supports both combined (FFE0/FFE1) and split (18F0/2AF0+2AF1) adapter types.
- **Export format: `.csv` → `.txt`** — both log and discovery exports use `.txt` extension.
- **Export delivery: file URL → `NSItemProvider`** — exports now pass content inline via `NSItemProvider(item: csv as NSString, typeIdentifier: "public.plain-text")` with `suggestedName`. Eliminates `NSCocoaErrorDomain Code=256` errors caused by `UIActivityViewController` failing to read sandboxed file URLs.
- **VIN decode: accepts printable ASCII only** — `decodeVINHex` guard changed from `byte > 0` to `byte >= 0x20 && byte < 0x7F`. Vehicles that return all `0xFF` fill bytes for Mode 09 (VIN not stored in OBD-II register) now display "Not available" instead of "ÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿ".
- **Multi-frame VIN parsing** — parser handles single-frame (`490201…`), first-frame (`0:4902…`), and continuation frames (`N:XX…`). ISO-TP byte-count header lines (`014`, `008`, etc.) are silently discarded.
- **`SEARCHING` / `STOPPED` handling** — these ELM327 tokens are now caught before `parseOBDLine` and counted. A diagnostic warning prints once on first occurrence and every 10 cycles thereafter.
- **Copyright / company name** — updated from "WheelBro LLC" to "RCMAZ Software, LLC" throughout all views and the README.
- **Logging default: off** — `isLoggingEnabled` is explicitly written as `false` to `UserDefaults` on first launch. Previously relied on `UserDefaults.bool` returning `false` for an absent key, which was correct but implicit.
- **Immediate first poll on connect** — `startPIDPolling()` calls `pollNextPID()` once before arming the watchdog timer, so live values appear immediately after the AT init sequence completes.

### Fixed
- **SwiftData migration crash** (`NSCocoaErrorDomain Code=134110`) — `LogEntry.pid` changed from `var pid: String` to `var pid: String = ""`. SwiftData's lightweight migration engine uses the property-level default to backfill existing rows; the `init` parameter default is not visible to it.
- **TTE / DTE values stuck at zero** — removed `@State var fuelText: Double?` and `@State var dteText: Double?` snapshot vars. Once set to `Optional(0.0)` on the first tick, the `??` operator never fell through to the live `obdManager` values. Cards now read `obdManager.distanceToEmpty` and `obdManager.fuelLevel` directly.
- **1-second ticker restarting on every re-render** — `Timer.publish(...).autoconnect()` declared as a `struct` property was recreated on every state change, resetting the countdown each tick. Replaced with a `.task` async loop pinned to the view's identity in the hierarchy.
- **PID discovery off-by-one value association** — `processLine`'s value-polling branch now only advances when the response starts with the expected `41XX` prefix for `currentValuePollPID`, or contains `NODATA`/`ERROR`. Stale in-flight Phase 1 responses are silently discarded.
- **Logging timer not starting on BLE connect** — `isConnected` now has `didSet { handleLoggingChange() }` so the timer starts immediately when BLE connects, not only when the logging toggle is flipped.
- **Duplicate `switch` case compiler warning** — removed duplicate `"31"` case in `decodePIDValue`.

---

© 2026 RCMAZ Software, LLC. All Rights Reserved.
