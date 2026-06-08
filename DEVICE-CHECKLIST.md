# Tier 3 — Human Device Gate (HARD STOP)

> **The autonomous build stops here.** Tiers 0–2 are green (build, Metal compile,
> lint, 80 `CameraCore` unit tests incl. the `PreviewUniforms` ABI parity guard,
> privacy keys, no-network, no deprecated orientation API). **None of the items
> below can be verified by CI** — the Simulator has no camera and RAW capture
> cannot run headlessly. A human must run this on a physical device. Do not let an
> agent mark these done.

## Run it

```bash
# 1. Open the generated project (xcodeproj is gitignored — regenerate first)
cd /Users/reed/workspace/raw-camera
xcodegen generate
open RAWCamera.xcodeproj

# 2. Select your device + your signing team (Signing & Capabilities), then Run.
#    Requires a device with a rear camera; ProRAW items need a Pro iPhone
#    (12 Pro or later) with ProRAW-capable hardware.
```

## Checklist (BUILD-PLAN §6, Tier 3)

- [ ] **ProRAW capture** saves a DNG that opens in Photos / Lightroom
- [ ] **Bayer RAW capture** saves a DNG (device without ProRAW, or ProRAW toggled off)
- [ ] **Manual shutter & ISO** visibly change exposure; **auto ⇄ manual** toggles cleanly
      (tapping **M** should engage manual immediately, not only after moving a slider)
- [ ] **White-balance** slider shifts color; **focus** slider racks focus end to end
- [ ] **Zebra** stripes appear on blown highlights at threshold; toggle works
- [ ] **Focus peaking** highlights in-focus edges and tracks as you rack focus
- [ ] **Live histogram** tracks the scene; RGB + luma channels look right
- [ ] **Level guide** reads ~0° on a flat surface; tracks tilt (snaps green when level)
- [ ] **No frame-rate collapse** with all overlays on (watch thermals)

## What the machine already proved (so you can focus on the above)

- App compiles for `iphoneos`; Metal shaders compile (zebra + focus-peaking +
  histogram kernel).
- `PreviewUniforms` is byte-identical Swift↔Metal (stride 48 / align 16) — verified by
  a `MemoryLayout` test **and** a Metal `static_assert`. The preview will read correct
  uniforms.
- Pure math is unit-tested headlessly: exposure clamp (NaN-safe), WB gains (finite,
  in `1.0…maxGain`), histogram normalization (max→1.0, empty→no divide-by-zero), level
  math (atan2 roll/pitch + threshold), RAW-format selection (ProRAW pref + Bayer
  fallback). **80 tests.**
- Offline & private: no networking/exfil anywhere; `NSCameraUsageDescription` +
  `NSPhotoLibraryAddUsageDescription` present and honest; no ATS bypass; no secrets.
- Threading reviewed: session/capture work on a serial session queue; CoreMotion on a
  background queue; GPU on a render queue; all `@Observable` writes hop to the main actor.

## Known notes carried in from review (verify on device)

- Frame upload dispatches the `CVPixelBuffer` to the render queue (ARC keeps it alive —
  safe), with `alwaysDiscardsLateVideoFrames = true` and a per-frame texture-cache
  flush. **Watch for frame drops / pool stalls under sustained capture** with all
  overlays on; if seen, move the texture-cache upload to be fully synchronous in the
  `onVideoFrame` call.
- Preview rotation is applied once via the capture connection's `videoRotationAngle`
  (uniform `rotation` = 0 to avoid double-rotation). Confirm orientation looks right in
  portrait + landscape.
- WB temp/tint → gains uses a green-pinned daylight model; outputs are in-range but the
  exact color response under non-zero tint is approximate — confirm the slider "feels"
  right to a colorist.
