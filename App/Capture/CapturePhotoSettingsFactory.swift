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
        var isPlainRAW = false
        if let rawFormat, photoOutput.availableRawPhotoPixelFormatTypes.contains(rawFormat.pixelFormat) {
            if rawFormat.isProRAW {
                settings = AVCapturePhotoSettings(
                    rawPixelFormatType: rawFormat.pixelFormat,
                    processedFormat: [AVVideoCodecKey: AVVideoCodecType.hevc]
                )
            } else {
                settings = AVCapturePhotoSettings(rawPixelFormatType: rawFormat.pixelFormat)
                isPlainRAW = true
            }
        } else {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        }

        if isPlainRAW {
            // photoQualityPrioritization applies to the PROCESSED photo; a
            // RAW-only capture has none, so setting it throws an (uncatchable)
            // "Unsupported when capturing RAW" exception. ProRAW is exempt — it
            // carries a processed HEVC companion. Pin dimensions to the
            // sensor-native size too, so we don't inherit the output's raised
            // 48MP ceiling (which plain Bayer RAW also can't produce).
            settings.maxPhotoDimensions = sensorDimensions(of: device)
        } else {
            settings.photoQualityPrioritization = options.maxQuality ? .quality : .balanced
            if options.highResolution, let dims = largestPhotoDimensions(of: device) {
                settings.maxPhotoDimensions = dims
            }
        }
        return settings
    }

    /// The active format's source (sensor-readout) dimensions — the size plain
    /// Bayer RAW is captured at, and always a valid RAW `maxPhotoDimensions`.
    static func sensorDimensions(of device: AVCaptureDevice) -> CMVideoDimensions {
        CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
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
        let settings = AVCapturePhotoBracketSettings(
            rawPixelFormatType: bayer,
            processedFormat: nil,
            bracketedSettings: frames
        )
        // Same Bayer-RAW vs inherited-48MP-ceiling crash as the single-shot path.
        settings.maxPhotoDimensions = sensorDimensions(of: device)
        return settings
    }

    /// The largest still-photo dimensions the active format supports (48MP on
    /// supporting hardware), or nil when only one size exists.
    static func largestPhotoDimensions(of device: AVCaptureDevice) -> CMVideoDimensions? {
        device.activeFormat.supportedMaxPhotoDimensions
            .max(by: { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) })
    }
}
