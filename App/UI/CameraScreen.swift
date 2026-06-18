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
    /// Drives the full-width fine-tuning overlay when a manual slider is grabbed.
    @State private var fineTune = FineTuneSession()
    /// Opacity of the brief black shutter-blink fired the moment a capture starts.
    @State private var shutterBlink: Double = 0
    /// Whether the post-save confirmation thumbnail is currently shown.
    @State private var showThumbnail = false

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
                        // Match the side inset so the rounded corners stay
                        // concentric with the screen and clear its corner curve.
                        .padding(.bottom, 12)
                        .overlay(alignment: .top) {
                            if model.showZoomSlider {
                                zoomSliderAbovePanel
                            }
                        }
                }

                // Fine-tuning overlay floats at the physical top of the screen
                // in both orientations, independent of the panel.
                fineTuneTopOverlay(screen: geo.size)

                // Landscape histogram: a rotated bar along the physical
                // bottom, floating at the far end from the dock (portrait
                // top). A fixed screen position — no panel dependency.
                if model.histogramEnabled && isLandscape {
                    landscapeHistogramStrip
                }

                // Confirmation thumbnail: the just-saved frame flashes in at the
                // physical top-left for a beat or two, then fades away.
                captureThumbnailOverlay(screen: geo.size)

                // Shutter blink: a brief black curtain over the viewfinder fired
                // the instant a capture starts. Never intercepts touches.
                Color.black
                    .opacity(shutterBlink)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .environment(fineTune)
            .animation(.easeOut(duration: 0.14), value: fineTune.active == nil)
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        // Immediate capture feedback: a crisp haptic tap + a quick shutter blink
        // the instant the shutter is pressed, before the photo is processed.
        .sensoryFeedback(.impact(weight: .medium), trigger: model.captureStartCount)
        .onChange(of: model.captureStartCount) {
            shutterBlink = 0.55
            withAnimation(.easeOut(duration: 0.28)) { shutterBlink = 0 }
        }
        // Confirmation thumbnail lifecycle: show on each save, auto-hide after a
        // beat. Keying the task on the counter restarts the timer per capture.
        .task(id: model.captureSavedCount) {
            guard model.captureSavedCount > 0 else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) { showThumbnail = true }
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(.easeInOut(duration: 0.3)) { showThumbnail = false }
        }
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

    /// The zoom slider anchored above the panel as a layout overlay, so its
    /// position is derived (never measured into state — measurement can go
    /// stale mid-animation) and it rides the drawer's spring. A zero-height
    /// frame pinned to the panel's top edge bottom-aligns the slider so it
    /// extends upward, with its visible bottom 10pt above the panel. In
    /// landscape the counter-rotation is a bare rotationEffect (layout box
    /// unchanged), so the visible bottom sits (height − width) / 2 above the
    /// layout box's bottom; the bottom guide compensates for that lift.
    ///
    /// If this is ever freed from the control panel and measurement needed
    /// make sure something always reads the state (or compute it inside a
    /// GeometryReader/custom Layout instead of state)
    private var zoomSliderAbovePanel: some View {
        // The gap matches the histogram's VStack spacing so the slider's
        // bottom lines up with the histogram's bottom edge.
        let gap: CGFloat = 10
        return ZoomSlider(model: model)
            .facingUser(deviceAngle)
            .padding(.trailing, isLandscape ? 0 : 10)
            // The gap lives INSIDE the guide, not in a bottom padding: padding
            // applied after an explicit alignment guide does not shift the
            // guide, so a padding-based gap is silently eaten.
            .alignmentGuide(.bottom) { d in
                let rotationLift = isLandscape ? (d.height - d.width) / 2 : 0
                return d[.bottom] + gap - rotationLift
            }
            .frame(
                maxWidth: .infinity, maxHeight: 0,
                alignment: isLandscape ? .bottom : .bottomTrailing)
    }

    /// Fine-tuning overlay floated at the physical top of the screen. Portrait:
    /// a full-width card below the notch. Landscape: the card rotated to face
    /// the user, hugging the physical-top edge (the portrait side opposite the
    /// dock). Shown only while a manual slider is grabbed; display-only — the
    /// finger drives the inline slider — so it never intercepts touches.
    @ViewBuilder private func fineTuneTopOverlay(screen: CGSize) -> some View {
        if let tuning = fineTune.active {
            let card = FineTuneOverlay(tuning: tuning)
            Group {
                if isLandscape {
                    // The physical top is the portrait edge opposite the dock.
                    let onTrailing = physicalBottomLeading
                    let length = min(screen.height - 120, 460)
                    card
                        .frame(width: length)
                        .rotationEffect(deviceAngle)
                        .frame(width: 110, height: length)
                        .padding(onTrailing ? .trailing : .leading, 16)
                        .frame(
                            maxWidth: .infinity, maxHeight: .infinity,
                            alignment: onTrailing ? .trailing : .leading)
                } else {
                    card
                        .frame(width: screen.width - 24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 64)
                }
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    /// Post-save confirmation thumbnail, pinned to the screen's top-leading
    /// corner and counter-rotated so the saved frame stays upright in any
    /// orientation. Fixed-size, so the bare rotation never disturbs layout.
    /// Display-only — it never intercepts touches.
    @ViewBuilder private func captureThumbnailOverlay(screen: CGSize) -> some View {
        if showThumbnail, let image = model.lastCaptureThumbnail {
            CaptureThumbnail(image: image)
                .facingUser(deviceAngle)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 64)
                .padding(.leading, 20)
                .allowsHitTesting(false)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.6, anchor: .topLeading).combined(with: .opacity),
                        removal: .opacity))
        }
    }

    /// Histogram rotated to run along the physical bottom edge: a fixed-length
    /// strip pinned to the portrait leading/trailing edge (the physical
    /// bottom), floating at the portrait-top end of the screen — the far
    /// corner from the dock. A fixed screen position needs no panel
    /// measurement, so there is no stale-state risk.
    private var landscapeHistogramStrip: some View {
        let span: CGFloat = 280
        return HistogramView(histogram: model.histogram)
            .frame(width: span, height: 56)
            .rotationEffect(deviceAngle)
            .frame(width: 56, height: span)
            .padding(physicalBottomLeading ? .leading : .trailing, 27)
            .padding(.top, 24)
            .frame(
                maxWidth: .infinity, maxHeight: .infinity,
                alignment: physicalBottomLeading ? .topLeading : .topTrailing)
    }

    /// Portrait-only trailing margin so the histogram clears the zoom slider,
    /// which sits in the lower-right whenever the slider is shown.
    private var histogramTrailingPadding: CGFloat {
        model.showZoomSlider ? 70 : 12
    }
}

// MARK: - CaptureThumbnail

/// Small rounded chip showing the just-saved frame — a quiet, dark-luxury
/// confirmation that the capture landed.
private struct CaptureThumbnail: View {
    let image: CGImage

    private static let side: CGFloat = 56
    private static let cornerRadius: CGFloat = 12

    var body: some View {
        // `decorative` — purely confirmatory; the orientation is already baked
        // into the thumbnail by Image I/O, so render it as-is.
        Image(decorative: image, scale: 1, orientation: .up)
            .resizable()
            .scaledToFill()
            .frame(width: Self.side, height: Self.side)
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 3)
            .accessibilityHidden(true)
    }
}

#if DEBUG
    // The Metal preview renders black in the canvas (no camera), but the overlays
    // (controls, histogram, level guide) compose over it.
    #Preview {
        CameraScreen(model: .preview())
    }
#endif
