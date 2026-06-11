import CameraCore
import CoreVideo
import Metal
import MetalKit
import SwiftUI
import simd

// OWNER: wt/metal.
//
// MTKView-backed live preview. Each `CVPixelBuffer` from the capture stack is
// uploaded into an `MTLTexture` via `CVMetalTextureCache` (no per-frame CPU
// copy), then rendered full-screen with the zebra + focus-peaking passes driven
// by a `PreviewUniforms` buffer (setFragmentBytes, buffer index 0). A compute
// kernel accumulates per-channel + luma histogram bin counts into a reused
// `MTLBuffer`; the integer counts are read back and normalized by
// `CameraCore.Histogram` — NO normalization logic lives in this view or the
// shader.
//
// Threading (T2-4): GPU encode + frame upload run on a private serial queue, off
// the main thread. Only `@Observable`/main-actor writes hop to the main actor —
// here, the histogram producer's callback is dispatched to `.main`. The view
// itself never writes `CameraModel`; it exposes a pure producer the integration
// node pumps into the model on the main actor (CONTRACTS §6 writer ownership).

// HistogramProducer and FramePump live in FramePump.swift.

// MARK: - UIViewRepresentable

struct CameraMetalView: UIViewRepresentable {
    let model: CameraModel
    /// Producer the integration node wires into `CameraModel.histogram`.
    let histogramProducer: HistogramProducer
    /// Frame entry the integration node pumps from `onVideoFrame`.
    let framePump: FramePump

    init(
        model: CameraModel,
        histogramProducer: HistogramProducer = HistogramProducer(),
        framePump: FramePump = FramePump()
    ) {
        self.model = model
        self.histogramProducer = histogramProducer
        self.framePump = framePump
    }

    func makeCoordinator() -> MetalRenderer {
        MetalRenderer(histogramProducer: histogramProducer, framePump: framePump)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = context.coordinator.device
        view.backgroundColor = .black
        view.framebufferOnly = false  // compute kernel may sample the drawable
        view.colorPixelFormat = .bgra8Unorm
        view.delegate = context.coordinator
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 30
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        // Snapshot the (main-actor) monitoring controls into the renderer via the
        // integration node's derived `PreviewUniforms` (toggles, thresholds,
        // peakingColor, rotation). The renderer keeps `viewSize` per-drawable.
        context.coordinator.updateUniforms(
            model.previewUniforms,
            histogramEnabled: model.histogramEnabled,
            aspectRatio: model.aspectRatio.ratio)
    }
}

// MARK: - Renderer

/// Owns all Metal state. Pipeline state, command queue, texture cache, and the
/// histogram buffer are created once and reused — no per-frame allocations.
final class MetalRenderer: NSObject, MTKViewDelegate, @unchecked Sendable {
    /// `nil` only on configurations without a Metal device (rare Simulators);
    /// the renderer then stays inert and every encode path short-circuits.
    let device: MTLDevice?

    private let commandQueue: MTLCommandQueue?
    private let renderPipeline: MTLRenderPipelineState?
    private let histogramPipeline: MTLComputePipelineState?
    private var textureCache: CVMetalTextureCache?

    /// Reused histogram bin buffer: 4 channels × 256 bins of `UInt32`.
    private let histogramBuffer: MTLBuffer?
    private static let binCount = HistogramData.binCount
    private static let channelCount = 4
    private static let totalBins = binCount * channelCount

    /// Serial queue for all GPU encode + frame upload work (off main).
    private let renderQueue = DispatchQueue(label: "wt.metal.render", qos: .userInteractive)

    private let histogramProducer: HistogramProducer
    private let framePump: FramePump

    // Latest camera texture + uniforms, guarded by `stateLock`.
    private let stateLock = NSLock()
    private var currentTexture: MTLTexture?
    // The CVMetalTexture OWNS the IOSurface backing `currentTexture`. It must be
    // retained for as long as the MTLTexture is used, or the backing is freed
    // under the GPU and the command buffer faults. Kept paired with currentTexture.
    private var currentCVTexture: CVMetalTexture?
    private var uniforms = PreviewUniforms()
    private var drawableSize = SIMD2<Float>(0, 0)
    /// When false, the histogram compute pass + readback are skipped entirely so
    /// the GPU does no histogram work while the overlay is hidden.
    private var histogramEnabled = false
    /// Preview framing ratio (long:short, >= 1). Bound to the fragment shader on
    /// buffer index 1 — kept off `PreviewUniforms` so its frozen ABI is untouched.
    private var targetAspectRatio: Float = 4.0 / 3.0

