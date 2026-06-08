import AVFoundation
import CameraCore
import CoreGraphics
import CoreVideo
import os.log

// OWNER: wt/capture.
//
// A thin AVFoundation shell that delegates all pure math to CameraCore.
// Threading (T2-4): ALL session/config/capture work runs on `sessionQueue`
// (serial DispatchQueue), never on the main thread. Callbacks fire on
// background queues — consumers hop to the main actor before touching state.

final class CaptureService: NSObject, CameraCapturing {

    // MARK: CameraCapturing

    var onVideoFrame: ((CVPixelBuffer) -> Void)?
    var onConfigured: ((ExposureLimits, Bool) -> Void)?
    var onCaptureFinished: ((String?) -> Void)?
    var onZoomRange: ((CGFloat, CGFloat) -> Void)?

    /// Usable preview zoom is capped well below the device's huge digital max.
    private static let maxUsableZoom: CGFloat = 10.0
    private(set) var exposureLimits: ExposureLimits = .unset
    private(set) var isProRAWAvailable: Bool = false

    // MARK: Private state

    private let sessionQueue = DispatchQueue(label: "com.rawcamera.sessionQueue", qos: .userInitiated)
    private let session = AVCaptureSession()
    private var videoDevice: AVCaptureDevice?
    private var photoOutput: AVCapturePhotoOutput?
    private var preferProRAW: Bool = true
    private var selectedRAWFormat: RAWFormat?
    private let logger = Logger(subsystem: "com.rawcamera", category: "CaptureService")
    /// Active capture delegates, retained across the async Photos save so
    /// `onCaptureFinished` is never dropped. AVFoundation does not retain the
    /// delegate, so we own it here and release it when the capture terminates.
    /// Mutated only on `sessionQueue`.
    private var activeProcessors: Set<PhotoCaptureProcessor> = []

    // MARK: Init

