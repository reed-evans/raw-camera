# Gotchas — hard-won traps in this codebase

Non-obvious failures that have actually happened here. Most are *not* caught by the build —
they need the simulator UI-test/screenshot harness or a device. Read before touching capture
settings or the SwiftUI overlays.

## AVFoundation / capture

- **`photoQualityPrioritization` is unsupported for RAW-only captures.** Setting it on a plain
  Bayer-RAW `AVCapturePhotoSettings` (no processed format) throws an uncatchable
  `NSInvalidArgumentException` ("Unsupported when capturing RAW") → instant crash on the shutter
  tap, **only** in plain-RAW mode. ProRAW is exempt (it carries a processed HEVC companion).
  Fix in `CapturePhotoSettingsFactory`: only set it when *not* plain RAW.
- **`AVCapturePhotoSettings` inherit the output's raised `maxPhotoDimensions`.** `CaptureService`
  raises `photoOutput.maxPhotoDimensions` to the largest (48MP) so ProRAW can opt in; every
  settings object then defaults to that ceiling. Plain Bayer RAW can't produce 48MP, so pin
  plain-RAW/bracket settings to the sensor-native size
  `CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)`.
- **Auto-WB transients crash `temperatureAndTintValues(for:)`.** The device can momentarily report
  `deviceWhiteBalanceGains` outside `[1, maxWhiteBalanceGain]` (or non-finite); the converter
  throws `NSRangeException`. Always route observed gains through `WhiteBalance.clampGains` before
  converting (see `CaptureService+DeviceValues`).
- **Simulator pins ISO/shutter.** With no camera, `exposureLimits` is degenerate and `clampISO`
  pins ISO/shutter to a fixed value — they never change in the sim even though the code is correct.
  White-balance and **focus** use static ranges and *do* change. UI tests that need a manual
  control's value to move must drive **FOCUS** (or WB), never ISO/SS.
- **General rule:** `capturePhoto(with:delegate:)` validates settings synchronously and throws
  ObjC exceptions (uncatchable in Swift) for invalid combos. When capture "immediately crashes,"
  get the crash log — the `NSException` reason names the exact bad parameter. Don't guess from the
  symptom.

## SwiftUI / Liquid Glass

- **Glass nested inside glass swallows touches (iOS 26).** A `glassEffect` (even non-interactive,
  even as a `.background`) applied to a view *inside* another glass surface silently eats taps on
  controls within it. The accessibility tree looks fine; the tap just never fires. Buttons must get
  glass from `.buttonStyle(.glass)` / `.glassProminent` (the button style owns hit-testing), never
  from a glass label background. Container surfaces use the `liquidGlass(in:)` background helper
  (`LiquidGlass.swift`, with an iOS 17–25 material fallback). Verified by `ControlsPanelUITests` on
  an iOS 26.5 sim — an 18.x-only test passes even when 26 is broken, so **test both runtimes**.
- **Padding after an explicit `.alignmentGuide` is silently eaten.** When a view has a custom
  alignment guide, a `.padding` applied afterward doesn't shift the guide. Put the gap *inside* the
  guide computation instead.
- **Read-dependency drop: measured @State that nothing reads doesn't get its writes serviced.**
  Positioning an overlay by copying a measured size into `@State` (via `onGeometryChange`) failed
  on first reveal: while the only reader was behind an `if`, SwiftUI effectively dropped writes to
  that state, so the overlay mounted against a stale value and only self-corrected on a later
  remount. **A debug `Text` that reads the value makes the bug vanish** (Heisenbug) — so any probe
  that reads the state invalidates the experiment. Fix: derive overlay positions by **layout**
  (anchor as an `.overlay` on the target, alignment guides) instead of measuring into state.

## Landscape (portrait-locked + counter-rotated overlays)

The interface is portrait-locked; floating overlays counter-rotate via `facingUser(angle)` to face
the user. This has produced repeated layout failures:

- **Do NOT transpose/measure a drawer section's layout box** (swap width/height, ask for ideal
  size, `.fixedSize()`): the sections have no rigid intrinsic size (they fill the proposed width)
  and collapse into an overlapping pile, in **both** orientations. Slider rows must be **width-
  pinned** (a fixed frame) — the landscape transpose proposes the panel's long dimension as width,
  and an unpinned row expands to fill it, blowing the panel up to full screen.
- **Prefer fixed screen positions or panel-anchored overlays** over panel-size measurement. The
  zoom slider and fine-tune overlay anchor as `.overlay` on the panel; the landscape histogram is a
  fixed screen-corner position. None measure the panel anymore.
- Physical edges map to portrait edges via `physicalBottomLeading` (`deviceAngle == 90`). "Physical
  top" in landscape = the portrait edge opposite the dock.

## Verifying landscape / UI changes

Landscape can't be reasoned about blind — use the harness:
1. Write a throwaway `AppUITests/ProbeTests.swift` that launches the app (optionally with a debug
   launch-arg seam to force state), rotates via `XCUIDevice.shared.orientation = .landscapeLeft`,
   and attaches `app.screenshot()` as a `keepAlways` XCTAttachment.
2. Run it; export with `xcrun xcresulttool export attachments --path <xcresult> --output-path …`,
   then read/crop the PNG (`sips -c H W`).
3. **Set device orientation AFTER `app.launch()`** — a pre-launch set is silently swallowed when
   the sim's orientation state is stale (deterministic failure until `simctl shutdown && boot`).
4. Delete the probe and re-run the real gates before finishing.

When asserting taps, there are multiple identical controls (e.g. three "M" segments, several
unlabeled `switches`) and accessibility order is **not stable across orientations** — pick the
element nearest the relevant section label, never `firstMatch`.
