// CameraManager.swift
// Owns the AVCaptureSession for BroCam.
// Supports photo capture and video recording with HUD values composited
// onto every frame using AVCaptureVideoDataOutput + AVAssetWriter + CoreImage.

import AVFoundation
import Photos
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

// ── Value bundle passed from BroCamView at ~4 fps ────────────────────────────
struct HUDValues {
    var tte:         String = "—"
    var speed:       Double = 0
    var fuelLevel:   Double = 0
    var dte:         Double = 0
    var pitch:       Double = 0
    var roll:        Double = 0
    var heading:     Double = 0
    var altitude:    Double = 0
    var latitude:    Double = 0
    var longitude:   Double = 0
    var statusLabel: String = ""
    var hasDTC:      Bool   = false
}

@Observable
final class CameraManager: NSObject {

    // MARK: - Observed State
    var isSessionRunning      = false
    var isRecording           = false
    var captureMode: CaptureMode = .photo
    var captureOrientation: CaptureOrientation = .portrait
    /// Actual rotation angle applied to the capture connection and preview layer.
    /// Tracks device orientation and distinguishes landscapeLeft (0°) from landscapeRight (180°).
    var captureRotationAngle: CGFloat = 90
    var cameraPosition: AVCaptureDevice.Position = .back
    var flashMode: AVCaptureDevice.FlashMode = .auto
    var saveStatus: SaveStatus = .idle
    var cameraAuthStatus: AVAuthorizationStatus = .notDetermined

    enum CaptureMode { case photo, video }
    enum SaveStatus   { case idle, saving, saved, failed }

    enum CaptureOrientation {
        case portrait, landscape

        /// Rotation angle for AVCaptureConnection.videoRotationAngle (iOS 17+)
        var rotationAngle: CGFloat { self == .portrait ? 90 : 0 }

        /// Pixel buffer dimensions the video pipeline delivers at this orientation
        var videoSize: (w: Int, h: Int) { self == .portrait ? (720, 1280) : (1280, 720) }

        /// HUD image size to match the video frame
        var hudSize: CGSize { CGSize(width: CGFloat(videoSize.w), height: CGFloat(videoSize.h)) }
    }

    // MARK: - Session
    let session              = AVCaptureSession()
    private var videoInput:  AVCaptureDeviceInput?
    private let photoOutput  = AVCapturePhotoOutput()
    private let videoOut     = AVCaptureVideoDataOutput()
    private let audioOut     = AVCaptureAudioDataOutput()
    private let sessionQ     = DispatchQueue(label: "com.wheelbro.cam.session", qos: .userInitiated)
    private let writeQ       = DispatchQueue(label: "com.wheelbro.cam.write",   qos: .userInitiated)

    // MARK: - Asset Writer
    private var assetWriter:          AVAssetWriter?
    private var videoInput_w:         AVAssetWriterInput?
    private var audioInput_w:         AVAssetWriterInput?
    private var pixelAdaptor:         AVAssetWriterInputPixelBufferAdaptor?
    private var outputURL:            URL?
    // Both flags are only read/written on writeQ — no additional lock needed.
    private var isActuallyRecording   = false
    private var writerSessionStarted  = false

    // MARK: - HUD
    private let hudQ          = DispatchQueue(label: "com.wheelbro.cam.hud")
    private var _hudImage:    CGImage?
    private let ciCtx         = CIContext(options: [.useSoftwareRenderer: false])

    /// Called from the main thread at ~4 fps. Renders and caches the HUD image.
    func updateHUD(_ values: HUDValues) {
        let size = captureOrientation.hudSize
        hudQ.async { [weak self] in
            self?._hudImage = CameraManager.renderHUDImage(values: values, size: size)
        }
    }

    private func getHUDImage() -> CGImage? { hudQ.sync { _hudImage } }

    // MARK: - Permissions + Setup
    func setup() async {
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        await MainActor.run { cameraAuthStatus = status }
        if status == .authorized { startSession() }
    }

    // MARK: - Session Lifecycle
    func startSession() {
        sessionQ.async { [weak self] in
            guard let self else { return }
            self.configure()
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async {
                self.isSessionRunning = true
                self.beginOrientationTracking()
            }
        }
    }

