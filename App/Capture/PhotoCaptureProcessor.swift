import AVFoundation
import Photos
import os.log

// OWNER: wt/capture.
//
// AVCapturePhotoCaptureDelegate that collects RAW/ProRAW DNG data and saves it
// to the Photos library. Errors are forwarded via `onCaptureFinished` —
// never silently swallowed — and logged with their real domain/code.

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

    private let logger = Logger(subsystem: "com.rawcamera", category: "PhotoCapture")

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
            // didFinishCaptureFor always fires last and emits exactly one callback.
            captureError = describe(error, context: "processing photo")
            return
        }

        if photo.isRawPhoto {
            rawData = photo.fileDataRepresentation()
            if rawData == nil { logger.error("RAW fileDataRepresentation() returned nil.") }
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
        // Priority: capture-level error > processing error > missing data > save.
        if let error {
            finish(describe(error, context: "capture"))
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

    /// Log an error with its real domain/code and return a user-facing message.
    private func describe(_ error: Error, context: String) -> String {
        let ns = error as NSError
        let detail = "\(ns.domain) code \(ns.code) — \(ns.localizedDescription)"
        logger.error("Capture error [\(context, privacy: .public)]: \(detail, privacy: .public)")
        return ns.localizedDescription
    }

    // MARK: - Private: Photos library save

    private func saveToPhotos(rawData: Data, processedData: Data?) {
        // Photos reliably ingests a RAW DNG from a file URL with the correct
        // extension; raw bytes added via `data:` are often rejected with a generic
        // "operation could not be completed". Stage the DNG to a temp .dng file.
        let rawURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("dng")
        do {
            try rawData.write(to: rawURL)
        } catch {
            finish(describe(error, context: "writing temp DNG"))
            return
        }

        PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let rawOptions = PHAssetResourceCreationOptions()
            rawOptions.shouldMoveFile = true
            if let processedData, self.isProRAWCapture {
                // ProRAW: processed image is the primary photo, the DNG is the alternate.
                request.addResource(with: .photo, data: processedData, options: nil)
                request.addResource(with: .alternatePhoto, fileURL: rawURL, options: rawOptions)
            } else {
                // Bayer RAW (or ProRAW with no paired processed image): DNG is the photo.
                request.addResource(with: .photo, fileURL: rawURL, options: rawOptions)
            }
        } completionHandler: { [weak self] success, error in
            // If shouldMoveFile consumed the file this is a harmless no-op.
            try? FileManager.default.removeItem(at: rawURL)
            if success {
                self?.finish(nil)
            } else if let error {
                self?.finish(self?.describe(error, context: "Photos save") ?? error.localizedDescription)
            } else {
                self?.finish("Unknown Photos library error.")
            }
        }
    }
}
