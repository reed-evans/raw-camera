import CameraCore
import SwiftUI
import UIKit

// OWNER: wt/integration. Composes the preview, controls, and monitoring overlays
// over the shared `CameraModel`. The interface is locked to portrait; in
// landscape the floating overlays are repositioned + counter-rotated so they face
// the user (the preview itself is never rotated).
struct CameraScreen: View {
    @State private var model: CameraModel
    @State private var pinching = false
    @State private var zoomAtPinchStart: CGFloat = 1.0
    @State private var deviceAngle: Angle = .zero

    init(model: CameraModel) {
        _model = State(initialValue: model)
    }

    // MARK: Orientation helpers

    /// Held sideways (±90°).
    private var isLandscape: Bool { abs(deviceAngle.degrees) == 90 }
    /// For landscapeLeft (+90°) the physical bottom maps to the portrait leading
    /// edge; for landscapeRight (−90°) it maps to the trailing edge.
    private var physicalBottomLeading: Bool { deviceAngle.degrees == 90 }
    /// Portrait height reserved for the dock so overlays clear the menu.
    private let dockReserve: CGFloat = 116

    private func refreshOrientation() {
        if let angle = DeviceOrientationAngle.angle(for: UIDevice.current.orientation) {
            deviceAngle = angle
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                preview(size: geo.size)

                // Level (top) + portrait histogram + dock.
                VStack(spacing: 10) {
                    if model.levelGuideEnabled {
                        LevelGuideView(
                            rollDegrees: model.rollDegrees,
                            pitchDegrees: model.pitchDegrees,
                            isLevel: model.isLevel
                        )
                        .facingUser(deviceAngle)
                    }
                    Spacer()
                    if model.histogramEnabled && !isLandscape {
                        HistogramView(histogram: model.histogram)
                            .padding(.leading, 12)
                            .padding(.trailing, histogramTrailingPadding)
                    }
                    ControlsPanel(model: model, angle: deviceAngle)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                }

                // Landscape histogram: a rotated bar along the physical bottom,
                // stopping short of the dock (physical right).
                if model.histogramEnabled && isLandscape {
                    landscapeHistogram(size: geo.size)
                }

                if model.showZoomSlider {
                    zoomOverlay
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .onAppear {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            refreshOrientation()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            refreshOrientation()
        }
        .task {
            // Start the session only after camera access is granted — otherwise
            // it runs with no access and the preview stays black.
            if await Permissions.ensureCaptureAccess() {
                model.startSession()
            }
        }
        .onDisappear {
            model.stopSession()
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
    }

    // MARK: Pieces

    private func preview(size: CGSize) -> some View {
        CameraMetalView(
            model: model,
            histogramProducer: model.histogramProducer,
            framePump: model.framePump
        )
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { location in
            // Normalized device coords (0...1, top-left origin) per the contract.
            guard size.width > 0, size.height > 0 else { return }
            model.focusTap(at: CGPoint(x: location.x / size.width, y: location.y / size.height))
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

    /// Histogram rotated to run along the physical bottom edge, ending before the
    /// dock. Its pre-rotation width becomes the physical-horizontal length.
    private func landscapeHistogram(size: CGSize) -> some View {
        let span = max(160, size.height - dockReserve - 28)
        return HStack(spacing: 0) {
            if !physicalBottomLeading { Spacer() }
            HistogramView(histogram: model.histogram)
                .frame(width: span, height: 58)
                .rotationEffect(deviceAngle)
                .frame(width: 58)
            if physicalBottomLeading { Spacer() }
        }
        .padding(.horizontal, 10)
        // Shift toward the physical-bottom's far end so it clears the dock.
        .padding(.bottom, physicalBottomLeading ? 0 : dockReserve)
        .padding(.top, physicalBottomLeading ? dockReserve : 0)
    }

    @ViewBuilder private var zoomOverlay: some View {
        if isLandscape {
            // Physically: vertically centered, just left of the dock. In portrait
            // coords that is horizontally centered, just above the dock.
            VStack(spacing: 0) {
                Spacer()
                ZoomSlider(model: model).facingUser(deviceAngle)
            }
            .padding(.bottom, dockReserve)
        } else {
            // Portrait: bottom-right, sitting just above the menu (above the open
            // drawer, or above the command bar when closed).
            VStack(spacing: 0) {
                Spacer()
                HStack {
                    Spacer()
                    ZoomSlider(model: model)
                        .facingUser(deviceAngle)
                        .padding(.trailing, 10)
                }
            }
            .padding(.bottom, model.showSettings ? 300 : 104)
        }
    }

    /// Portrait-only trailing margin so the histogram clears the zoom slider,
    /// which sits in the lower-right whenever the slider is shown.
    private var histogramTrailingPadding: CGFloat {
        model.showZoomSlider ? 70 : 12
    }
}
