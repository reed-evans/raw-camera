import Foundation

// OWNER: wt/capture — grader T1-1.
//
// Pure exposure clamp math. Setting shutter/ISO outside the active-format range
// throws at runtime on device, so the model must clamp before applying.
public enum Exposure {
    /// Clamp an ISO value into `[limits.minISO, limits.maxISO]`.
    ///
    /// NaN-safe: a NaN input is treated as the minimum boundary.
    public static func clampISO(_ iso: Float, into limits: ExposureLimits) -> Float {
        guard iso.isFinite else {
            return iso > 0 ? limits.maxISO : limits.minISO
        }
        return min(max(iso, limits.minISO), limits.maxISO)
    }

    /// Clamp a shutter duration (seconds) into the active-format range.
    ///
    /// NaN-safe: a NaN input is treated as the minimum boundary.
    public static func clampShutter(_ seconds: Double, into limits: ExposureLimits) -> Double {
        guard seconds.isFinite else {
            return seconds > 0 ? limits.maxShutterSeconds : limits.minShutterSeconds
        }
        return min(max(seconds, limits.minShutterSeconds), limits.maxShutterSeconds)
    }
}
