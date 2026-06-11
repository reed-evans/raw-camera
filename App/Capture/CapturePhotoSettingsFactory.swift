import AVFoundation
import CameraCore

// OWNER: wt/capture.
//
// Builds per-shot AVCapturePhotoSettings from the selected RAW format and the
// user's CaptureOptions. Kept out of CaptureService so the service stays a thin
// session/threading shell.
enum CapturePhotoSettingsFactory {

    /// Number of frames in a RAW exposure bracket.
    static let bracketCount = 3
    /// EV step between bracket frames (±2 EV around the metered exposure).
    static let bracketStops: Float = 2.0

    static func make(
        photoOutput: AVCapturePhotoOutput,
        device: AVCaptureDevice,
        rawFormat: RAWFormat?,
        options: CaptureOptions
    ) -> AVCapturePhotoSettings {
        if options.rawBracketing, let bracket = makeBracketSettings(photoOutput: photoOutput, device: device) {
            return bracket
        }

        let settings: AVCapturePhotoSettings
        if let rawFormat, photoOutput.availableRawPhotoPixelFormatTypes.contains(rawFormat.pixelFormat) {
            if rawFormat.isProRAW {
                settings = AVCapturePhotoSettings(
                    rawPixelFormatType: rawFormat.pixelFormat,
                    processedFormat: [AVVideoCodecKey: AVVideoCodecType.hevc]
                )
            } else {
                settings = AVCapturePhotoSettings(rawPixelFormatType: rawFormat.pixelFormat)
            }
        } else {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        }

        settings.photoQualityPrioritization = options.maxQuality ? .quality : .balanced
        if options.highResolution, let dims = largestPhotoDimensions(of: device) {
            settings.maxPhotoDimensions = dims
        }
        return settings
    }

    /// 3-shot Bayer-RAW exposure bracket (±2 EV, clamped to the device's bias
    /// range). Returns nil when the device/output can't bracket RAW — caller
    /// falls back to a single capture. Note: bracketing uses Bayer RAW; ProRAW
    /// fusion does not support bracketed capture.
    private static func makeBracketSettings(
        photoOutput: AVCapturePhotoOutput,
        device: AVCaptureDevice
    ) -> AVCapturePhotoBracketSettings? {
        let bayer = photoOutput.availableRawPhotoPixelFormatTypes
            .first(where: { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) })
        guard let bayer, photoOutput.maxBracketedCapturePhotoCount >= 2 else { return nil }

        let count = min(bracketCount, photoOutput.maxBracketedCapturePhotoCount)
        let biases = ExposureBracket.biases(
            count: count,
            stops: bracketStops,
            minBias: device.minExposureTargetBias,
            maxBias: device.maxExposureTargetBias
        )
        let frames = biases.map {
            AVCaptureAutoExposureBracketedStillImageSettings.autoExposureSettings(exposureTargetBias: $0)
        }
        return AVCapturePhotoBracketSettings(
            rawPixelFormatType: bayer,
            processedFormat: nil,
            bracketedSettings: frames
        )
    }

    /// The largest still-photo dimensions the active format supports (48MP on
    /// supporting hardware), or nil when only one size exists.
    static func largestPhotoDimensions(of device: AVCaptureDevice) -> CMVideoDimensions? {
        device.activeFormat.supportedMaxPhotoDimensions
            .max(by: { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) })
    }
}
