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

            VStack(spacing: 10) {
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
                        .padding(.horizontal, 12)
                }
                ControlsPanel(model: model)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }
        }
        .statusBarHidden(true)
        .task {
            // Start the session only after camera access is granted — otherwise
            // it runs with no access and the preview stays black. `.task` runs on
            // the main actor, so the @MainActor model call is safe here.
            if await Permissions.ensureCaptureAccess() {
                model.startSession()
            }
        }
        .onDisappear { model.stopSession() }
    }
}
