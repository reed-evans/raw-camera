import AVFoundation
import Photos

// OWNER: wt/capture.
//
// AVCapturePhotoCaptureDelegate that collects RAW/ProRAW DNG data and saves it
// to the Photos library. Errors are forwarded via `onCaptureFinished` —
// never silently swallowed.

final class PhotoCaptureProcessor: NSObject {

    private let onCaptureFinished: ((String?) -> Void)?
    /// Set by the owner (`CaptureService`) to release this processor once the
    /// capture has fully terminated (terminal delegate fired + Photos save done).
    /// Lets the owner retain the delegate across the async save without leaking.
    var onComplete: ((PhotoCaptureProcessor) -> Void)?

    /// Accumulated DNG data from the RAW photo output.
    private var rawData: Data?
    /// Processed/compressed photo data for ProRAW (used as the alternatePhoto).
    private var processedData: Data?
    /// Whether the capture settings requested a ProRAW output.
    private var isProRAWCapture: Bool = false
    /// Stores the first error from `didFinishProcessingPhoto` so that
    /// `didFinishCaptureFor` can fire `onCaptureFinished` exactly once.
    private var captureError: String?

    init(onCaptureFinished: ((String?) -> Void)?) {
        self.onCaptureFinished = onCaptureFinished
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension PhotoCaptureProcessor: AVCapturePhotoCaptureDelegate {

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            // Store the error; do NOT fire onCaptureFinished here.
            // didFinishCaptureFor always fires last and will emit exactly one callback.
            captureError = error.localizedDescription
            return
        }

        if photo.isRawPhoto {
            rawData = photo.fileDataRepresentation()
            // Determine ProRAW via the pixel buffer's format type.
            if let pixelBuffer = photo.pixelBuffer {
                let fmt = CVPixelBufferGetPixelFormatType(pixelBuffer)
                isProRAWCapture = AVCapturePhotoOutput.isAppleProRAWPixelFormat(fmt)
            }
        } else {
            processedData = photo.fileDataRepresentation()
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        // Terminal delegate method — fires exactly once per capture.
        // Evaluate in priority order: capture-level error > processing error >
        // missing RAW data > success save path.
        if let error {
            finish(error.localizedDescription)
            return
        }

        if let processingError = captureError {
            finish(processingError)
            return
        }

        guard let rawData else {
            finish("No RAW data received from capture.")
            return
        }

        saveToPhotos(rawData: rawData, processedData: processedData)
    }

    /// Emits the capture result exactly once, then releases this processor via
    /// `onComplete`. All terminal paths funnel through here.
    private func finish(_ error: String?) {
        onCaptureFinished?(error)
        onComplete?(self)
    }

    // MARK: - Private: Photos library save

    private func saveToPhotos(rawData: Data, processedData: Data?) {
        PHPhotoLibrary.shared().performChanges {
            let creationRequest = PHAssetCreationRequest.forAsset()

            if let processedData, self.isProRAWCapture {
                // ProRAW: save processed as the primary photo, RAW as alternate.
                creationRequest.addResource(with: .photo, data: processedData, options: nil)
                let rawOptions = PHAssetResourceCreationOptions()
                rawOptions.shouldMoveFile = false
                creationRequest.addResource(with: .alternatePhoto, data: rawData, options: rawOptions)
            } else {
                // Bayer RAW or ProRAW without a paired processed image.
                creationRequest.addResource(with: .photo, data: rawData, options: nil)
            }
        } completionHandler: { [weak self] success, error in
            if success {
                self?.finish(nil)
            } else {
                let message = error?.localizedDescription ?? "Unknown Photos library error."
                self?.finish(message)
            }
        }
    }
}
