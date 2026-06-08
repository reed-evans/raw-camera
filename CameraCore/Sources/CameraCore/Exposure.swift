import Foundation

// OWNER: wt/capture — implement test-first (grader T1-1). Phase-0 stub.
//
// Pure exposure clamp math. Setting shutter/ISO outside the active-format range
// throws at runtime on device, so the model must clamp before applying.
public enum Exposure {
    /// Clamp an ISO value into `[limits.minISO, limits.maxISO]`.
    public static func clampISO(_ iso: Float, into limits: ExposureLimits) -> Float {
        // TODO(wt/capture): implement + test (T1-1).
        iso
    }

    /// Clamp a shutter duration (seconds) into the active-format range.
    public static func clampShutter(_ seconds: Double, into limits: ExposureLimits) -> Double {
        // TODO(wt/capture): implement + test (T1-1).
        seconds
    }
}