    func stopSession() {
        stopOrientationTracking()
        sessionQ.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async { self.isSessionRunning = false }
        }
    }

    deinit {
        stopOrientationTracking()
    }

    private func configure() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720
        session.inputs.forEach  { session.removeInput($0)  }
        session.outputs.forEach { session.removeOutput($0) }

        // Video input
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition),
           let input  = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
            videoInput = input
        }
        // Audio input
        if let mic = AVCaptureDevice.default(for: .audio),
           let inp  = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(inp) {
            session.addInput(inp)
        }
        // Photo output
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            if let device = videoInput?.device,
               let maxDims = device.activeFormat.supportedMaxPhotoDimensions.last {
                photoOutput.maxPhotoDimensions = maxDims
            }
        }
        // Video data output (used for HUD compositing during recording)
        videoOut.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOut.alwaysDiscardsLateVideoFrames = true
        videoOut.setSampleBufferDelegate(self, queue: writeQ)
        if session.canAddOutput(videoOut) {
            session.addOutput(videoOut)
            applyRotationAngle(captureRotationAngle, to: videoOut.connection(with: .video))
        }
        // Audio data output
        audioOut.setSampleBufferDelegate(self, queue: writeQ)
        if session.canAddOutput(audioOut) { session.addOutput(audioOut) }

        session.commitConfiguration()
    }

    // MARK: - Flip Camera
    func flipCamera() {
        cameraPosition = (cameraPosition == .back) ? .front : .back
        sessionQ.async { [weak self] in self?.configure() }
    }

    // MARK: - Orientation Toggle (manual — UI hidden; auto-orientation is active)
    /// Switches between portrait and landscape capture. Disabled during recording
    /// because the asset writer dimensions are fixed for the duration of a clip.
    func toggleOrientation() {
        guard !isRecording else { return }
        captureOrientation = (captureOrientation == .portrait) ? .landscape : .portrait
        captureRotationAngle = captureOrientation.rotationAngle
        sessionQ.async { [weak self] in
            guard let self else { return }
            self.applyRotationAngle(self.captureRotationAngle, to: self.videoOut.connection(with: .video))
            self.applyRotationAngle(self.captureRotationAngle, to: self.photoOutput.connection(with: .video))
        }
    }

    private func applyRotationAngle(_ angle: CGFloat, to connection: AVCaptureConnection?) {
        guard let conn = connection else { return }
        if conn.isVideoRotationAngleSupported(angle) {
            conn.videoRotationAngle = angle
        }
    }

    // MARK: - Device Orientation Tracking
    private func beginOrientationTracking() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeviceOrientationChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
        applyDeviceOrientation(UIDevice.current.orientation)
    }

    func stopOrientationTracking() {
        NotificationCenter.default.removeObserver(self,
            name: UIDevice.orientationDidChangeNotification, object: nil)
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    @objc private func handleDeviceOrientationChange() {
        applyDeviceOrientation(UIDevice.current.orientation)
    }

    /// Maps a UIDeviceOrientation to a capture rotation angle and updates connections.
    /// No-op during recording — asset writer dimensions are fixed for the clip.
    private func applyDeviceOrientation(_ deviceOrientation: UIDeviceOrientation) {
        guard !isRecording else { return }
        let angle: CGFloat
        switch deviceOrientation {
        case .portrait:           angle = 90
        case .landscapeLeft:      angle = 0    // home button / USB on right
        case .landscapeRight:     angle = 180  // home button / USB on left
        case .portraitUpsideDown: angle = 270
        default: return                        // faceUp, faceDown, unknown — ignore
        }
        let newOrientation: CaptureOrientation = deviceOrientation.isLandscape ? .landscape : .portrait
        // Update connections first, then reflect in observed state so SwiftUI
        // re-renders the preview after the pipeline is already correct.
        sessionQ.async { [weak self] in
            guard let self else { return }
            self.applyRotationAngle(angle, to: self.videoOut.connection(with: .video))
            self.applyRotationAngle(angle, to: self.photoOutput.connection(with: .video))
            DispatchQueue.main.async { [weak self] in
                self?.captureRotationAngle = angle
                self?.captureOrientation   = newOrientation
            }
        }
    }

    // MARK: - Photo Capture
    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        settings.flashMode = flashMode
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    // MARK: - Video Recording
    func startRecording() {
        guard !isRecording else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mov")
        outputURL = url

        guard let w = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return }

        let vSize = captureOrientation.videoSize
        let vSettings: [String: Any] = [
            AVVideoCodecKey:  AVVideoCodecType.h264,
            AVVideoWidthKey:  vSize.w,
            AVVideoHeightKey: vSize.h,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: CameraConstants.videoBitRate]
        ]
        let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: vSettings)
        vIn.expectsMediaDataInRealTime = true
        let adp = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: vIn,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey  as String: vSize.w,
                kCVPixelBufferHeightKey as String: vSize.h
            ]
        )
        var acl = AudioChannelLayout(); acl.mChannelLayoutTag = kAudioChannelLayoutTag_Mono
        let aSettings: [String: Any] = [
            AVFormatIDKey:           kAudioFormatMPEG4AAC,
            AVSampleRateKey:         CameraConstants.audioSampleRate,
            AVNumberOfChannelsKey:   CameraConstants.audioChannels,
            AVChannelLayoutKey:      Data(bytes: &acl, count: MemoryLayout<AudioChannelLayout>.size)
        ]
        let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: aSettings)
        aIn.expectsMediaDataInRealTime = true

        if w.canAdd(vIn) { w.add(vIn) }
        if w.canAdd(aIn) { w.add(aIn) }
        assetWriter  = w
        videoInput_w = vIn
        audioInput_w = aIn
        pixelAdaptor = adp
        w.startWriting()

        // Arm the write flag on writeQ so captureOutput picks it up atomically
        writeQ.async { [weak self] in
            self?.isActuallyRecording  = true
            self?.writerSessionStarted = false
        }
        DispatchQueue.main.async { self.isRecording = true }
    }

    func stopRecording() {
        guard isRecording else { return }
        DispatchQueue.main.async { self.isRecording = false }

        // All mutations to assetWriter happen on writeQ for thread safety
        writeQ.async { [weak self] in
            guard let self else { return }
            self.isActuallyRecording = false
            self.videoInput_w?.markAsFinished()
            self.audioInput_w?.markAsFinished()
            self.assetWriter?.finishWriting { [weak self] in
                guard let self, let url = self.outputURL else { return }
                self.saveVideo(url: url)
            }
        }
    }

    // MARK: - Composite HUD onto video frame
    private func compositeAndAppend(pixelBuffer: CVPixelBuffer, at time: CMTime) {
        guard let adp = pixelAdaptor, adp.assetWriterInput.isReadyForMoreMediaData else { return }

        let frameCI = CIImage(cvPixelBuffer: pixelBuffer)
        let extent  = frameCI.extent

        var outBuffer: CVPixelBuffer?
        if let pool = adp.pixelBufferPool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outBuffer)
        }
        guard let out = outBuffer else { adp.append(pixelBuffer, withPresentationTime: time); return }

        if let hud = getHUDImage() {
            let scaled = CIImage(cgImage: hud).transformed(by: CGAffineTransform(
                scaleX: extent.width  / CGFloat(hud.width),
                y:      extent.height / CGFloat(hud.height)
            ))
            let composite = CIFilter.sourceOverCompositing()
            composite.inputImage      = scaled
            composite.backgroundImage = frameCI
            ciCtx.render(composite.outputImage ?? frameCI, to: out)
        } else {
            ciCtx.render(frameCI, to: out)
        }
        adp.append(out, withPresentationTime: time)
    }

    // MARK: - Save Helpers
    private func saveVideo(url: URL) {
        DispatchQueue.main.async { self.saveStatus = .saving }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { self?.saveStatus = .failed }; return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset()
                    .addResource(with: .video, fileURL: url, options: nil)
            } completionHandler: { [weak self] ok, _ in
                try? FileManager.default.removeItem(at: url)
                DispatchQueue.main.async {
                    self?.saveStatus = ok ? .saved : .failed
                    DispatchQueue.main.asyncAfter(deadline: .now() + CameraConstants.saveStatusResetDelay) { self?.saveStatus = .idle }
                }
            }
        }
    }

    private func savePhoto(_ image: UIImage) {
        DispatchQueue.main.async { self.saveStatus = .saving }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { self?.saveStatus = .failed }; return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset()
                    .addResource(with: .photo, data: image.jpegData(compressionQuality: CameraConstants.jpegQuality) ?? Data(), options: nil)
            } completionHandler: { [weak self] ok, _ in
                DispatchQueue.main.async {
                    self?.saveStatus = ok ? .saved : .failed
                    DispatchQueue.main.asyncAfter(deadline: .now() + CameraConstants.saveStatusResetDelay) { self?.saveStatus = .idle }
                }
            }
        }
    }

    // MARK: - HUD Image Renderer (CoreGraphics — no SwiftUI dependencies)
    // Renders portrait (720×1280) and landscape (1280×720) layouts independently.
    //
    // Scale strategy for saved files:
    //   • Top bar, side strips, logo → ×2 (hudCompositorMainScale)
    //   • Bottom bar                 → ×1.4 (hudCompositorBottomScale)
    //     Full-precision coordinates at ×2 would overflow the 720-px frame width.
    //
    // Logo is placed above the bottom bar, centered in the inner camera area
    // (between the side strips / controls inset) so it never overlaps HUD text.
    static func renderHUDImage(values: HUDValues, size: CGSize) -> CGImage? {
        let fmt    = UIGraphicsImageRendererFormat()
        fmt.scale  = 1.0
        fmt.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: fmt)

        let image = renderer.image { _ in
            let w = size.width, h = size.height
            let isLandscape = w > h

            // Reference dimension — same in both orientations (720 px).
            let ref   = min(w, h)

            // Scale factors
            let mS = CameraConstants.hudCompositorMainScale    // 2.0
            let bS = CameraConstants.hudCompositorBottomScale  // 1.4

            // Bar height uses main scale so 2× top-bar cells fit.
            let barH  = h * CameraConstants.hudBarHeightRatio * mS
            let sideW = w * CameraConstants.hudSideWidthRatio
            let pad   = ref * CameraConstants.hudPadRatio * mS  // 2× pad

            // ── Fonts ──────────────────────────────────────────────────────
            // Main (2×): top bar, side strips
            let mKeyF = UIFont.monospacedSystemFont(ofSize: ref * CameraConstants.hudKeyFontRatio * mS, weight: .regular)
            let mValF = UIFont.monospacedSystemFont(ofSize: ref * CameraConstants.hudValFontRatio * mS, weight: .bold)
            let mSmlF = UIFont.monospacedSystemFont(ofSize: ref * CameraConstants.hudSmlFontRatio * mS, weight: .bold)
            // Bottom (1.4×): bottom bar only
            let bKeyF = UIFont.monospacedSystemFont(ofSize: ref * CameraConstants.hudKeyFontRatio * bS, weight: .regular)
            let bValF = UIFont.monospacedSystemFont(ofSize: ref * CameraConstants.hudValFontRatio * bS, weight: .bold)

            // ── Colors ─────────────────────────────────────────────────────
            let yellow    = UIColor(red: 1.0, green: 0.80, blue: 0.0, alpha: 1)
            let white     = UIColor.white
            let red       = UIColor(red: 1, green: 0.25, blue: 0.25, alpha: 1)
            let secondary = UIColor(white: 0.55, alpha: 1)

            // ── Cell drawing helper (explicit font pair) ───────────────────
            func cell(key: String, val: String, at pt: CGPoint,
                      keyColor: UIColor = yellow, valColor: UIColor = white,
                      kf: UIFont, vf: UIFont) {
                let kAttrs: [NSAttributedString.Key: Any] = [.font: kf, .foregroundColor: keyColor]
                let vAttrs: [NSAttributedString.Key: Any] = [.font: vf, .foregroundColor: valColor]
                NSAttributedString(string: key, attributes: kAttrs).draw(at: pt)
                let keyH = (key as NSString).size(withAttributes: kAttrs).height
                NSAttributedString(string: " " + val, attributes: vAttrs)
                    .draw(at: CGPoint(x: pt.x, y: pt.y + keyH + CameraConstants.hudKeyValGap))
            }

            // ── Shared derived values ──────────────────────────────────────
            let statusColor: UIColor = values.statusLabel.contains("Sim") ? yellow
                : (values.statusLabel.contains("Connected") ? .green : secondary)
            let dtcColor: UIColor = values.hasDTC ? red : UIColor(white: 0.35, alpha: 1)

            let tY = barH * CameraConstants.hudBarTopOffsetRatio
            let bY = h - barH + barH * CameraConstants.hudBarTopOffsetRatio

            // ── Logo ───────────────────────────────────────────────────────
            // Sized at 2× (128 px), placed above the bottom bar and centred
            // horizontally in the inner camera area (clear of all strips).
            let logo     = UIImage(named: "wheelbro_logo")
            let logoSize = CameraConstants.hudLogoSize * mS        // 128 px
            let logoTopY = h - barH - logoSize - pad / 4

            // ── Adaptive strip cell positions ──────────────────────────────
            // Derive spacing from available height so 2× cells never overlap
            // regardless of orientation.
            let stripCellH = mKeyF.lineHeight + CameraConstants.hudKeyValGap + mValF.lineHeight
            let stripTop   = barH
            let stripBot   = h - barH
            let cellGap    = max(4, (stripBot - stripTop - 3 * stripCellH) / 4)
            let strip1Y    = stripTop + cellGap
            let strip2Y    = strip1Y + stripCellH + cellGap
            let strip3Y    = strip2Y + stripCellH + cellGap

            if isLandscape {
                // ── Landscape layout ─────────────────────────────────────────
                let controlsInset = w * CameraConstants.hudLandscapeControlsRatio
                let usableW       = w - controlsInset

                // Top bar: TTE | STATUS | SPEED | PITCH | ROLL
                let col5 = usableW / 5
                cell(key: "TIME TO EMPTY", val: values.tte,                                                                            at: CGPoint(x: pad,            y: tY), kf: mKeyF, vf: mValF)
                cell(key: "STATUS",        val: values.statusLabel,                                                                    at: CGPoint(x: col5 + pad,     y: tY), keyColor: statusColor, valColor: statusColor, kf: mKeyF, vf: mSmlF)
                cell(key: "SPEED",         val: String(format: "%.0f mph", values.speed),                                             at: CGPoint(x: col5 * 2 + pad, y: tY), kf: mKeyF, vf: mValF)
                cell(key: "PITCH",         val: String(format: "%.1f° %@", abs(values.pitch), values.pitch >= 0 ? "Up" : "Down"),      at: CGPoint(x: col5 * 3 + pad, y: tY), kf: mKeyF, vf: mValF)
                cell(key: "ROLL",          val: String(format: "%.1f° %@", abs(values.roll),  values.roll  >= 0 ? "Right" : "Left"),   at: CGPoint(x: col5 * 4 + pad, y: tY), kf: mKeyF, vf: mValF)

                // Bottom bar (1.4×): ALT | LAT | LON | HEADING
                let col4 = usableW / 4
                cell(key: "ALTITUDE",  val: String(format: "%.0f ft",   values.altitude * VehicleConstants.metersToFeet),             at: CGPoint(x: pad,            y: bY), kf: bKeyF, vf: bValF)
                cell(key: "LATITUDE",  val: String(format: "%.5f %@",   abs(values.latitude),  values.latitude  >= 0 ? "N" : "S"),    at: CGPoint(x: col4 + pad,     y: bY), kf: bKeyF, vf: bValF)
                cell(key: "LONGITUDE", val: String(format: "%.5f %@",   abs(values.longitude), values.longitude >= 0 ? "E" : "W"),    at: CGPoint(x: col4 * 2 + pad, y: bY), kf: bKeyF, vf: bValF)
                cell(key: "HEADING",   val: compassLabel(values.heading),                                                             at: CGPoint(x: col4 * 3 + pad, y: bY), kf: bKeyF, vf: bValF)

                // Logo: above bottom bar, centred in usable area (right of left strip)
                let logoX = (sideW + usableW) / 2 - logoSize / 2
                logo?.draw(in: CGRect(x: logoX, y: logoTopY, width: logoSize, height: logoSize))

                // Left strip (2×): FUEL | DTE | DTCs
                cell(key: "FUEL LEVEL",    val: String(format: "%.1f%%",  values.fuelLevel), at: CGPoint(x: pad, y: strip1Y), kf: mKeyF, vf: mValF)
                cell(key: "DIST TO EMPTY", val: String(format: "%.1f mi", values.dte),        at: CGPoint(x: pad, y: strip2Y), kf: mKeyF, vf: mValF)
                cell(key: "DTCs",          val: values.hasDTC ? "FAULT" : "CLEAR",            at: CGPoint(x: pad, y: strip3Y), valColor: dtcColor, kf: mKeyF, vf: mValF)

            } else {
                // ── Portrait layout ───────────────────────────────────────────
                // Top bar: TTE | STATUS | SPEED
                cell(key: "TIME TO EMPTY", val: values.tte,                                                                            at: CGPoint(x: pad,                              y: tY), kf: mKeyF, vf: mValF)
                cell(key: "STATUS",        val: values.statusLabel,                                                                    at: CGPoint(x: w * CameraConstants.hudStatusXRatio, y: tY), keyColor: statusColor, valColor: statusColor, kf: mKeyF, vf: mSmlF)
                cell(key: "SPEED",         val: String(format: "%.0f mph", values.speed),                                             at: CGPoint(x: w - sideW + pad,                  y: tY), kf: mKeyF, vf: mValF)

                // Bottom bar (1.4×): ALT | LAT | LON
                cell(key: "ALTITUDE",  val: String(format: "%.0f ft",  values.altitude * VehicleConstants.metersToFeet),              at: CGPoint(x: pad,                              y: bY), kf: bKeyF, vf: bValF)
                cell(key: "LATITUDE",  val: String(format: "%.5f %@",  abs(values.latitude),  values.latitude  >= 0 ? "N" : "S"),     at: CGPoint(x: w * CameraConstants.hudLatXRatio, y: bY), kf: bKeyF, vf: bValF)
                cell(key: "LONGITUDE", val: String(format: "%.5f %@",  abs(values.longitude), values.longitude >= 0 ? "E" : "W"),     at: CGPoint(x: w * CameraConstants.hudLonXRatio, y: bY), kf: bKeyF, vf: bValF)

                // Logo: above bottom bar, centred between the two side strips
                let logoX = w / 2 - logoSize / 2
                logo?.draw(in: CGRect(x: logoX, y: logoTopY, width: logoSize, height: logoSize))

                // Left strip (2×): FUEL | DTE | DTCs
                cell(key: "FUEL LEVEL",    val: String(format: "%.1f%%",  values.fuelLevel), at: CGPoint(x: pad, y: strip1Y), kf: mKeyF, vf: mValF)
                cell(key: "DIST TO EMPTY", val: String(format: "%.1f mi", values.dte),        at: CGPoint(x: pad, y: strip2Y), kf: mKeyF, vf: mValF)
                cell(key: "DTCs",          val: values.hasDTC ? "FAULT" : "CLEAR",            at: CGPoint(x: pad, y: strip3Y), valColor: dtcColor, kf: mKeyF, vf: mValF)

                // Right strip (2×): PITCH | ROLL | HEADING
                let rX = w - sideW + pad
                cell(key: "PITCH",   val: String(format: "%.1f° %@", abs(values.pitch), values.pitch >= 0 ? "Up"    : "Down"), at: CGPoint(x: rX, y: strip1Y), kf: mKeyF, vf: mValF)
                cell(key: "ROLL",    val: String(format: "%.1f° %@", abs(values.roll),  values.roll  >= 0 ? "Right" : "Left"), at: CGPoint(x: rX, y: strip2Y), kf: mKeyF, vf: mValF)
                cell(key: "HEADING", val: compassLabel(values.heading),                                                         at: CGPoint(x: rX, y: strip3Y), kf: mKeyF, vf: mValF)
            }
        }
        return image.cgImage
    }

    private static func compassLabel(_ h: Double) -> String {
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
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate,
                         AVCaptureAudioDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard isActuallyRecording,
              let w = assetWriter, w.status == .writing else { return }

        let ts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // Start the AVAssetWriter session on the very first frame (video or audio).
        // All subsequent calls are no-ops on the flag.
        if !writerSessionStarted {
            w.startSession(atSourceTime: ts)
            writerSessionStarted = true
        }

        if output === videoOut {
            guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer),
                  let vIn = videoInput_w, vIn.isReadyForMoreMediaData else { return }
            compositeAndAppend(pixelBuffer: pb, at: ts)

        } else if output === audioOut,
                  let aIn = audioInput_w, aIn.isReadyForMoreMediaData {
            aIn.append(sampleBuffer)
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension CameraManager: AVCapturePhotoCaptureDelegate {

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil,
              let data  = photo.fileDataRepresentation(),
              let uiImg = UIImage(data: data) else {
            DispatchQueue.main.async { self.saveStatus = .failed }; return
        }

        let hud = getHUDImage()
        let finalImage: UIImage

        if let hud {
            let size = uiImg.size
            let r    = UIGraphicsImageRenderer(size: size)
            finalImage = r.image { _ in
                uiImg.draw(in: CGRect(origin: .zero, size: size))
                UIImage(cgImage: hud, scale: 1, orientation: .up)
                    .draw(in: CGRect(origin: .zero, size: size))
            }
        } else {
            finalImage = uiImg
        }
        savePhoto(finalImage)
    }
}
