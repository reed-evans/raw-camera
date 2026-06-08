import AVFoundation
import Photos

// OWNER: wt/capture.
//
// AVCapturePhotoCaptureDelegate that collects RAW/ProRAW DNG data and saves it
// to the Photos library. Errors are forwarded via `onCaptureFinished` —
// never silently swallowed.

final class PhotoCaptureProcessor: NSObject {

    private let onCaptureFinished: ((String?) -> Void)?

    /// Accumulated DNG data from the RAW photo output.
    private var rawData: Data?
    /// Processed/compressed photo data for ProRAW (used as the alternatePhoto).
    private var processedData: Data?
    /// Whether the capture settings requested a ProRAW output.
    private var isProRAWCapture: Bool = false

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
            onCaptureFinished?(error.localizedDescription)
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
        if let error {
            onCaptureFinished?(error.localizedDescription)
            return
        }

        guard let rawData else {
            onCaptureFinished?("No RAW data received from capture.")
            return
        }

        saveToPhotos(rawData: rawData, processedData: processedData)
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
                self?.onCaptureFinished?(nil)
            } else {
                let message = error?.localizedDescription ?? "Unknown Photos library error."
                self?.onCaptureFinished?(message)
            }
        }
    }
}
