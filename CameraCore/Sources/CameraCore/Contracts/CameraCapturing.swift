import CoreGraphics
import CoreVideo

/// **FROZEN protocol surface — orchestrator-mediated only.**
///
/// The capture stack (`App/Capture/CaptureService.swift`) conforms to this.
/// `CameraModel` depends on `any CameraCapturing` so UI agents code against the
/// model, never against the concrete service. Grader **T1-6** checks that a
/// conforming type compiles against this surface.
///
/// Threading contract: `onVideoFrame` is delivered on a background queue;
/// consumers must hop to the main actor before mutating observable state.
/// Session control (`startSession`/`stopSession`) and `capturePhoto` run their
/// AVFoundation work off the main thread inside the implementation.
public protocol CameraCapturing: AnyObject {
    /// Per-frame preview hand-off. Called on a background queue. The
    /// `CVPixelBuffer` is valid only for the duration of the call — retain or
    /// copy it if you need it past return (the pool recycles it otherwise).
    var onVideoFrame: ((CVPixelBuffer) -> Void)? { get set }

    /// Fires after `startSession` configures the active format (background
    /// queue): delivers the real exposure range and ProRAW availability, which
    /// are `.unset`/`false` until then. Consumers hop to the main actor before
    /// updating observable state.
    var onConfigured: ((ExposureLimits, _ isProRAWAvailable: Bool) -> Void)? { get set }

    /// Fires when a capture finishes (background queue). `nil` means the DNG
    /// saved to Photos; non-`nil` is a user-presentable failure message.
    var onCaptureFinished: ((_ error: String?) -> Void)? { get set }

    /// Fires (background queue) once a just-saved capture has a small, upright
    /// preview thumbnail ready — the UI briefly shows it as a confirmation that
    /// the photo landed. Only fires on a successful save. Consumers hop to the
    /// main actor before touching observable state.
    var onCaptureThumbnail: ((CGImage) -> Void)? { get set }

    /// Fires after configuration (background queue): the device's usable video
    /// zoom range (min...max). Consumers hop to the main actor.
    var onZoomRange: ((_ minZoom: CGFloat, _ maxZoom: CGFloat) -> Void)? { get set }

    /// Fires after configuration (background queue): which advanced capture
    /// features (48MP, RAW bracketing, 10-bit HDR) the device supports.
    var onCaptureCapabilities: ((CaptureCapabilities) -> Void)? { get set }

    /// Fires (throttled) while a device is configured: the device's current
    /// effective exposure / white-balance / focus values, so the UI can show
    /// live read-only readouts in auto mode. Background queue; consumers hop to
    /// the main actor before updating observable state.
    var onDeviceValues: ((DeviceValues) -> Void)? { get set }

    /// Active-format exposure range; `.unset` until a device is configured.
    var exposureLimits: ExposureLimits { get }

    /// Whether the active device/output supports Apple ProRAW.
    var isProRAWAvailable: Bool { get }

    func startSession()
    func stopSession()

    func capturePhoto()
    /// Focus point of interest in normalized device coordinates, `0...1`,
    /// top-left origin.
    func focus(at point: CGPoint)

    func setManualExposure(iso: Float, shutterSeconds: Double)
    func setAutoExposure()

    func setWhiteBalance(_ gains: WhiteBalanceGains)
    func setAutoWhiteBalance()

    func setFocus(lensPosition: Float)
    func setAutoFocus()

    /// Prefer ProRAW (DNG) over Bayer RAW when both are available.
    func setPreferProRAW(_ prefer: Bool)

    /// Set the video zoom factor; the implementation clamps to the device range.
    func setZoom(factor: CGFloat)

    /// Apply advanced capture options (48MP / RAW bracket / 10-bit HDR / max
    /// quality). Unsupported options are ignored per `onCaptureCapabilities`.
    func setCaptureOptions(_ options: CaptureOptions)
}
