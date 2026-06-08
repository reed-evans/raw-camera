import Foundation

// OWNER: wt/capture — implement test-first (grader T1-5). Phase-0 stub.
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
    public static func select(from formats: [RAWFormat], preferProRAW: Bool) -> RAWFormat? {
        // TODO(wt/capture): implement + test (T1-5).
        formats.first
    }
}
