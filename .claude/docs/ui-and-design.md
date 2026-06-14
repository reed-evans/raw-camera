# UI & design language

The visual direction is **dark-luxury editorial / instrument**: a near-black surface, monospaced
labels, restrained chrome, system-blue slider fills and system-green switches, and a precision
artificial-horizon overlay. The app is **dark-appearance-locked** (`UIUserInterfaceStyle: Dark`)
and **portrait-locked**; overlays counter-rotate to face the user in landscape.

## Composition (`CameraScreen` — the composition root)

`CameraScreen` is a `ZStack` over the live preview:

1. `CameraMetalView` — the Metal camera preview (full screen, never rotated).
2. `LevelGuideView` — the artificial-horizon overlay (when enabled).
3. A bottom `VStack`: portrait histogram (when enabled) above the `ControlsPanel`.
4. Landscape histogram — a fixed strip at the far screen corner from the dock.
5. Floating overlays anchored to the panel: the zoom slider and the fine-tune overlay.

Orientation: `deviceAngle` comes from `UIDevice.orientation` (the UI itself stays portrait).
`facingUser(angle)` counter-rotates a control so it reads upright when the phone is sideways.
`physicalBottomLeading` maps physical edges to portrait edges.

## Control surface (`ControlsPanel`)

- A slim, always-docked **command bar**: status chip (RAW/ProRAW or error) · shutter · settings
  toggle. The panel is a Liquid Glass rounded-rect; its corner radius (40) is sized to read
  concentric with the phone's screen corners, inset a uniform 12pt so the rounded corners stay
  inside the display curve (matches the system dock).
- The **settings drawer** slides up: EXPOSURE · WHITE BAL · FOCUS · RATIO · MONITOR · FORMAT ·
  CAPTURE. Horizontally scrollable in portrait; counter-rotated as a transposed column in landscape
  (see the landscape gotchas before touching it).
- **A/M segments** (`ModeSegment`) toggle each axis between auto and manual.
- **Sliders** (`FineSlider` via `FSlider`/`DSlider`): grabbing the knob opens a full-width
  fine-tune overlay floated at the top of the screen with a large readout; the inline drag spreads
  the value range over ~3× the finger travel for finer control. The overlay is display-only (the
  finger stays on the inline slider). Knob is a capsule matching the native thumb; fill is system
  blue.
- **Switches** (`MiniToggleStyle`): system-style — green track when on, gray off, white capsule
  thumb. (When flattening overlapping translucent shapes, fill opaque + `.compositingGroup()` +
  `.opacity()` so overlaps don't double-brighten.)
- **Glass:** all glass goes through `LiquidGlass.swift` — `liquidGlass(in:)` for container
  backgrounds and `glassIconButton()`/`.buttonStyle(.glass)` for buttons, each with an iOS 17–25
  fallback. Never nest glass in glass (it swallows taps — see gotchas).

## Monitoring overlays

- **Histogram** (`HistogramView`): RGB + luma, `Canvas`-drawn, 256 bins. Portrait: above the panel.
  Landscape: a rotated strip at the far corner.
- **Level guide** (`LevelGuideView`): instrument-style artificial horizon —
  - a full-width green "laser" horizon line, **split into two segments** running from the center
    reference out to the screen edges, that rotate with roll; green only when level, muted white
    otherwise;
  - a fixed graduated **bezel ring** (minor ticks every 6°, longer majors every 30°);
  - a center reference **cross** (horizontal + vertical bars), drawn opaque + flattened so the
    overlap doesn't brighten, then made semi-transparent.
  `isLevel` / roll come from `CameraCore.Level` via `MotionManager` (CoreMotion).
- **Zebra & focus peaking:** Metal shader effects; thresholds, colors, and rotation flow to
  `CameraShaders.metal` through the frozen `PreviewUniforms` struct.
- **Zoom slider** (`ZoomSlider`): optional vertical on-screen zoom; pinch-to-zoom works regardless.

## Tokens / conventions

- Type: SF Mono (`design: .monospaced`) for labels/readouts; tracked, low-opacity whites for
  hierarchy.
- Color: system blue for slider fills, system green for switch-on, red reserved for the level
  guide's old style (now green-when-level). Otherwise white at graded opacities on near-black.
- Motion: short `easeOut` (0.12–0.18s) for state changes; a spring for the drawer.
- Animate compositor-friendly properties (transform/opacity); the preview and horizon line rotate
  via `rotationEffect`, never by reflowing layout.

See **gotchas.md** for the glass-tap, alignment-guide, measured-state, and landscape traps that
constrain how these are built.