    override init() {
        super.init()
        registerSessionObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: Session lifecycle

    func startSession() {
        sessionQueue.async { [weak self] in
            self?.configureSession()
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    // MARK: Photo capture

    func capturePhoto() {
        sessionQueue.async { [weak self] in
            self?.performCapturePhoto()
        }
    }

    // MARK: Focus

    func focus(at point: CGPoint) {
        sessionQueue.async { [weak self] in
            guard let device = self?.videoDevice else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = point }
                if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            } catch {
                self?.logger.error("focus(at:) failed: \(error)")
            }
        }
    }

    // MARK: Exposure

    func setManualExposure(iso: Float, shutterSeconds: Double) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDevice else { return }
            let clampedISO = Exposure.clampISO(iso, into: self.exposureLimits)
            let clampedShutter = Exposure.clampShutter(shutterSeconds, into: self.exposureLimits)
            let duration = CMTime(seconds: clampedShutter, preferredTimescale: 1_000_000)
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                device.setExposureModeCustom(duration: duration, iso: clampedISO, completionHandler: nil)
            } catch {
                self.logger.error("setManualExposure failed: \(error)")
            }
        }
    }

    func setAutoExposure() {
        sessionQueue.async { [weak self] in
            guard let device = self?.videoDevice else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
            } catch {
                self?.logger.error("setAutoExposure failed: \(error)")
            }
        }
    }

    // MARK: White balance

    func setWhiteBalance(_ gains: WhiteBalanceGains) {
        sessionQueue.async { [weak self] in
            guard let device = self?.videoDevice else { return }
            let clamped = WhiteBalance.clampGains(gains, maxGain: device.maxWhiteBalanceGain)
            var deviceGains = AVCaptureDevice.WhiteBalanceGains()
            deviceGains.redGain = clamped.red
            deviceGains.greenGain = clamped.green
            deviceGains.blueGain = clamped.blue
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                device.setWhiteBalanceModeLocked(with: deviceGains, completionHandler: nil)
            } catch {
                self?.logger.error("setWhiteBalance failed: \(error)")
            }
        }
    }

    func setAutoWhiteBalance() {
        sessionQueue.async { [weak self] in
            guard let device = self?.videoDevice else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                }
            } catch {
                self?.logger.error("setAutoWhiteBalance failed: \(error)")
            }
        }
    }

    // MARK: Focus (manual lens position)

    func setFocus(lensPosition: Float) {
        sessionQueue.async { [weak self] in
            guard let device = self?.videoDevice else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                device.setFocusModeLocked(lensPosition: min(max(lensPosition, 0), 1), completionHandler: nil)
            } catch {
                self?.logger.error("setFocus(lensPosition:) failed: \(error)")
            }
        }
    }

    func setAutoFocus() {
        sessionQueue.async { [weak self] in
            guard let device = self?.videoDevice else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            } catch {
                self?.logger.error("setAutoFocus failed: \(error)")
            }
        }
    }

    // MARK: RAW format preference

    func setPreferProRAW(_ prefer: Bool) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.preferProRAW = prefer
            self.updateSelectedRAWFormat()
        }
    }

    func setZoom(factor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDevice else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                let lo = device.minAvailableVideoZoomFactor
                let hi = min(device.maxAvailableVideoZoomFactor, CaptureService.maxUsableZoom)
                device.videoZoomFactor = min(max(factor, lo), hi)
            } catch {
                self.logger.error("setZoom failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

// MARK: - Session configuration (fileprivate helpers)

extension CaptureService {
    fileprivate func configureSession() {
        guard let device = discoverBackCamera() else { return }
        guard let deviceInput = (try? AVCaptureDeviceInput(device: device)) else {
            logger.error("Could not create AVCaptureDeviceInput.")
            return
        }
        let videoDataOutput = makeVideoDataOutput()
        let capturePhotoOutput = AVCapturePhotoOutput()
        self.photoOutput = capturePhotoOutput

        guard addSessionIO(deviceInput: deviceInput, videoDataOutput: videoDataOutput, photoOutput: capturePhotoOutput) else {
            return
        }
        // ProRAW pixel formats only appear in availableRawPhotoPixelFormatTypes
        // once ProRAW is enabled — must be set inside the configuration block.
        if capturePhotoOutput.isAppleProRAWSupported {
            capturePhotoOutput.isAppleProRAWEnabled = true
        }
        if let connection = videoDataOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90  // T2-3: videoRotationAngle, not videoOrientation
        }
        session.commitConfiguration()
        finalizeConfiguration(device: device, photoOutput: capturePhotoOutput)
        session.startRunning()
    }

    private func discoverBackCamera() -> AVCaptureDevice? {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            logger.error("No back camera available.")
            return nil
        }
        videoDevice = device
        return device
    }

    private func makeVideoDataOutput() -> AVCaptureVideoDataOutput {
        let output = AVCaptureVideoDataOutput()
        // The Metal preview uploads each frame as a single BGRA texture, so the
        // capture output must deliver BGRA (the default is biplanar YUV, which
        // fails CVMetalTextureCacheCreateTextureFromImage and renders black).
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        output.setSampleBufferDelegate(self, queue: sessionQueue)
        output.alwaysDiscardsLateVideoFrames = true
        return output
    }

    private func addSessionIO(
        deviceInput: AVCaptureDeviceInput,
        videoDataOutput: AVCaptureVideoDataOutput,
        photoOutput: AVCapturePhotoOutput
    ) -> Bool {
        session.beginConfiguration()
        session.sessionPreset = .photo
        guard session.canAddInput(deviceInput) else {
            logger.error("Cannot add device input.")
            session.commitConfiguration()
            return false
        }
        session.addInput(deviceInput)
        guard session.canAddOutput(videoDataOutput) else {
            logger.error("Cannot add video data output.")
            session.commitConfiguration()
            return false
        }
        session.addOutput(videoDataOutput)
        guard session.canAddOutput(photoOutput) else {
            logger.error("Cannot add photo output.")
            session.commitConfiguration()
            return false
        }
        session.addOutput(photoOutput)
        return true
    }

    private func finalizeConfiguration(device: AVCaptureDevice, photoOutput: AVCapturePhotoOutput) {
        let fmt = device.activeFormat
        let limits = ExposureLimits(
            minISO: fmt.minISO,
            maxISO: fmt.maxISO,
            minShutterSeconds: CMTimeGetSeconds(fmt.minExposureDuration),
            maxShutterSeconds: CMTimeGetSeconds(fmt.maxExposureDuration)
        )
        exposureLimits = limits
        isProRAWAvailable = photoOutput.isAppleProRAWSupported
        updateSelectedRAWFormat()
        onConfigured?(limits, isProRAWAvailable)
        let maxZoom = min(device.maxAvailableVideoZoomFactor, CaptureService.maxUsableZoom)
        onZoomRange?(device.minAvailableVideoZoomFactor, maxZoom)
    }

    fileprivate func updateSelectedRAWFormat() {
        guard let photoOutput else { return }
        let rawFormats: [RAWFormat] = photoOutput.availableRawPhotoPixelFormatTypes.map { fmt in
            RAWFormat(
                pixelFormat: fmt,
                isProRAW: AVCapturePhotoOutput.isAppleProRAWPixelFormat(fmt),
                isBayerRAW: AVCapturePhotoOutput.isBayerRAWPixelFormat(fmt)
            )
        }
        selectedRAWFormat = RAWFormatSelector.select(from: rawFormats, preferProRAW: preferProRAW)
    }

    fileprivate func performCapturePhoto() {
        guard let photoOutput else {
            onCaptureFinished?("Photo output not configured.")
            return
        }
        let settings = buildCaptureSettings(photoOutput: photoOutput)
        let processor = PhotoCaptureProcessor(onCaptureFinished: onCaptureFinished)
        // Retain the delegate across the async Photos save; release it when the
        // capture terminates so it isn't deallocated mid-flight (and the result
        // isn't dropped). `completion` and the set mutation stay on sessionQueue.
        processor.onComplete = { [weak self] finished in
            self?.sessionQueue.async { self?.activeProcessors.remove(finished) }
        }
        activeProcessors.insert(processor)
        photoOutput.capturePhoto(with: settings, delegate: processor)
    }

    private func buildCaptureSettings(photoOutput: AVCapturePhotoOutput) -> AVCapturePhotoSettings {
        guard let rawFormat = selectedRAWFormat,
            photoOutput.availableRawPhotoPixelFormatTypes.contains(rawFormat.pixelFormat)
        else {
            return AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        }
        if rawFormat.isProRAW {
            return AVCapturePhotoSettings(
                rawPixelFormatType: rawFormat.pixelFormat,
                processedFormat: [AVVideoCodecKey: AVVideoCodecType.hevc]
            )
        }
        return AVCapturePhotoSettings(rawPixelFormatType: rawFormat.pixelFormat)
    }
}

