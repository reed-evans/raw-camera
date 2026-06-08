import CameraCore
import CoreVideo
import Foundation

// OWNER: wt/metal. The two pure producers that bridge the capture stack and the
// Metal renderer to the integration node (kept out of CameraMetalView.swift).

/// A thin producer the integration node subscribes to. The Metal renderer reads
/// back raw GPU bin counts on its private queue, normalizes them via
/// `CameraCore.Histogram`, and delivers the result on the **main** actor so the
/// integration node can assign it to `CameraModel.histogram` without re-hopping.
public final class HistogramProducer: @unchecked Sendable {
    /// Set by the integration node. Always invoked on the main thread.
    public var onHistogram: ((HistogramData) -> Void)?

    public init() {}

    /// Called by the renderer on its private queue with raw integer counts.
    /// Normalizes off-main, then delivers on main.
    func ingest(red: [Int], green: [Int], blue: [Int], luma: [Int]) {
        let data = Histogram.normalize(red: red, green: green, blue: blue, luma: luma)
        DispatchQueue.main.async { [weak self] in
            self?.onHistogram?(data)
        }
    }
}

/// Frame entry point the integration node pumps from `CameraCapturing.onVideoFrame`.
/// The renderer registers its uploader here when the view is created, so the
/// integration node only needs a reference to this sink — never to the
/// coordinator (which SwiftUI does not surface). `submit` is safe to call from
/// the capture stack's background queue.
public final class FramePump: @unchecked Sendable {
    private let lock = NSLock()
    private var uploader: ((CVPixelBuffer) -> Void)?

    public init() {}

    /// Called by the renderer to register its (off-main) upload path.
    func setUploader(_ uploader: @escaping (CVPixelBuffer) -> Void) {
        lock.lock()
        self.uploader = uploader
        lock.unlock()
    }

    /// Integration pumps each camera frame here. Valid only for the call's
    /// duration (the pool recycles the buffer); the uploader copies via the
    /// texture cache immediately.
    public func submit(_ pixelBuffer: CVPixelBuffer) {
        lock.lock()
        let uploader = self.uploader
        lock.unlock()
        uploader?(pixelBuffer)
    }
}
