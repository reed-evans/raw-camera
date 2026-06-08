# CONTRACTS.md — FROZEN (Phase 0)

> **Orchestrator-mediated only.** No worktree edits this file. If a module needs
> a contract change, STOP and raise it to the orchestrator; the amendment is made
> here in Phase-0 space and both sides update simultaneously (§8). Contract drift
> — especially the `PreviewUniforms` layout (T1-7) — is the #1 risk.

Frozen at Phase-0 commit. Branch all Phase-1 worktrees from that commit.

---

## 1. Targets

| Target | Kind | Frameworks | Headless-testable |
| --- | --- | --- | --- |
| `CameraCore` | SPM library (`CameraCore/`) | Foundation, simd, CoreGraphics, CoreVideo | **Yes** |
| `RAWCamera` | iOS app (`App/`, xcodegen `project.yml`) | + AVFoundation, Metal(Kit), CoreMotion, Photos, SwiftUI | No (device) |
| `CameraCoreTests` | XCTest/Swift-Testing | `CameraCore` | **Yes** |

Build app: `xcodebuild -scheme RAWCamera -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
Test core: `cd CameraCore && swift test`
All gates: `./scripts/gates.sh all`

`CameraCore` imports **no Apple media-capture framework** (no AVFoundation / Metal /
CoreMotion / Photos). `CoreVideo` (CVPixelBuffer) and `CoreGraphics` (CGPoint) are
permitted — both build on the host with no camera.

---

## 2. Module ownership map (exclusive — contractual)

| Module | Worktree | Owns (app) | Owns (CameraCore logic + tests) |
| --- | --- | --- | --- |
| Capture stack | `wt/capture` | `App/Capture/CaptureService.swift`, `App/Capture/PhotoCaptureProcessor.swift` | `Exposure.swift`, `WhiteBalance.swift`, `RAWFormatSelector.swift` + their tests |
| Metal preview | `wt/metal` | `App/Monitoring/CameraMetalView.swift`, `App/Monitoring/CameraShaders.metal` | `Histogram.swift` + its tests |
| Controls UI | `wt/controls-ui` | `App/UI/ControlsPanel.swift` | — (binds to model only) |
| Monitoring UI | `wt/monitoring-ui` | `App/UI/HistogramView.swift`, `App/UI/LevelGuideView.swift`, `App/Monitoring/MotionManager.swift` | `Level.swift` + its tests |
| Integration | `wt/integration` (Phase 2) | `App/RAWCameraApp.swift`, `App/CameraModel.swift`, `App/UI/CameraScreen.swift`, `App/Info.plist`, `project.yml`, glue | — |

**Frozen contract files (no worktree edits):**
`CameraCore/Sources/CameraCore/Contracts/*` (PreviewUniforms, CameraTypes,
CameraCapturing), the `PreviewUniforms` struct in `CameraShaders.metal`, the
`@Observable` surface of `CameraModel.swift`, and the two Phase-0 guard tests
(`UniformLayoutTests`, `ContractConformanceTests`).

> The metal worker owns `CameraShaders.metal` but the `PreviewUniforms` struct
> inside it is frozen — it must stay byte-identical to §4. Reviewer enforces.

---

## 3. `CameraCapturing` (frozen protocol) — `Contracts/CameraCapturing.swift`

The capture stack conforms; `CameraModel` depends on `any CameraCapturing`.

```swift
public protocol CameraCapturing: AnyObject {
    var onVideoFrame: ((CVPixelBuffer) -> Void)? { get set }   // background queue
    var onConfigured: ((ExposureLimits, _ isProRAWAvailable: Bool) -> Void)? { get set }  // bg, post-startSession
    var onCaptureFinished: ((_ error: String?) -> Void)? { get set }  // bg; nil = DNG saved
    var exposureLimits: ExposureLimits { get }
    var isProRAWAvailable: Bool { get }
    func startSession()
    func stopSession()
    func capturePhoto()
    func focus(at point: CGPoint)   // normalized device coords 0...1, top-left origin
    func setManualExposure(iso: Float, shutterSeconds: Double)
    func setAutoExposure()
    func setWhiteBalance(_ gains: WhiteBalanceGains)
    func setAutoWhiteBalance()
    func setFocus(lensPosition: Float)
    func setAutoFocus()
    func setPreferProRAW(_ prefer: Bool)
}
```

**Threading:** `onVideoFrame`, `onConfigured`, `onCaptureFinished` fire on a
background queue — consumers hop to the main actor before touching observable
state. Session control + `capturePhoto` run AVFoundation work off the main thread
inside the implementation. (T2-4)

**Buffer lifetime:** the `CVPixelBuffer` in `onVideoFrame` is valid only for the
duration of the call; retain/copy if used past return (the pool recycles it).

**Amendment A1 (Phase 0):** `onConfigured` + `onCaptureFinished` added so the
real post-configuration `ExposureLimits`/ProRAW availability and capture
results reach `CameraModel` (which would otherwise be stuck at `.unset`/`false`).
`CameraModel.init` wires both. The Metal side of `PreviewUniforms` is now also
guarded at compile time by `static_assert` in `CameraShaders.metal` (T0-2).

**Amendment A2 (zoom):** `onZoomRange: ((CGFloat, CGFloat) -> Void)?` and
`func setZoom(factor: CGFloat)` added — the implementation clamps to the device
range. `CameraModel` exposes `zoomFactor`/`minZoom`/`maxZoom` and drives it from
pinch + an optional vertical slider (`showZoomSlider`).

---

## 4. `PreviewUniforms` — FROZEN ABI (grader T1-7)

`stride = 48`, `alignment = 16`. Shared byte-for-byte between
`Contracts/PreviewUniforms.swift` and the `struct PreviewUniforms` in
`CameraShaders.metal`.

| field | Swift | Metal | offset | size |
| --- | --- | --- | --- | --- |
| `peakingColor` | `SIMD4<Float>` | `float4` | 0 | 16 |
| `viewSize` | `SIMD2<Float>` | `float2` | 16 | 8 |
| `zebraThreshold` | `Float` | `float` | 24 | 4 |
| `peakingThreshold` | `Float` | `float` | 28 | 4 |
| `rotation` | `Float` | `float` | 32 | 4 |
| `zebraEnabled` | `UInt32` | `uint` | 36 | 4 |
| `peakingEnabled` | `UInt32` | `uint` | 40 | 4 |
| `_pad` | `UInt32` | `uint` | 44 | 4 |

Semantics: `zebraThreshold`/`peakingThreshold` in `0...1`; `*Enabled` are `0`/`1`;
`rotation` in radians; `viewSize` in drawable px; `peakingColor` is RGBA.

---

## 5. Value types — `Contracts/CameraTypes.swift` (frozen)

```swift
struct ExposureLimits { minISO, maxISO: Float; minShutterSeconds, maxShutterSeconds: Double }   // .unset
struct WhiteBalanceGains { red, green, blue: Float }   // each 1.0...maxGain; .neutral = (1,1,1)
struct HistogramData { red, green, blue, luma: [Float] }   // 256 bins each, 0...1; .empty; binCount = 256
```

`RAWFormat` lives in `RAWFormatSelector.swift` (owned by capture):
```swift
struct RAWFormat { pixelFormat: UInt32; isProRAW: Bool; isBayerRAW: Bool }
```

---

## 6. `CameraModel` published surface (frozen) — `App/CameraModel.swift`

`@MainActor @Observable final class CameraModel`. UI binds to these; integration
fills the bodies. Stored properties (all observable):

```
exposure:   isManualExposure, iso, shutterSeconds, exposureLimits
whiteBal:   isManualWhiteBalance, whiteBalanceTemperature, whiteBalanceTint, maxWhiteBalanceGain
focus:      isManualFocus, focusLensPosition
format:     preferProRAW, isProRAWAvailable
monitoring: zebraEnabled, zebraThreshold, focusPeakingEnabled, focusPeakingThreshold,
            histogramEnabled, levelGuideEnabled
data:       histogram (HistogramData), rollDegrees, pitchDegrees, isLevel
status:     isSessionRunning, lastCaptureError
```

Intents:
```
startSession() · stopSession() · capturePhoto() · focusTap(at:)
setManualExposure(iso:shutterSeconds:) · enableAutoExposure()
setWhiteBalance(temperature:tint:) · enableAutoWhiteBalance()
setFocus(lensPosition:) · enableAutoFocus() · setPreferProRAW(_:)
```

Frozen UI ranges (so `wt/controls-ui` binds without guessing):
`CameraModel.temperatureRange = 2500...8000` (K), `tintRange = -150...150`,
`lensPositionRange = 0...1`. ISO/shutter ranges come from `exposureLimits`.

**Writer ownership (Phase 1 → Phase 2):** monitoring-data props (`histogram`,
`rollDegrees`, `pitchDegrees`, `isLevel`) are *written by the integration node*,
which pumps `wt/metal`'s histogram producer and `wt/monitoring-ui`'s
`MotionManager` into the model on the main actor. Phase-1 workers expose pure
producers only; they do not write `CameraModel`.

**Monitoring toggle ownership:** the enable/threshold *controls* (`zebraEnabled`,
`zebraThreshold`, `focusPeakingEnabled`, `focusPeakingThreshold`,
`histogramEnabled`, `levelGuideEnabled`) are UI'd by `wt/controls-ui`.
`wt/monitoring-ui` only *renders* (`HistogramView`, `LevelGuideView`) and reads
those flags. This prevents both UI workers writing the same fields.

---

## 7. CameraCore pure-logic surfaces (Tier-1 graders)

Workers implement test-first; signatures frozen here.

| Grader | Symbol | Signature |
| --- | --- | --- |
| T1-1 | `Exposure.clampISO` | `(_ iso: Float, into: ExposureLimits) -> Float` |
| T1-1 | `Exposure.clampShutter` | `(_ seconds: Double, into: ExposureLimits) -> Double` |
| T1-2 | `WhiteBalance.clampGains` | `(_ gains: WhiteBalanceGains, maxGain: Float) -> WhiteBalanceGains` |
| T1-2 | `WhiteBalance.gains` | `(temperature: Float, tint: Float, maxGain: Float) -> WhiteBalanceGains` |
| T1-3 | `Histogram.normalize` | `(red:[Int], green:[Int], blue:[Int], luma:[Int]) -> HistogramData` |
| T1-4 | `Level.attitude` | `(gravity: SIMD3<Double>) -> Level.Attitude` (rollDegrees, pitchDegrees) |
| T1-4 | `Level.isLevel` | `(rollDegrees: Double, pitchDegrees: Double, threshold: Double) -> Bool` |
| T1-5 | `RAWFormatSelector.select` | `(from: [RAWFormat], preferProRAW: Bool) -> RAWFormat?` |

Behavioral contracts:
- **T1-1**: clamp into `[min,max]`; out-of-range in ⇒ boundary out; NaN-safe.
- **T1-2**: every output channel finite and within `1.0...maxGain`.
- **T1-3**: max bin ⇒ 1.0; all-zero input ⇒ `.empty` (no divide-by-zero); each output length 256.
- **T1-4**: known gravity vectors ⇒ expected roll/pitch; `isLevel` true iff `|roll|,|pitch| ≤ threshold`.
- **T1-5**: prefer+ProRAW present ⇒ a ProRAW format; ProRAW absent ⇒ Bayer; empty ⇒ nil.

---

## 8. Done definition per worktree

`DONE = Tier 0 green AND your Tier 1 tests green AND swift-reviewer APPROVES.`
Touch only OWNED files. Push pure logic into `CameraCore`, test-first.
