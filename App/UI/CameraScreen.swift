import CameraCore
import SwiftUI

// OWNER: wt/integration. Phase-0 stub composing the preview, controls, and
// monitoring overlays over the shared `CameraModel`.
struct CameraScreen: View {
    @State private var model: CameraModel

    init(model: CameraModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                CameraMetalView(
                    model: model,
                    histogramProducer: model.histogramProducer,
                    framePump: model.framePump
                )
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { location in
                    // Normalized device coords (0...1, top-left origin) per the
                    // CameraCapturing.focus(at:) contract.
                    let size = proxy.size
                    guard size.width > 0, size.height > 0 else { return }
                    model.focusTap(
                        at: CGPoint(
                            x: location.x / size.width,
                            y: location.y / size.height
                        )
                    )
                }
            }
            .ignoresSafeArea()

            VStack {
                if model.levelGuideEnabled {
                    LevelGuideView(
                        rollDegrees: model.rollDegrees,
                        pitchDegrees: model.pitchDegrees,
                        isLevel: model.isLevel
                    )
                }
                Spacer()
                if model.histogramEnabled {
                    HistogramView(histogram: model.histogram)
                }
                ControlsPanel(model: model)
            }
        }
        .statusBarHidden(true)
        .onAppear {
            Permissions.requestCaptureAccess()
            model.startSession()
        }
        .onDisappear { model.stopSession() }
    }
}
