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
@MainActor
final class MotionManager {

    // MARK: - Public interface

    /// Called on a background queue when a new attitude sample is available.
    /// Callers must dispatch to @MainActor before touching CameraModel.
    var onAttitude: ((Level.Attitude) -> Void)?

    // MARK: - Private state

    @ObservationIgnored private let motionManager = CMMotionManager()
    @ObservationIgnored private let motionQueue = OperationQueue()

    // MARK: - Lifecycle

    /// Begin device-motion updates on a background queue.
    func start() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionQueue.name = "com.rawcamera.motion"
        motionQueue.qualityOfService = .userInteractive
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        // Capture the callback outside the actor to avoid data races.
        let callback = onAttitude
        motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, _ in
            guard let motion else { return }
            let g = motion.gravity
            let gravity = SIMD3<Double>(g.x, g.y, g.z)
            let attitude = Level.attitude(gravity: gravity)
            // Invoke on the background queue — caller hops to main actor.
            callback?(attitude)
            // Also forward via the stored property in case it changed after start().
            self?.dispatchAttitude(attitude)
        }
    }

    /// Stop device-motion updates and release the callback.
    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }

    // MARK: - Private helpers

    /// Forwards an attitude sample through the stored onAttitude closure.
    /// Called from the background motion queue; nonisolated to avoid actor hop.
    nonisolated private func dispatchAttitude(_ attitude: Level.Attitude) {
        Task { @MainActor [weak self] in
            self?.onAttitude?(attitude)
        }
    }
}
