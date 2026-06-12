import AVFoundation
import CameraCore
import Foundation

// OWNER: wt/capture.
//
// Live exposure / white-balance / focus observation, split out of
// CaptureService.swift to keep that file focused. KVO change handlers arrive on
// an internal AVFoundation queue; `emitDeviceValues` throttles and forwards on
// that background queue (consumers hop to the main actor), per the callback
// contract on `CameraCapturing.onDeviceValues`.

extension CaptureService {

    /// Minimum spacing between `onDeviceValues` emits — KVO fires far faster
    /// than any readout needs.
    private static let deviceValueInterval: TimeInterval = 0.2  // ~5 Hz

    /// Observe the device's live exposure/WB/focus so `onDeviceValues` can feed
    /// read-only readouts in auto mode.
    func observeDeviceValues(_ device: AVCaptureDevice) {
        // Each keypath yields a differently-typed change, so the handlers can't
        // share one closure; all ignore the change and re-read from the device.
        deviceValueObservations = [
            device.observe(\.iso) { [weak self] dev, _ in self?.emitDeviceValues(from: dev) },
            device.observe(\.exposureDuration) { [weak self] dev, _ in self?.emitDeviceValues(from: dev) },
            device.observe(\.deviceWhiteBalanceGains) { [weak self] dev, _ in self?.emitDeviceValues(from: dev) },
            device.observe(\.lensPosition) { [weak self] dev, _ in self?.emitDeviceValues(from: dev) },
        ]
    }

    func emitDeviceValues(from device: AVCaptureDevice) {
        guard onDeviceValues != nil else { return }
        deviceValueLock.lock()
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastDeviceValueEmit >= CaptureService.deviceValueInterval else {
            deviceValueLock.unlock()
            return
        }
        lastDeviceValueEmit = now
        deviceValueLock.unlock()

        // During auto-WB transients the device can report gains outside
        // [1, maxWhiteBalanceGain] (or non-finite); the converter throws
        // NSRangeException on those, so clamp before converting.
        let raw = device.deviceWhiteBalanceGains
        let clamped = WhiteBalance.clampGains(
            WhiteBalanceGains(red: raw.redGain, green: raw.greenGain, blue: raw.blueGain),
            maxGain: device.maxWhiteBalanceGain)
        var safeGains = AVCaptureDevice.WhiteBalanceGains()
        safeGains.redGain = clamped.red
        safeGains.greenGain = clamped.green
        safeGains.blueGain = clamped.blue
        let tempTint = device.temperatureAndTintValues(for: safeGains)
        onDeviceValues?(
            DeviceValues(
                iso: device.iso,
                shutterSeconds: CMTimeGetSeconds(device.exposureDuration),
                whiteBalanceTemperature: tempTint.temperature,
                whiteBalanceTint: tempTint.tint,
                lensPosition: device.lensPosition
            )
        )
    }
}
