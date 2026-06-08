import Foundation

// OWNER: wt/capture — grader T1-5.
//
// RAW-format selection over an injected list (keeps AVFoundation out of
// CameraCore so the choice is unit-testable). The app maps real
// `availableRawPhotoPixelFormatTypes` into `[RAWFormat]`.

/// A candidate RAW pixel format, abstracted away from AVFoundation.
public struct RAWFormat: Equatable, Sendable {
    /// The underlying `OSType` pixel-format code (opaque to CameraCore).
    public var pixelFormat: UInt32
    public var isProRAW: Bool
    public var isBayerRAW: Bool

    public init(pixelFormat: UInt32, isProRAW: Bool, isBayerRAW: Bool) {
        self.pixelFormat = pixelFormat
        self.isProRAW = isProRAW
        self.isBayerRAW = isBayerRAW
    }
}

public enum RAWFormatSelector {
    /// Pick ProRAW when preferred and available; otherwise fall back to Bayer
    /// RAW; otherwise the first available; `nil` if the list is empty.
    ///
    /// Selection rules (in priority order):
    /// 1. Empty list → `nil`.
    /// 2. `preferProRAW == true` and a ProRAW format exists → pick the first ProRAW.
    /// 3. A Bayer RAW format exists → pick the first Bayer.
    /// 4. Fall back to the first available format (unknown type).
    public static func select(from formats: [RAWFormat], preferProRAW: Bool) -> RAWFormat? {
        guard !formats.isEmpty else { return nil }

        if preferProRAW, let proRAW = formats.first(where: { $0.isProRAW }) {
            return proRAW
        }
        if let bayer = formats.first(where: { $0.isBayerRAW }) {
            return bayer
        }
        return formats.first
    }
}
