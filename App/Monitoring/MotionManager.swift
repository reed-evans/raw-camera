import CameraCore
import CoreMotion
import Foundation

// OWNER: wt/monitoring-ui.
//
// Thin CoreMotion shell. Converts CMDeviceMotion.gravity → SIMD3<Double> and
// delegates all trig/threshold logic to CameraCore.Level (pure simd, no CoreMotion).
//
// Threading contract (T2-4):
//   • CMMotionManager updates fire on a dedicated background OperationQueue.
//   • Level.attitude + Level.isLevel are called on that background queue.
//   • onAttitude is invoked on the background queue; callers are responsible for
//     hopping to @MainActor before writing observable model state.
//   • @Observable writes are NOT done here — this is a pure producer.
final class MotionManager {

    // MARK: - Public interface

    /// Called on the CoreMotion background queue for every attitude sample.
    /// Set this before calling start(). Callers must hop to @MainActor before
    /// writing observable model state.
    var onAttitude: ((Level.Attitude) -> Void)?

    // MARK: - Private state

    private let motionManager = CMMotionManager()
    private let motionQueue = OperationQueue()

    // MARK: - Lifecycle

    /// Begin device-motion updates on a background queue.
    /// Set onAttitude before calling this.
    func start() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionQueue.name = "com.rawcamera.motion"
        motionQueue.qualityOfService = .userInteractive
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        // Capture the callback once so it is delivered exactly once per sample
        // on the background motion queue — no hop, no double delivery.
        let deliver = onAttitude
        motionManager.startDeviceMotionUpdates(to: motionQueue) { motion, _ in
            guard let motion else { return }
            let g = motion.gravity
            let gravity = SIMD3<Double>(g.x, g.y, g.z)
            let attitude = Level.attitude(gravity: gravity)
            deliver?(attitude)
        }
    }

    /// Stop device-motion updates.
    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }
}
