import AVFoundation
import Photos
import os.log

// OWNER: wt/integration.
//
// Privacy permission requests for camera capture (T2-1 strings live in
// Info.plist). Camera authorization gates live frames; Photos add-only
// authorization gates the DNG save. Both are requested up front so the first
// capture isn't silently dropped. Stays fully on-device (T2-2).

enum Permissions {
    private static let logger = Logger(subsystem: "com.rawcamera", category: "Permissions")

    /// Ensure camera access, prompting if needed, and request Photos add-only
    /// access. Returns whether the camera is authorized — the caller must wait
    /// for `true` before starting the session, or the session runs with no
    /// access and the preview stays black. Safe to call repeatedly.
    static func ensureCaptureAccess() async -> Bool {
        requestPhotosAddOnly()
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted { logger.error("Camera access denied by user.") }
            return granted
        case .denied, .restricted:
            logger.error("Camera access unavailable (denied/restricted).")
            return false
        @unknown default:
            return false
        }
    }

    private static func requestPhotosAddOnly() {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard status == .notDetermined else {
            if status == .denied || status == .restricted {
                logger.error("Photos add-only access unavailable (denied/restricted).")
            }
            return
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
            if newStatus != .authorized && newStatus != .limited {
                logger.error("Photos add-only access denied by user.")
            }
        }
    }
}
