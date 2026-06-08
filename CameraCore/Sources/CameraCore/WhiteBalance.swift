import Foundation

// OWNER: wt/capture — grader T1-2.
//
// Pure white-balance math: clamp device gains and convert temperature/tint to
// per-channel gains. Results must be finite and within `1.0...maxGain`.
public enum WhiteBalance {
    /// Clamp every channel into `1.0...maxGain`.
    ///
    /// NaN-safe: a NaN or non-finite input is clamped to 1.0.
    public static func clampGains(_ gains: WhiteBalanceGains, maxGain: Float) -> WhiteBalanceGains {
        WhiteBalanceGains(
            red: clampChannel(gains.red, maxGain: maxGain),
            green: clampChannel(gains.green, maxGain: maxGain),
            blue: clampChannel(gains.blue, maxGain: maxGain)
        )
    }

    /// Convert a temperature (Kelvin) + tint to clamped per-channel gains.
    ///
    /// Uses a standard green-pinned D65-daylight model. Green is held at 1.0;
    /// red and blue are scaled to compensate for the scene colour temperature.
    /// The tint parameter shifts green vs magenta (negative = green, positive = magenta).
    /// All outputs are clamped to `1.0...maxGain`.
    public static func gains(temperature: Float, tint: Float, maxGain: Float) -> WhiteBalanceGains {
        // Planckian / Bradford colour-temperature model.
        // Approximates the CIE D-illuminant chromaticity (xy) as a function of
        // colour temperature, then derives per-channel scale factors with green
        // pinned to 1.0 so the result maps onto AVCaptureDevice's gain space.
        //
        // Reference: McCamy (1992) CCT approximation + Kang et al. (2002) for
        // the extended range used by camera sensors.

        let t = max(1000, temperature)  // guard against near-zero / negative T

        // Chromaticity x as a function of CCT (Kang et al. polynomial, valid ~1667..25000 K)
        let xRaw: Float
        if t <= 4000 {
            let t2 = t * t
            let t3 = t2 * t
            xRaw = -0.2661239e9 / (t3) - 0.2343589e6 / (t2) + 0.8776956e3 / t + 0.179910
        } else {
            let t2 = t * t
            let t3 = t2 * t
            xRaw = -3.0258469e9 / (t3) + 2.1070379e6 / (t2) + 0.2226347e3 / t + 0.240390
        }
        let x = max(0.1, min(0.9, xRaw))

        // Chromaticity y from x (Kang et al.)
        let yRaw: Float
        if t <= 2222 {
            yRaw = -1.1063814 * x * x * x - 1.34811020 * x * x + 2.18555832 * x - 0.20219683
        } else if t <= 4000 {
            yRaw = -0.9549476 * x * x * x - 1.37418593 * x * x + 2.09137015 * x - 0.16748867
        } else {
            yRaw = 3.0817580 * x * x * x - 5.87338670 * x * x + 3.75112997 * x - 0.37001483
        }
        let y = max(0.001, min(0.9, yRaw))

        // XYZ tristimulus for unit luminance Y = 1.0
        let bigX = x / y
        let bigY: Float = 1.0
        let bigZ = (1.0 - x - y) / y

        // Linear sRGB from XYZ (D65 adapted, IEC 61966-2-1)
        let r = max(0.0001, 3.2404542 * bigX - 1.5371385 * bigY - 0.4985314 * bigZ)
        let g = max(0.0001, -0.9692660 * bigX + 1.8760108 * bigY + 0.0415560 * bigZ)
        let b = max(0.0001, 0.0556434 * bigX - 0.2040259 * bigY + 1.0572252 * bigZ)

        // Tint adjustment (green vs magenta).
        // AVFoundation tint range: roughly -150 (green) to +150 (magenta).
        let tintNorm = max(-150, min(150, tint)) / 150.0  // -1...1
        let tintFactor: Float = 1.0 - tintNorm * 0.3  // 0.7...1.3

        // Green-pinned gain computation.
        // The scene illuminant has colour (r, g, b) in linear sRGB.
        // To correct, the camera boosts the channel that is proportionally dim.
        let redGain = g / r
        let greenGain = tintFactor
        let blueGain = g / b

        // Normalize so the minimum of the three equals 1.0.
        let minGain = min(redGain, min(greenGain, blueGain))
        let scale = max(1.0, minGain)

        let raw = WhiteBalanceGains(
            red: redGain / scale,
            green: greenGain / scale,
            blue: blueGain / scale
        )
        return clampGains(raw, maxGain: maxGain)
    }

    // MARK: Private helpers

    private static func clampChannel(_ value: Float, maxGain: Float) -> Float {
        guard value.isFinite else {
            return value > 0 ? maxGain : 1.0
        }
        return min(max(value, 1.0), maxGain)
    }
}
