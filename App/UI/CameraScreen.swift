import CameraCore
import SwiftUI

// OWNER: wt/integration. Phase-0 stub composing the preview, controls, and
// monitoring overlays over the shared `CameraModel`.
struct CameraScreen: View {
    @State private var model: CameraModel
    @State private var pinching = false
    @State private var zoomAtPinchStart: CGFloat = 1.0

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
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            if !pinching {
                                pinching = true
                                zoomAtPinchStart = model.zoomFactor
                            }
                            model.setZoom(zoomAtPinchStart * value.magnification)
                        }
                        .onEnded { _ in pinching = false }
                )
            }
            .ignoresSafeArea()

            if model.showZoomSlider {
                HStack {
                    Spacer()
                    ZoomSlider(model: model).padding(.trailing, 10)
                }
            }

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
                        .padding(.leading, 12)
                        .padding(.trailing, histogramTrailingPadding)
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

    /// Trailing margin for the histogram. When the zoom slider is shown AND the
    /// settings drawer is open, the drawer pushes the histogram up into the
    /// slider's row — stop the histogram short of the slider (slider ≈48pt wide
    /// + 10pt inset) with a small gap. In every other state, keep the normal 12.
    private var histogramTrailingPadding: CGFloat {
        model.showZoomSlider && model.showSettings ? 70 : 12
    }
}
