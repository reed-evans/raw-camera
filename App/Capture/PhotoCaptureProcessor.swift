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

    /// Accumulated DNG data from the RAW photo output — one entry per frame
    /// (a single capture yields one; an exposure bracket yields one per frame).
    private var rawDatas: [Data] = []
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
            if let data = photo.fileDataRepresentation() {
                rawDatas.append(data)
            } else {
                logger.error("RAW fileDataRepresentation() returned nil.")
            }
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
        guard !rawDatas.isEmpty else {
            finish("No RAW data received from capture.")
            return
        }
        saveToPhotos(rawDatas: rawDatas, processedData: processedData)
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

    private func saveToPhotos(rawDatas: [Data], processedData: Data?) {
        // Photos reliably ingests a RAW DNG from a file URL with the correct
        // extension; raw bytes added via `data:` are often rejected with a generic
        // "operation could not be completed". Stage each DNG to a temp .dng file.
        var rawURLs: [URL] = []
        for rawData in rawDatas {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("dng")
            do {
                try rawData.write(to: url)
                rawURLs.append(url)
            } catch {
                rawURLs.forEach { try? FileManager.default.removeItem(at: $0) }
                finish(describe(error, context: "writing temp DNG"))
                return
            }
        }

        let isProRAW = isProRAWCapture
        PHPhotoLibrary.shared().performChanges {
            let rawOptions = PHAssetResourceCreationOptions()
            rawOptions.shouldMoveFile = true
            if rawURLs.count == 1, let processedData, isProRAW {
                // ProRAW: processed image is the primary photo, the DNG is the alternate.
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: processedData, options: nil)
                request.addResource(with: .alternatePhoto, fileURL: rawURLs[0], options: rawOptions)
            } else {
                // Bayer RAW / bracket frames: each DNG becomes its own asset.
                for url in rawURLs {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, fileURL: url, options: rawOptions)
                }
            }
        } completionHandler: { [weak self] success, error in
            // If shouldMoveFile consumed the files this is a harmless no-op.
            rawURLs.forEach { try? FileManager.default.removeItem(at: $0) }
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
