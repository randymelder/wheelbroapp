// MotionManager.swift
// Wraps CMMotionManager to expose device pitch and roll in degrees.
//
// PITCH — rotation around the device's x-axis (lateral axis).
//   Positive = nose of the vehicle pointing upward (climbing).
//   Negative = nose pointing downward (descending).
//
// ROLL  — rotation around the device's y-axis (longitudinal axis).
//   Positive = right side of the vehicle higher (leaning left).
//   Negative = left side higher (leaning right).
//
// NOTE: Angles are relative to the phone's current mounting orientation,
// not an absolute vehicle frame. Mount the phone consistently for repeatable
// readings. No Info.plist permissions are required.

import Foundation
import CoreMotion
import Observation

@Observable
final class MotionManager {

    // =========================================================================
    // MARK: - Public State  (observed by SwiftUI views)
    // =========================================================================
    var pitch:       Double = 0.0   // degrees, + = nose up
    var roll:        Double = 0.0   // degrees, + = right side up
    var isAvailable: Bool   = false

    // =========================================================================
    // MARK: - Private State
    // =========================================================================
    private let cmManager = CMMotionManager()

    // =========================================================================
    // MARK: - Init
    // =========================================================================
    init() {
        isAvailable = cmManager.isDeviceMotionAvailable
    }

    // =========================================================================
    // MARK: - Start / Stop
    // =========================================================================
    func startUpdates() {
        guard cmManager.isDeviceMotionAvailable else {
            print("[Motion] device motion not available on this hardware")
            return
        }
        guard !cmManager.isDeviceMotionActive else { return }  // already running
        cmManager.deviceMotionUpdateInterval = MotionConstants.updateInterval
        cmManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self else { return }
            if let error {
                print("[Motion] error: \(error.localizedDescription)")
                return
            }
            guard let motion else { return }
            self.pitch = motion.attitude.pitch * (180.0 / .pi)
            self.roll  = motion.attitude.roll  * (180.0 / .pi)
        }
        print("[Motion] started at \(Int(1.0 / MotionConstants.updateInterval)) Hz")
    }

    func stopUpdates() {
        cmManager.stopDeviceMotionUpdates()
        print("[Motion] stopped")
    }
}
