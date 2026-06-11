import Foundation

/// **FROZEN — orchestrator-mediated only.** Active-format exposure range.
/// Used by the capture stack and surfaced through `CameraModel`.
public struct ExposureLimits: Equatable, Sendable {
    public var minISO: Float
    public var maxISO: Float
    /// Shutter (exposure duration) bounds in **seconds**.
    public var minShutterSeconds: Double
    public var maxShutterSeconds: Double

    public init(
        minISO: Float,
        maxISO: Float,
        minShutterSeconds: Double,
        maxShutterSeconds: Double
    ) {
        self.minISO = minISO
        self.maxISO = maxISO
        self.minShutterSeconds = minShutterSeconds
        self.maxShutterSeconds = maxShutterSeconds
    }

    /// A neutral default used by shells before a device reports real limits.
    public static let unset = ExposureLimits(
        minISO: 0, maxISO: 0, minShutterSeconds: 0, maxShutterSeconds: 0
    )
}

/// **FROZEN — orchestrator-mediated only.** The device's current *effective*
/// exposure / white-balance / focus values, sampled from the live capture
/// device. Lets the UI show read-only readouts while in auto mode (where the
/// device, not the user, is choosing these). Shutter is in seconds; temperature
/// in Kelvin; tint in Apple's device units; lens position in `0...1`.
public struct DeviceValues: Equatable, Sendable {
    public var iso: Float
    public var shutterSeconds: Double
    public var whiteBalanceTemperature: Float
    public var whiteBalanceTint: Float
    public var lensPosition: Float

    public init(
        iso: Float,
        shutterSeconds: Double,
        whiteBalanceTemperature: Float,
        whiteBalanceTint: Float,
        lensPosition: Float
    ) {
        self.iso = iso
        self.shutterSeconds = shutterSeconds
        self.whiteBalanceTemperature = whiteBalanceTemperature
        self.whiteBalanceTint = whiteBalanceTint
        self.lensPosition = lensPosition
    }
}

/// **FROZEN — orchestrator-mediated only.** Per-channel white-balance gains.
/// Each channel is in `1.0...maxGain` (device-reported). Green is typically
/// pinned to `1.0` and red/blue scale around it.
public struct WhiteBalanceGains: Equatable, Sendable {
    public var red: Float
    public var green: Float
    public var blue: Float

    public init(red: Float, green: Float, blue: Float) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let neutral = WhiteBalanceGains(red: 1, green: 1, blue: 1)
}

/// **FROZEN — orchestrator-mediated only.** Normalized capture-time histogram.
/// 256 bins per channel, each value in `0...1` (bin count / max bin count).
public struct HistogramData: Equatable, Sendable {
    public static let binCount = 256

    public var red: [Float]
    public var green: [Float]
    public var blue: [Float]
    public var luma: [Float]

    public init(red: [Float], green: [Float], blue: [Float], luma: [Float]) {
        self.red = red
        self.green = green
        self.blue = blue
        self.luma = luma
    }

    /// All-zero histogram (no frame yet). Never causes divide-by-zero downstream.
    public static let empty = HistogramData(
        red: Array(repeating: 0, count: binCount),
        green: Array(repeating: 0, count: binCount),
        blue: Array(repeating: 0, count: binCount),
        luma: Array(repeating: 0, count: binCount)
    )
}