    init(histogramProducer: HistogramProducer, framePump: FramePump) {
        self.histogramProducer = histogramProducer
        self.framePump = framePump

        // Resolve the Metal device + queue once. On the rare configuration with
        // no Metal device (some Simulators) the renderer stays inert: pipelines
        // are nil and `render`/`enqueue` short-circuit on their guards.
        let resolvedDevice = MTLCreateSystemDefaultDevice()
        self.device = resolvedDevice
        self.commandQueue = resolvedDevice?.makeCommandQueue()

        if let device = resolvedDevice {
            var cache: CVMetalTextureCache?
            CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
            self.textureCache = cache

            self.histogramBuffer = device.makeBuffer(
                length: MetalRenderer.totalBins * MemoryLayout<UInt32>.stride,
                options: .storageModeShared
            )

            let library = try? device.makeDefaultLibrary(bundle: .main)
            self.renderPipeline = MetalRenderer.makeRenderPipeline(device: device, library: library)
            self.histogramPipeline = MetalRenderer.makeHistogramPipeline(
                device: device, library: library)
        } else {
            self.renderPipeline = nil
            self.histogramPipeline = nil
            self.histogramBuffer = nil
        }

        super.init()

        // Register the (off-main) upload path so the integration node can pump
        // frames through `framePump` without reaching the coordinator.
        framePump.setUploader { [weak self] pixelBuffer in
            self?.enqueue(pixelBuffer)
        }
    }

    // MARK: Pipeline construction (once)

    private static func makeRenderPipeline(
        device: MTLDevice,
        library: MTLLibrary?
    ) -> MTLRenderPipelineState? {
        guard let library,
            let vertexFn = library.makeFunction(name: "preview_vertex"),
            let fragmentFn = library.makeFunction(name: "preview_fragment")
        else { return nil }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func makeHistogramPipeline(
        device: MTLDevice,
        library: MTLLibrary?
    ) -> MTLComputePipelineState? {
        guard let library, let fn = library.makeFunction(name: "histogram_accumulate") else {
            return nil
        }
        return try? device.makeComputePipelineState(function: fn)
    }

    // MARK: Public API (main actor)

    /// Snapshot the integration node's derived `PreviewUniforms` for the next
    /// frame. Everything except `viewSize` (renderer-owned, per-drawable) is taken
    /// from the model snapshot; the FROZEN struct is copied wholesale, not mutated.
    func updateUniforms(_ snapshot: PreviewUniforms, histogramEnabled: Bool, aspectRatio: Float) {
        stateLock.lock()
        let viewSize = uniforms.viewSize
        uniforms = snapshot
        uniforms.viewSize = viewSize
        self.histogramEnabled = histogramEnabled
        self.targetAspectRatio = aspectRatio
        stateLock.unlock()
    }

    /// Upload a camera frame to an `MTLTexture` (off main, via the texture cache).
    /// Buffer is valid only for the call duration; the cache retains the IOSurface.
    func enqueue(_ pixelBuffer: CVPixelBuffer) {
        renderQueue.async { [weak self] in
            self?.uploadFrame(pixelBuffer)
        }
    }

    // MARK: Frame upload

    private func uploadFrame(_ pixelBuffer: CVPixelBuffer) {
        guard let textureCache else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )
        guard status == kCVReturnSuccess,
            let cvTexture,
            let texture = CVMetalTextureGetTexture(cvTexture)
        else { return }

        stateLock.lock()
        // Retain the CVMetalTexture alongside the MTLTexture — releasing it (or
        // flushing the cache) while the GPU still reads the texture frees the
        // backing IOSurface and faults the command buffer.
        currentCVTexture = cvTexture
        currentTexture = texture
        stateLock.unlock()
    }

