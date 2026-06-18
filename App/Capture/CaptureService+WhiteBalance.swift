import AVFoundation
import CameraCore
import Foundation

// OWNER: wt/capture.
//
// White-balance locking, split out of CaptureService.swift to keep that file
// focused. Manual WB converts temperature/tint to device gains with
// AVFoundation's `deviceWhiteBalanceGains(for:)` — the exact inverse of the
// `temperatureAndTintValues(for:)` used to report auto-WB values in
// CaptureService+DeviceValues — so the value shown in auto reproduces the same
// preview when entered manually.

extension CaptureService {

    func setWhiteBalance(temperature: Float, tint: Float) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDevice else { return }
            // Use AVFoundation's exact inverse of `temperatureAndTintValues(for:)`
            // (the function that reports auto-WB values). Hand-rolling the
            // temp/tint→gains math here would diverge from the displayed values,
            // so the same numbers must map back through the same model.
            let tempTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
                temperature: temperature, tint: tint)
            let rawGains = device.deviceWhiteBalanceGains(for: tempTint)
            // The conversion can yield gains above maxWhiteBalanceGain for extreme
            // values; setWhiteBalanceModeLocked throws (Obj-C) on out-of-range
            // gains, so clamp first.
            let clamped = WhiteBalance.clampGains(
                WhiteBalanceGains(
                    red: rawGains.redGain, green: rawGains.greenGain, blue: rawGains.blueGain),
                maxGain: device.maxWhiteBalanceGain)
            var deviceGains = AVCaptureDevice.WhiteBalanceGains()
            deviceGains.redGain = clamped.red
            deviceGains.greenGain = clamped.green
            deviceGains.blueGain = clamped.blue
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                device.setWhiteBalanceModeLocked(with: deviceGains, completionHandler: nil)
            } catch {
                self.logger.error("setWhiteBalance failed: \(error)")
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
}
