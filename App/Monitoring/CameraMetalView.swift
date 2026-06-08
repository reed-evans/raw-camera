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

// MARK: - Histogram producer (pure hand-off; main-actor delivery)

/// A thin producer the integration node subscribes to. The Metal renderer reads
/// back raw GPU bin counts on its private queue, normalizes them via
/// `CameraCore.Histogram`, and delivers the result on the **main** actor so the
/// integration node can assign it to `CameraModel.histogram` without re-hopping.
public final class HistogramProducer: @unchecked Sendable {
    /// Set by the integration node. Always invoked on the main thread.
    public var onHistogram: ((HistogramData) -> Void)?

    public init() {}

    /// Called by the renderer on its private queue with raw integer counts.
    /// Normalizes off-main, then delivers on main.
    func ingest(red: [Int], green: [Int], blue: [Int], luma: [Int]) {
        let data = Histogram.normalize(red: red, green: green, blue: blue, luma: luma)
        DispatchQueue.main.async { [weak self] in
            self?.onHistogram?(data)
        }
    }
}

/// Frame entry point the integration node pumps from `CameraCapturing.onVideoFrame`.
/// The renderer registers its uploader here when the view is created, so the
/// integration node only needs a reference to this sink — never to the
/// coordinator (which SwiftUI does not surface). `submit` is safe to call from
/// the capture stack's background queue.
public final class FramePump: @unchecked Sendable {
    private let lock = NSLock()
    private var uploader: ((CVPixelBuffer) -> Void)?

    public init() {}

    /// Called by the renderer to register its (off-main) upload path.
    func setUploader(_ uploader: @escaping (CVPixelBuffer) -> Void) {
        lock.lock()
        self.uploader = uploader
        lock.unlock()
    }

    /// Integration pumps each camera frame here. Valid only for the call's
    /// duration (the pool recycles the buffer); the uploader copies via the
    /// texture cache immediately.
    public func submit(_ pixelBuffer: CVPixelBuffer) {
        lock.lock()
        let uploader = self.uploader
        lock.unlock()
        uploader?(pixelBuffer)
    }
}

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
        view.preferredFramesPerSecond = 60
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        // Snapshot the (main-actor) monitoring controls into the renderer's
        // uniforms. The renderer reads these on its private queue under a lock.
        context.coordinator.updateUniforms(
            zebraEnabled: model.zebraEnabled,
            zebraThreshold: model.zebraThreshold,
            peakingEnabled: model.focusPeakingEnabled,
            peakingThreshold: model.focusPeakingThreshold
        )
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
    private var uniforms = PreviewUniforms()
    private var drawableSize = SIMD2<Float>(0, 0)

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

    /// Snapshot monitoring controls into the uniforms used by the next frame.
    func updateUniforms(
        zebraEnabled: Bool,
        zebraThreshold: Float,
        peakingEnabled: Bool,
        peakingThreshold: Float
    ) {
        stateLock.lock()
        uniforms.zebraEnabled = zebraEnabled ? 1 : 0
        uniforms.zebraThreshold = zebraThreshold
        uniforms.peakingEnabled = peakingEnabled ? 1 : 0
        uniforms.peakingThreshold = peakingThreshold
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
        currentTexture = texture
        stateLock.unlock()

        // Recycle cache resources for stale frames.
        CVMetalTextureCacheFlush(textureCache, 0)
    }

    // MARK: MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        stateLock.lock()
        drawableSize = SIMD2<Float>(Float(size.width), Float(size.height))
        uniforms.viewSize = drawableSize
        stateLock.unlock()
    }

    func draw(in view: MTKView) {
        renderQueue.async { [weak self] in
            self?.render(in: view)
        }
    }

    private func render(in view: MTKView) {
        stateLock.lock()
        let texture = currentTexture
        var frameUniforms = uniforms
        frameUniforms.viewSize = drawableSize
        stateLock.unlock()

        guard let texture,
            let renderPipeline,
            let commandQueue,
            let drawable = view.currentDrawable,
            let passDescriptor = view.currentRenderPassDescriptor,
            let commandBuffer = commandQueue.makeCommandBuffer()
        else { return }

        encodeHistogram(texture: texture, commandBuffer: commandBuffer)
        encodePreview(
            texture: texture,
            uniforms: &frameUniforms,
            pipeline: renderPipeline,
            passDescriptor: passDescriptor,
            commandBuffer: commandBuffer
        )

        commandBuffer.present(drawable)
        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.readbackHistogram()
        }
        commandBuffer.commit()
    }

    private func encodePreview(
        texture: MTLTexture,
        uniforms: inout PreviewUniforms,
        pipeline: MTLRenderPipelineState,
        passDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer
    ) {
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else {
            return
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<PreviewUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<PreviewUniforms>.stride, index: 0)
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
        let grid = MTLSize(width: texture.width, height: texture.height, depth: 1)
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