    // MARK: MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        stateLock.lock()
        drawableSize = SIMD2<Float>(Float(size.width), Float(size.height))
        uniforms.viewSize = drawableSize
        stateLock.unlock()
    }

    func draw(in view: MTKView) {
        // MTKView calls this on the main thread, and `currentDrawable` /
        // `currentRenderPassDescriptor` are ONLY valid here on the main thread.
        // Reading them from a background queue returns a render pass with no
        // attachments ("No output textures defined for the render pass"), which
        // faults the command buffer and cascades into GPU submission errors.
        // Encode synchronously on main; GPU execution is still async, and frame
        // uploads stay off-main in `enqueue`/`uploadFrame`.
        render(in: view)
    }

    private func render(in view: MTKView) {
        stateLock.lock()
        let texture = currentTexture
        // Pair the backing with the texture and hold it for this command buffer.
        let cvTexture = currentCVTexture
        let doHistogram = histogramEnabled
        let targetRatio = targetAspectRatio
        var frameUniforms = uniforms
        frameUniforms.viewSize = drawableSize
        stateLock.unlock()

        guard let texture,
            let commandQueue,
            let drawable = view.currentDrawable,
            let passDescriptor = view.currentRenderPassDescriptor,
            let commandBuffer = commandQueue.makeCommandBuffer()
        else { return }

        // Skip the histogram clear+compute entirely when the overlay is hidden.
        if doHistogram {
            encodeHistogram(texture: texture, commandBuffer: commandBuffer)
        }
        encodePreview(
            texture: texture,
            uniforms: &frameUniforms,
            targetRatio: targetRatio,
            passDescriptor: passDescriptor,
            commandBuffer: commandBuffer
        )

        commandBuffer.present(drawable)
        // Capture `cvTexture` so the camera frame's IOSurface stays alive until the
        // GPU finishes this command buffer (prevents a use-after-free fault). Read
        // the histogram back only if we computed it this frame.
        commandBuffer.addCompletedHandler { [weak self, cvTexture] _ in
            _ = cvTexture
            if doHistogram { self?.readbackHistogram() }
        }
        commandBuffer.commit()
    }

    private func encodePreview(
        texture: MTLTexture,
        uniforms: inout PreviewUniforms,
        targetRatio: Float,
        passDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer
    ) {
        guard let pipeline = renderPipeline,
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)
        else { return }
        var ratio = targetRatio
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<PreviewUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<PreviewUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&ratio, length: MemoryLayout<Float>.stride, index: 1)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private func encodeHistogram(texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        guard let histogramPipeline,
            let histogramBuffer,
            let blit = commandBuffer.makeBlitCommandEncoder()
        else { return }

        // Clear the reused bin buffer before accumulating this frame.
        blit.fill(
            buffer: histogramBuffer,
            range: 0..<(MetalRenderer.totalBins * MemoryLayout<UInt32>.stride),
            value: 0
        )
        blit.endEncoding()

        guard let compute = commandBuffer.makeComputeCommandEncoder() else { return }
        compute.setComputePipelineState(histogramPipeline)
        compute.setTexture(texture, index: 0)
        compute.setBuffer(histogramBuffer, offset: 0, index: 0)

        let w = histogramPipeline.threadExecutionWidth
        let h = max(1, histogramPipeline.maxTotalThreadsPerThreadgroup / w)
        let threadsPerGroup = MTLSize(width: w, height: h, depth: 1)
        // Sample a BOUNDED grid, not one thread per pixel. With the .photo preset
        // the camera texture is ~12 MP; dispatching it 1:1 launches millions of
        // threads all doing atomic adds into 1024 bins — atomic contention that
        // saturates the GPU, trips the watchdog, and locks up the device. A capped
        // grid is statistically more than enough for a preview histogram and keeps
        // cost independent of capture resolution. The kernel maps gid → texel via
        // [[threads_per_grid]].
        let maxSamples = 384
        let grid = MTLSize(
            width: min(texture.width, maxSamples),
            height: min(texture.height, maxSamples),
            depth: 1
        )
        compute.dispatchThreads(grid, threadsPerThreadgroup: threadsPerGroup)
        compute.endEncoding()
    }

    // MARK: Histogram readback (off main; producer hops to main)

    private func readbackHistogram() {
        guard let histogramBuffer else { return }
        let pointer = histogramBuffer.contents().bindMemory(
            to: UInt32.self,
            capacity: MetalRenderer.totalBins
        )
        let counts = UnsafeBufferPointer(start: pointer, count: MetalRenderer.totalBins)

        let bins = MetalRenderer.binCount
        // Cast GPU UInt32 counts to [Int] at the call site (frozen signature).
        let red = (0..<bins).map { Int(counts[$0]) }
        let green = (0..<bins).map { Int(counts[bins + $0]) }
        let blue = (0..<bins).map { Int(counts[2 * bins + $0]) }
        let luma = (0..<bins).map { Int(counts[3 * bins + $0]) }

        histogramProducer.ingest(red: red, green: green, blue: blue, luma: luma)
    }
}

#if DEBUG
    // Renders black in the canvas (no camera frames); included so every view has a
    // preview. The real preview only appears on a device.
    #Preview {
        CameraMetalView(model: .preview())
            .ignoresSafeArea()
    }
#endif
