import CoreGraphics
import CoreVideo
import Testing

@testable import CameraCore

/// Grader **T1-6** — Contract conformance.
///
/// A headless mock conforms to the frozen `CameraCapturing` surface. If the
/// protocol changes shape, this fails to compile — catching contract drift in
/// the capture stack at build time, in `CameraCore` (no device required).
final class MockCaptureService: CameraCapturing {
    var onVideoFrame: ((CVPixelBuffer) -> Void)?
    var onConfigured: ((ExposureLimits, Bool) -> Void)?
    var onCaptureFinished: ((String?) -> Void)?
    var onZoomRange: ((CGFloat, CGFloat) -> Void)?
    var onCaptureCapabilities: ((CaptureCapabilities) -> Void)?
    private(set) var exposureLimits: ExposureLimits = .unset
    private(set) var isProRAWAvailable: Bool = false

    private(set) var didStart = false
    private(set) var lastISO: Float?
    private(set) var lastShutter: Double?

    func startSession() { didStart = true }
    func stopSession() { didStart = false }
    func capturePhoto() {}
    func focus(at point: CGPoint) {}
    func setManualExposure(iso: Float, shutterSeconds: Double) {
        lastISO = iso
        lastShutter = shutterSeconds
    }
    func setAutoExposure() {}
    func setWhiteBalance(_ gains: WhiteBalanceGains) {}
    func setAutoWhiteBalance() {}
    func setFocus(lensPosition: Float) {}
    func setAutoFocus() {}
    func setPreferProRAW(_ prefer: Bool) {}
    func setZoom(factor: CGFloat) {}
    func setCaptureOptions(_ options: CaptureOptions) {}
}

@Suite("T1-6 contract conformance")
struct ContractConformanceTests {
    @Test("a type can satisfy the frozen CameraCapturing surface")
    func conforms() {
        let mock = MockCaptureService()
        let service: any CameraCapturing = mock
        service.startSession()
        service.setManualExposure(iso: 100, shutterSeconds: 0.01)
        #expect(mock.didStart)
        #expect(mock.lastISO == 100)
        #expect(mock.lastShutter == 0.01)
    }

    @Test("frozen value types expose their neutral defaults")
    func defaults() {
        #expect(WhiteBalanceGains.neutral == WhiteBalanceGains(red: 1, green: 1, blue: 1))
        #expect(HistogramData.empty.red.count == HistogramData.binCount)
        #expect(ExposureLimits.unset.maxISO == 0)
    }
}
