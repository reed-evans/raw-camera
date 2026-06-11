import Foundation

// OWNER: wt/capture — amendment A3 (advanced capture options).
//
// Value types shared between `CameraModel` and the capture stack, plus the pure
// bracket-bias math (Tier-1 tested; no AVFoundation in CameraCore).

/// Advanced capture options the user can toggle in settings. Applied via
/// `CameraCapturing.setCaptureOptions(_:)`; unsupported options are ignored by
/// the implementation (capabilities are reported via `onCaptureCapabilities`).
public struct CaptureOptions: Equatable, Sendable {
    /// Capture at the sensor's full resolution (e.g. 48MP) instead of binned.
    public var highResolution: Bool
    /// Capture a 3-shot RAW exposure bracket (±2 EV) instead of a single RAW.
    public var rawBracketing: Bool
    /// Use the 10-bit HLG/BT.2020 color space for processed output.
    public var hdr10BitColor: Bool
    /// Prioritize maximum processing quality over shot-to-shot speed.
    public var maxQuality: Bool

    public init(
        highResolution: Bool = false,
        rawBracketing: Bool = false,
        hdr10BitColor: Bool = false,
        maxQuality: Bool = true
    ) {
        self.highResolution = highResolution
        self.rawBracketing = rawBracketing
        self.hdr10BitColor = hdr10BitColor
        self.maxQuality = maxQuality
    }
}

/// What the configured device actually supports; reported after configuration
/// so the UI can disable unavailable toggles.
public struct CaptureCapabilities: Equatable, Sendable {
    public var supports48MP: Bool
    public var supportsRAWBracketing: Bool
    public var supports10BitHDR: Bool

    public init(supports48MP: Bool, supportsRAWBracketing: Bool, supports10BitHDR: Bool) {
        self.supports48MP = supports48MP
        self.supportsRAWBracketing = supportsRAWBracketing
        self.supports10BitHDR = supports10BitHDR
    }

    public static let none = CaptureCapabilities(
        supports48MP: false, supportsRAWBracketing: false, supports10BitHDR: false
    )
}

/// Pure exposure-bracket math: symmetric EV biases around 0, clamped into the
/// device's supported bias range (out-of-range biases throw at runtime).
public enum ExposureBracket {
    /// `count` biases stepped by `stops`, centered on 0, each clamped into
    /// `[minBias, maxBias]`. Non-finite `stops` is treated as 0; `count < 1`
    /// yields a single 0 bias.
    public static func biases(count: Int, stops: Float, minBias: Float, maxBias: Float) -> [Float] {
        let n = max(1, count)
        let step = stops.isFinite ? stops : 0
        let mid = Float(n - 1) / 2
        return (0..<n).map { i in
            let raw = (Float(i) - mid) * step
            return min(max(raw, minBias), maxBias)
        }
    }
}
