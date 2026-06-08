import CameraCore
import CoreGraphics
import CoreVideo

// OWNER: wt/capture. Phase-0 stub conforming to the frozen `CameraCapturing`
// surface. The capture worker replaces these bodies with AVFoundation /
// RAW+ProRAW configuration, manual controls, and Photos save — pushing all
// pure math into CameraCore (Exposure / WhiteBalance / RAWFormatSelector).
final class CaptureService: CameraCapturing {
    var onVideoFrame: ((CVPixelBuffer) -> Void)?
    var onConfigured: ((ExposureLimits, Bool) -> Void)?
    var onCaptureFinished: ((String?) -> Void)?
    private(set) var exposureLimits: ExposureLimits = .unset
    private(set) var isProRAWAvailable: Bool = false

    func startSession() {}
    func stopSession() {}
    func capturePhoto() {}
    func focus(at point: CGPoint) {}
    func setManualExposure(iso: Float, shutterSeconds: Double) {}
    func setAutoExposure() {}
    func setWhiteBalance(_ gains: WhiteBalanceGains) {}
    func setAutoWhiteBalance() {}
    func setFocus(lensPosition: Float) {}
    func setAutoFocus() {}
    func setPreferProRAW(_ prefer: Bool) {}
}
