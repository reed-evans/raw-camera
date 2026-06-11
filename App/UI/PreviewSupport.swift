#if DEBUG
    import CameraCore
    import CoreGraphics
    import CoreVideo
    import Foundation

    // OWNER: wt/integration. Shared fixtures for SwiftUI previews (Xcode canvas).
    // DEBUG-only; never shipped.

    /// Headless `CameraCapturing` stub so previews build without a device.
    final class PreviewCaptureStub: CameraCapturing {
        var onVideoFrame: ((CVPixelBuffer) -> Void)?
        var onConfigured: ((ExposureLimits, Bool) -> Void)?
        var onCaptureFinished: ((String?) -> Void)?
        var onZoomRange: ((CGFloat, CGFloat) -> Void)?
        var onCaptureCapabilities: ((CaptureCapabilities) -> Void)?
        var exposureLimits = ExposureLimits(
            minISO: 25, maxISO: 6400, minShutterSeconds: 1.0 / 8000, maxShutterSeconds: 30)
        var isProRAWAvailable = true
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
        func setZoom(factor: CGFloat) {}
        func setCaptureOptions(_ options: CaptureOptions) {}
    }

    extension CameraModel {
        /// A model wired to a headless stub, populated with sample data so the
        /// canvas shows realistic content.
        @MainActor static func preview() -> CameraModel {
            let model = CameraModel(service: PreviewCaptureStub())
            model.isProRAWAvailable = true
            model.is48MPAvailable = true
            model.isRAWBracketingAvailable = true
            model.histogram = .previewSample
            model.rollDegrees = 4
            model.pitchDegrees = -3
            return model
        }
    }

    extension HistogramData {
        /// A representative multi-channel histogram for previews.
        static var previewSample: HistogramData {
            func curve(peak: Int, scale: Double) -> [Float] {
                (0..<binCount).map { i in
                    let d = Double(i - peak) / 38
                    return Float(min(1, max(0, exp(-d * d) * scale)))
                }
            }
            return HistogramData(
                red: curve(peak: 90, scale: 0.9),
                green: curve(peak: 120, scale: 1.0),
                blue: curve(peak: 150, scale: 0.8),
                luma: curve(peak: 110, scale: 0.95)
            )
        }
    }
#endif
