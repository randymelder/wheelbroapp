// BroCamView.swift
// Tab 2 — Bro Cam.
// Full-screen camera with a live HUD border showing all TTE telemetry.
// Supports photo capture and video recording; HUD values are composited
// directly onto every saved photo and video frame.
// Orientation is tracked automatically; controls float at the bottom
// (portrait) or on the right side (landscape) over the camera image.

import SwiftUI
import AVFoundation
import CoreBluetooth

struct BroCamView: View {

    @Binding var selectedTab: Int

    @Environment(OBDDataManager.self)   private var obdManager
    @Environment(BluetoothManager.self) private var bleManager
    @Environment(LocationManager.self)  private var locationManager
    @Environment(MotionManager.self)    private var motionManager

    @State private var cameraManager = CameraManager()
    @State private var recBlink      = false

    private var isLandscape: Bool {
        cameraManager.captureRotationAngle == 0 || cameraManager.captureRotationAngle == 180
    }

    // MARK: - Body
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch cameraManager.cameraAuthStatus {
            case .authorized:
                cameraContent
            case .denied, .restricted:
                permissionDeniedView
            default:
                ProgressView().tint(Color.wheelBroYellow)
            }

            // Exit button — top-left corner, always above all other content
            exitButton
        }
        .ignoresSafeArea()
        // Save-status toast — slides in from the top
        .overlay(alignment: .top) {
            if cameraManager.saveStatus != .idle {
                saveToast
                    .padding(.top, CameraConstants.toastTopPad)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: CameraConstants.toastFadeDuration),
                   value: cameraManager.saveStatus == .idle)
        // Hide the tab bar — camera fills the full display
        .toolbar(.hidden, for: .tabBar)
        // First launch: request permissions and start session
        .task { await cameraManager.setup() }
        // Re-start session when returning to this tab
        .onAppear {
            if cameraManager.cameraAuthStatus == .authorized && !cameraManager.isSessionRunning {
                cameraManager.startSession()
            }
        }
        .onDisappear {
            if cameraManager.isRecording { cameraManager.stopRecording() }
            cameraManager.stopSession()
        }
        // Push live telemetry to CameraManager for HUD compositing at ~4 fps
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(CameraConstants.hudUpdateInterval))
                cameraManager.updateHUD(currentHUDValues)
            }
        }
    }

    // MARK: - Exit Button
    private var exitButton: some View {
        VStack {
            HStack {
                Button {
                    if cameraManager.isRecording { cameraManager.stopRecording() }
                    selectedTab = Tab.tte
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: CameraConstants.exitButtonSize))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.white, Color.black.opacity(0.5))
                }
                .padding(.top, 16)
                .padding(.leading, 20)
                Spacer()
            }
            Spacer()
        }
    }

    // MARK: - Camera Content
    // Camera preview always fills 100% of the display.
    // Controls float as overlays — they never shrink the camera frame.
    @ViewBuilder
    private var cameraContent: some View {
        ZStack {
            CameraPreviewView(session: cameraManager.session,
                              rotationAngle: cameraManager.captureRotationAngle)

            hudOverlay

            if cameraManager.isRecording { recIndicator }
        }
        // Portrait: controls float at the bottom
        .overlay(alignment: .bottom) {
            if !isLandscape { controlsBarPortrait }
        }
        // Landscape: controls float on the right
        .overlay(alignment: .trailing) {
            if isLandscape { controlsBarLandscape }
        }
    }

    // MARK: - HUD Overlay (orientation-aware router)
    @ViewBuilder
    private var hudOverlay: some View {
        if isLandscape {
            landscapeHUDOverlay
        } else {
            portraitHUDOverlay
        }
    }

    // MARK: - Portrait HUD
    // Top bar: TTE | STATUS | SPEED
    // Left strip: FUEL / DTE / DIAG     Right strip: PITCH / ROLL / HEADING
    // Bottom bar: ALT | LAT | LON
    private var portraitHUDOverlay: some View {
        VStack(spacing: 0) {
            // ── Top bar ───────────────────────────────────────────────────
            HStack(alignment: .top, spacing: 0) {
                hudCell(key: "TIME TO EMPTY",
                        val: obdManager.calculateTimeToEmpty(
                            fuelLevel: obdManager.fuelLevel, speed: obdManager.speed,
                            rpm: obdManager.rpm, errorCodes: obdManager.errorCodes))
                Spacer()
                hudCell(key: "STATUS", val: hudStatusLabel, valColor: hudStatusColor)
                Spacer()
                hudCell(key: "SPEED", val: String(format: "%.0f mph", obdManager.speed))
            }
            .padding(.horizontal, CameraConstants.hudBarHPad)
            .padding(.vertical, CameraConstants.hudBarVPad)

            // ── Middle: left strip | clear center | right strip ───────────
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: CameraConstants.hudStripSpacing) {
                    hudCell(key: "FUEL LEVEL",
                            val: String(format: "%.1f%%", obdManager.fuelLevel))
                    hudCell(key: "DIST TO EMPTY",
                            val: String(format: "%.1f mi", obdManager.distanceToEmpty))
                    hudCell(key: "DTCs",
                            val: obdManager.errorCodes == "None" ? "CLEAR" : "FAULT",
                            valColor: obdManager.errorCodes == "None"
                                ? Color(white: CameraConstants.hudDiagClearWhite)
                                : Color.wheelBroRed)
                }
                .frame(width: CameraConstants.hudStripWidth)
                .padding(.horizontal, CameraConstants.hudStripHPad)
                .padding(.vertical, CameraConstants.hudStripVPad)
                .frame(maxHeight: .infinity, alignment: .center)

                Spacer()

                VStack(alignment: .leading, spacing: CameraConstants.hudStripSpacing) {
                    hudCell(key: "PITCH",
                            val: String(format: "%.1f° %@", abs(motionManager.pitch),
                                        motionManager.pitch >= 0 ? "Up" : "Down"))
                    hudCell(key: "ROLL",
                            val: String(format: "%.1f° %@", abs(motionManager.roll),
                                        motionManager.roll  >= 0 ? "R"  : "L"))
                    hudCell(key: "HEADING", val: headingText)
                }
                .frame(width: CameraConstants.hudStripWidth)
                .padding(.horizontal, CameraConstants.hudStripHPad)
                .padding(.vertical, CameraConstants.hudStripVPad)
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(maxHeight: .infinity)

            // ── Bottom bar ────────────────────────────────────────────────
            HStack(alignment: .center, spacing: 0) {
                hudCell(key: "ALTITUDE",
                        val: String(format: "%.0f ft",
                                    locationManager.altitude * VehicleConstants.metersToFeet))
                Spacer()
                hudCell(key: "LATITUDE",
                        val: String(format: "%.5f %@", abs(locationManager.latitude),
                                    locationManager.latitude  >= 0 ? "N" : "S"))
                Spacer()
                hudCell(key: "LONGITUDE",
                        val: String(format: "%.5f %@", abs(locationManager.longitude),
                                    locationManager.longitude >= 0 ? "E" : "W"))
                Spacer()
                Image("wheelbro_logo")
                    .resizable().scaledToFit()
                    .frame(width: CameraConstants.hudLogoSize,
                           height: CameraConstants.hudLogoSize)
            }
            .padding(.horizontal, CameraConstants.hudBarHPad)
            .padding(.vertical, CameraConstants.hudBarVPad)
        }
    }

    // MARK: - Landscape HUD
    // Right strip is omitted — that column is occupied by the floating controls.
    // PITCH, ROLL move to the top bar; HEADING moves to the bottom bar.
    // Leading/trailing padding keeps all text clear of the controls strip.
    private var landscapeHUDOverlay: some View {
        let trailingInset = CameraConstants.landscapeControlsWidth + CameraConstants.hudBarHPad
        return VStack(spacing: 0) {
            // ── Top bar: TTE | STATUS | SPEED | PITCH | ROLL ─────────────
            HStack(alignment: .top, spacing: 0) {
                hudCell(key: "TIME TO EMPTY",
                        val: obdManager.calculateTimeToEmpty(
                            fuelLevel: obdManager.fuelLevel, speed: obdManager.speed,
                            rpm: obdManager.rpm, errorCodes: obdManager.errorCodes))
                Spacer()
                hudCell(key: "STATUS", val: hudStatusLabel, valColor: hudStatusColor)
                Spacer()
                hudCell(key: "SPEED", val: String(format: "%.0f mph", obdManager.speed))
                Spacer()
                hudCell(key: "PITCH",
                        val: String(format: "%.1f° %@", abs(motionManager.pitch),
                                    motionManager.pitch >= 0 ? "Up" : "Down"))
                Spacer()
                hudCell(key: "ROLL",
                        val: String(format: "%.1f° %@", abs(motionManager.roll),
                                    motionManager.roll  >= 0 ? "R"  : "L"))
            }
            .padding(.leading, CameraConstants.hudBarHPad)
            .padding(.trailing, trailingInset)
            .padding(.vertical, CameraConstants.hudBarVPad)

            // ── Middle: left strip only ───────────────────────────────────
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: CameraConstants.hudStripSpacing) {
                    hudCell(key: "FUEL LEVEL",
                            val: String(format: "%.1f%%", obdManager.fuelLevel))
                    hudCell(key: "DIST TO EMPTY",
                            val: String(format: "%.1f mi", obdManager.distanceToEmpty))
                    hudCell(key: "DTCs",
                            val: obdManager.errorCodes == "None" ? "CLEAR" : "FAULT",
                            valColor: obdManager.errorCodes == "None"
                                ? Color(white: CameraConstants.hudDiagClearWhite)
                                : Color.wheelBroRed)
                }
                .frame(width: CameraConstants.hudStripWidth)
                .padding(.horizontal, CameraConstants.hudStripHPad)
                .padding(.vertical, CameraConstants.hudStripVPad)
                .frame(maxHeight: .infinity, alignment: .center)

                Spacer()
            }
            .frame(maxHeight: .infinity)

            // ── Bottom bar: ALT | LAT | LON | HEADING | logo ─────────────
            HStack(alignment: .center, spacing: 0) {
                hudCell(key: "ALTITUDE",
                        val: String(format: "%.0f ft",
                                    locationManager.altitude * VehicleConstants.metersToFeet))
                Spacer()
                hudCell(key: "LATITUDE",
                        val: String(format: "%.5f %@", abs(locationManager.latitude),
                                    locationManager.latitude  >= 0 ? "N" : "S"))
                Spacer()
                hudCell(key: "LONGITUDE",
                        val: String(format: "%.5f %@", abs(locationManager.longitude),
                                    locationManager.longitude >= 0 ? "E" : "W"))
                Spacer()
                hudCell(key: "HEADING", val: headingText)
                Spacer()
                Image("wheelbro_logo")
                    .resizable().scaledToFit()
                    .frame(width: CameraConstants.hudLogoSize,
                           height: CameraConstants.hudLogoSize)
            }
            .padding(.leading, CameraConstants.hudBarHPad)
            .padding(.trailing, trailingInset)
            .padding(.vertical, CameraConstants.hudBarVPad)
        }
    }

    // MARK: - Shared Control Buttons
    private var modeToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: CameraConstants.modeToggleDuration)) {
                cameraManager.captureMode =
                    cameraManager.captureMode == .photo ? .video : .photo
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: cameraManager.captureMode == .photo
                      ? "video.fill" : "camera.fill")
                    .font(.title3)
                Text(cameraManager.captureMode == .photo ? "Video" : "Photo")
                    .font(.caption2)
            }
            .foregroundStyle(Color.wheelBroYellow)
        }
        .disabled(cameraManager.isRecording)
    }

    private var flipCameraButton: some View {
        Button { cameraManager.flipCamera() } label: {
            VStack(spacing: 4) {
                Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                    .font(.title3)
                Text("Flip")
                    .font(.caption2)
            }
            .foregroundStyle(Color.wheelBroYellow)
        }
        .disabled(cameraManager.isRecording)
    }

    // MARK: - Controls Bar — Portrait (floats at the bottom, full width)
    private var controlsBarPortrait: some View {
        HStack(spacing: 0) {
            modeToggleButton.frame(maxWidth: .infinity)
            captureButton.frame(maxWidth: .infinity)
            flipCameraButton.frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, CameraConstants.controlsVPad)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(CameraConstants.controlsOverlayAlpha))
    }

    // MARK: - Controls Bar — Landscape (floats on the right, full height)
    private var controlsBarLandscape: some View {
        VStack(spacing: 0) {
            modeToggleButton.frame(maxHeight: .infinity)
            captureButton.frame(maxHeight: .infinity)
            flipCameraButton.frame(maxHeight: .infinity)
        }
        .padding(.horizontal, CameraConstants.hudBarHPad)
        .padding(.vertical, 20)
        .frame(width: CameraConstants.landscapeControlsWidth)
        .frame(maxHeight: .infinity)
        .background(.black.opacity(CameraConstants.controlsOverlayAlpha))
    }

    // MARK: - Capture Button
    private var captureButton: some View {
        Button {
            switch cameraManager.captureMode {
            case .photo:
                cameraManager.capturePhoto()
            case .video:
                if cameraManager.isRecording { cameraManager.stopRecording() }
                else { cameraManager.startRecording() }
            }
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: CameraConstants.captureButtonStroke)
                    .frame(width: CameraConstants.captureButtonOuter,
                           height: CameraConstants.captureButtonOuter)

                if cameraManager.captureMode == .photo {
                    Circle()
                        .fill(Color.white)
                        .frame(width: CameraConstants.shutterInner,
                               height: CameraConstants.shutterInner)
                } else if cameraManager.isRecording {
                    RoundedRectangle(cornerRadius: CameraConstants.stopSquareRadius,
                                     style: .continuous)
                        .fill(Color.wheelBroRed)
                        .frame(width: CameraConstants.stopSquareSize,
                               height: CameraConstants.stopSquareSize)
                } else {
                    Circle()
                        .fill(Color.wheelBroRed)
                        .frame(width: CameraConstants.recordInner,
                               height: CameraConstants.recordInner)
                }
            }
        }
    }

    // MARK: - Recording Indicator
    private var recIndicator: some View {
        // In landscape the right edge is taken by the controls strip, so offset by its width.
        // In portrait the right HUD strip (recTrailingPad) is the clearance target.
        let trailingPad: CGFloat = isLandscape
            ? CameraConstants.landscapeControlsWidth + CameraConstants.hudBarHPad
            : CameraConstants.recTrailingPad

        return VStack {
            HStack {
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(recBlink ? Color.wheelBroRed : Color.clear)
                        .frame(width: CameraConstants.recDotSize,
                               height: CameraConstants.recDotSize)
                        .overlay(Circle().stroke(Color.wheelBroRed,
                                                 lineWidth: CameraConstants.recDotStroke))
                    Text("REC")
                        .font(.system(size: CameraConstants.recFontSize,
                                      weight: .bold,
                                      design: .monospaced))
                        .foregroundStyle(Color.wheelBroRed)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.black.opacity(0.65))
                .clipShape(Capsule())
                .padding(.top, 10)
                .padding(.trailing, trailingPad)
            }
            Spacer()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: CameraConstants.recBlinkDuration)
                            .repeatForever(autoreverses: true)) {
                recBlink = true
            }
        }
        .onDisappear { recBlink = false }
    }

    // MARK: - Save Toast
    private var saveToast: some View {
        HStack(spacing: CameraConstants.toastIconSpacing) {
            Image(systemName: cameraManager.saveStatus == .saved  ? "checkmark.circle.fill" :
                              cameraManager.saveStatus == .saving ? "arrow.up.circle"        :
                                                                    "xmark.circle.fill")
                .foregroundStyle(cameraManager.saveStatus == .saved  ? Color.green :
                                 cameraManager.saveStatus == .saving ? Color.wheelBroYellow :
                                                                       Color.wheelBroRed)
            Text(cameraManager.saveStatus == .saved  ? "Saved to Photos" :
                 cameraManager.saveStatus == .saving ? "Saving…"         :
                                                       "Save Failed")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, CameraConstants.toastHPad)
        .padding(.vertical, CameraConstants.toastVPad)
        .background(.black.opacity(CameraConstants.toastBgAlpha))
        .clipShape(Capsule())
    }

    // MARK: - Permission Denied
    private var permissionDeniedView: some View {
        VStack(spacing: CameraConstants.permissionViewSpacing) {
            Image(systemName: "camera.fill.badge.ellipsis")
                .font(.system(size: CameraConstants.permissionIconSize))
                .foregroundStyle(Color.wheelBroYellow)

            Text("Camera Access Required")
                .font(.title2).fontWeight(.bold).foregroundStyle(.white)

            Text("Enable camera access in iOS Settings\nto use Bro Cam.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Open iOS Settings", systemImage: "gearshape.fill")
                    .font(.headline).foregroundStyle(.black)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.wheelBroYellow)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, 40)
        }
    }

    // MARK: - HUD Cell
    @ViewBuilder
    private func hudCell(key: String, val: String,
                         keyColor: Color = Color.wheelBroYellow,
                         valColor: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(key)
                .font(.system(size: CameraConstants.hudKeyFontPt,
                              weight: .regular, design: .monospaced))
                .foregroundStyle(keyColor)
                .lineLimit(1)
            Text(val)
                .font(.system(size: CameraConstants.hudValFontPt,
                              weight: .bold, design: .monospaced))
                .foregroundStyle(valColor)
                .lineLimit(1)
                .minimumScaleFactor(CameraConstants.hudValMinScale)
        }
    }

    // MARK: - HUD Helpers
    private var hudStatusLabel: String {
        if obdManager.isSimulatorOn { return "Simulator" }
        if bleManager.isConnected, let name = bleManager.connectedPeripheral?.name { return name }
        return "No Device"
    }

    private var hudStatusColor: Color {
        if obdManager.isSimulatorOn { return Color.wheelBroYellow }
        if bleManager.isConnected   { return .green }
        return Color(white: CameraConstants.hudNoDeviceWhite)
    }

    private var headingText: String {
        guard locationManager.isAuthorized,
              !(locationManager.latitude == 0 && locationManager.longitude == 0) else { return "—" }
        let h = locationManager.heading
        let point: String
        switch h {
        case 337.5..<360, 0..<22.5: point = "N"
        case 22.5..<67.5:           point = "NE"
        case 67.5..<112.5:          point = "E"
        case 112.5..<157.5:         point = "SE"
        case 157.5..<202.5:         point = "S"
        case 202.5..<247.5:         point = "SW"
        case 247.5..<292.5:         point = "W"
        case 292.5..<337.5:         point = "NW"
        default:                     point = ""
        }
        return String(format: "%.0f° %@", h, point)
    }

    private var currentHUDValues: HUDValues {
        HUDValues(
            tte:         obdManager.calculateTimeToEmpty(
                            fuelLevel: obdManager.fuelLevel, speed: obdManager.speed,
                            rpm: obdManager.rpm, errorCodes: obdManager.errorCodes),
            speed:       obdManager.speed,
            fuelLevel:   obdManager.fuelLevel,
            dte:         obdManager.distanceToEmpty,
            pitch:       motionManager.pitch,
            roll:        motionManager.roll,
            heading:     locationManager.heading,
            altitude:    locationManager.altitude,
            latitude:    locationManager.latitude,
            longitude:   locationManager.longitude,
            statusLabel: hudStatusLabel,
            hasDTC:      obdManager.errorCodes != "None"
        )
    }
}

// MARK: - Camera Preview (UIViewRepresentable)
struct CameraPreviewView: UIViewRepresentable {
    let session:       AVCaptureSession
    var rotationAngle: CGFloat          // 90 = portrait, 0/180 = landscape variants

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session      = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        // Sync the preview layer orientation with the current device orientation.
        // Called on every SwiftUI re-render, so this is always up-to-date.
        if let conn = uiView.previewLayer.connection,
           conn.isVideoRotationAngleSupported(rotationAngle) {
            conn.videoRotationAngle = rotationAngle
        }
    }

    class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

// MARK: - Preview
#Preview {
    BroCamView(selectedTab: .constant(Tab.broCam))
        .environment(OBDDataManager())
        .environment(BluetoothManager())
        .environment(LocationManager())
        .environment(MotionManager())
}
