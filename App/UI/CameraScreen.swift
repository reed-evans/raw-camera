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

    private func refreshOrientation() {
        if let angle = DeviceOrientationAngle.angle(for: UIDevice.current.orientation) {
            deviceAngle = angle
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                preview(size: geo.size)
                if model.levelGuideEnabled {
                    LevelGuideView(
                        rollDegrees: model.rollDegrees,
                        isLevel: model.isLevel
                    )
                }

                // Level (top) + portrait histogram + dock.
                VStack(spacing: 10) {
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

    /// Reserve at the physical-right (portrait bottom) so overlays clear the menu,
    /// which is taller when the settings drawer is open.
    private var menuReserve: CGFloat { model.showSettings ? 300 : 110 }

    /// The zoom slider hugs the menu in landscape — a smaller inset than the full
    /// menu reserve so it sits right next to the panel rather than mid-screen.
    private var landscapeZoomInset: CGFloat { model.showSettings ? 175 : 15 }

    /// Histogram rotated to run along the physical bottom edge: a fixed-length
    /// strip pinned to the portrait leading/trailing edge, hanging from the top
    /// margin, shrinking only when the space above the menu can't fit it.
    private func landscapeHistogram(size: CGSize) -> some View {
        let topMargin: CGFloat = 40
        let bottomInset = menuReserve + 40
        let span: CGFloat = min(280, size.height - topMargin - bottomInset)
        return HStack(spacing: 0) {
            if !physicalBottomLeading { Spacer() }
            VStack(spacing: 0) {
                HistogramView(histogram: model.histogram)
                    .frame(width: span, height: 56)
                    .rotationEffect(deviceAngle)
                    .frame(width: 56, height: span)
                Spacer()
            }
            if physicalBottomLeading { Spacer() }
        }
        .padding(physicalBottomLeading ? .leading : .trailing, 27)
        .padding(.top, topMargin)
    }

    @ViewBuilder private var zoomOverlay: some View {
        if isLandscape {
            // Physically: sitting right next to the menu (just left of it). In
            // portrait coords that is horizontally centered, just above the menu —
            // a smaller inset than the histogram so it tucks up against the panel.
            VStack(spacing: 0) {
                Spacer()
                ZoomSlider(model: model).facingUser(deviceAngle)
            }
            .padding(.bottom, landscapeZoomInset)
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

#if DEBUG
    // The Metal preview renders black in the canvas (no camera), but the overlays
    // (controls, histogram, level guide) compose over it.
    #Preview {
        CameraScreen(model: .preview())
    }
#endif
