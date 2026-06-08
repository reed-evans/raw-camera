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

    /// Request camera + Photos (add-only) authorization. Safe to call repeatedly;
    /// the system returns the cached decision after the first prompt.
    static func requestCaptureAccess() {
        requestCamera()
        requestPhotosAddOnly()
    }

    private static func requestCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if !granted { logger.error("Camera access denied by user.") }
            }
        case .denied, .restricted:
            logger.error("Camera access unavailable (denied/restricted).")
        case .authorized:
            break
        @unknown default:
            break
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
