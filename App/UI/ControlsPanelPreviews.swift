import CameraCore
import SwiftUI

// OWNER: wt/controls-ui. Xcode previews for ControlsPanel (DEBUG only).

#if DEBUG
    private final class StubCapturing: CameraCapturing {
        var onVideoFrame: ((CVPixelBuffer) -> Void)?
        var onConfigured: ((ExposureLimits, Bool) -> Void)?
        var onCaptureFinished: ((String?) -> Void)?
        var exposureLimits = ExposureLimits(
            minISO: 25, maxISO: 6400,
            minShutterSeconds: 1.0 / 8000, maxShutterSeconds: 30.0
        )
        var isProRAWAvailable: Bool = true
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

    #Preview("collapsed") {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack {
                Spacer()
                ControlsPanel(model: CameraModel(service: StubCapturing()))
                    .padding(.horizontal, 12)
            }
        }.preferredColorScheme(.dark)
    }

    #Preview("manual") {
        let model = CameraModel(service: StubCapturing())
        model.isManualExposure = true
        model.isManualWhiteBalance = true
        model.isManualFocus = true
        model.zebraEnabled = true
        model.focusPeakingEnabled = true
        return ZStack {
            Color.black.ignoresSafeArea()
            VStack {
                Spacer()
                ControlsPanel(model: model)
                    .padding(.horizontal, 12)
            }
        }.preferredColorScheme(.dark)
    }
#endif