// MARK: - Session interruption & runtime-error recovery

extension CaptureService {
    fileprivate func registerSessionObservers() {
        let center = NotificationCenter.default
        center.addObserver(
            self, selector: #selector(sessionRuntimeError(_:)),
            name: .AVCaptureSessionRuntimeError, object: session)
        center.addObserver(
            self, selector: #selector(sessionWasInterrupted(_:)),
            name: .AVCaptureSessionWasInterrupted, object: session)
        center.addObserver(
            self, selector: #selector(sessionInterruptionEnded(_:)),
            name: .AVCaptureSessionInterruptionEnded, object: session)
    }

    /// A runtime error stops the session. Media-services resets are recoverable —
    /// restart on the session queue. (Notifications arrive on an internal queue.)
    @objc private func sessionRuntimeError(_ note: Notification) {
        let nsError = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
        let desc = nsError?.localizedDescription ?? "unknown"
        let code = nsError?.code ?? 0
        logger.error("Session runtime error: \(desc, privacy: .public) (code \(code))")
        guard code == AVError.Code.mediaServicesWereReset.rawValue else { return }
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
            self.logger.notice("Session restarted after media-services reset.")
        }
    }

    /// The system took the camera (call, Control Center, another app, resource
    /// pressure). Log the reason; the preview pauses until the interruption ends.
    @objc private func sessionWasInterrupted(_ note: Notification) {
        let raw = (note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber)?.intValue
        let reason = raw.flatMap(AVCaptureSession.InterruptionReason.init(rawValue:))
        logger.notice("Session interrupted (reason: \(reason?.rawValue ?? -1)).")
    }

    /// Interruption ended — resume the session so the preview comes back.
    @objc private func sessionInterruptionEnded(_ note: Notification) {
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
            self.logger.notice("Session resumed after interruption.")
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onVideoFrame?(pixelBuffer)
    }
}
