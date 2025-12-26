import UIKit
import Metal
import MetalKit
import MetalPerformanceShaders
import simd

private let semaphoreValue: Int = 2

public enum LegacyGlassCaptureMode: Equatable {
    public enum Speed {
        case fast
        case slow
    }
    
    case dynamicBackground(LegacyGlassCaptureMode.Speed)
    case staticBackground
}

private struct LegacyGlassUniforms {
    var canvasSize: simd_float2
    var lensCenterCanvas: simd_float2
    var lensRadiusCanvas: simd_float2
    var cornerRadius: Float
    var refractionStrength: Float
    var brightnessAdaptationMin: Float
    var brightnessAdaptationMax: Float
    var brightnessAdaptationStrength: Float
    var averageBackgroundLuma: Float
    var textureOriginHost: simd_float2
    var textureSizeHost: simd_float2
    var lensOriginHost: simd_float2
    var lensSizeHost: simd_float2
    var refractionEdgeWidth: Float
    var refractionCenterStrength: Float
    var refractionEdgeStrength: Float
    var interactionScale: Float
    var refractionYScale: Float
    var chromaticAberrationStrength: Float
    var rimHighlightWidth: Float
    var rimHighlightStrength: Float
    var coreRadius: Float
    var glowProgress: Float
    var glowCenter: simd_float2
    var glowRadius: Float
    var glowStrength: Float
    var outerShadowWidth: Float
    var outerShadowOpacity: Float
    var tintColor: simd_float4
    var fillColor: simd_float4
    var fillProgress: Float
}

private struct AdditionalTextureUniforms {
    var canvasSize: simd_float2
    var additionalTextureOriginCanvas: simd_float2
    var additionalTextureSizeCanvas: simd_float2
    var backgroundTextureSize: simd_float2
    var cornerRadius: Float
    var backgroundColor: simd_float4
}

protocol LegacyGlassRendererDelegate: AnyObject {
    var onCaptureBegan: (() -> Void)? { get set }
    var onCaptureEnded: (() -> Void)? { get set }
    
    var isHidden: Bool { get set }
    var lensSize: CGSize { get }

    func updateContentViewTransform(scale: CGPoint, translation: CGPoint)
}

final class LegacyGlassRenderer: MTKView {

    static let minRenderSize: CGSize = CGSize(width: 10, height: 10)

    weak var glassDelegate: LegacyGlassRendererDelegate?
    
    var useAdaptiveBrightness: Bool = false
    var useLayerBaseRender: Bool = false
    var useAdditionalFrontImage: Bool = false {
        didSet {
            self.isTextureUpdateNeeded = true
        }
    }
    var hasAdditionalFrontImage: Bool {
        return self.additionalFrontTexture != nil
    }
    
    let allowsGroupSnapshotting: Bool
    
    override var tintColor: UIColor? {
        didSet {
            self.tintColorVector = self.colorVector(from: self.tintColor)
        }
    }
    private var tintColorVector: simd_float4 = .zero
    
    var fillColor: UIColor? {
        didSet {
            self.fillColorVector = self.colorVector(from: self.fillColor)
        }
    }
    private var fillColorVector: simd_float4 = .zero
    
    var additionalFrontImageBackgroundColor: UIColor? {
        didSet {
            guard self.additionalFrontImageBackgroundColor != oldValue else { return }
            self.additionalFrontImageBackgroundColorVector = self.colorVector(from: self.additionalFrontImageBackgroundColor)
            self.isCombinedTextureValid = false
        }
    }
    private var additionalFrontImageBackgroundColorVector: simd_float4 = .zero

    private var snapshotRequest: LegacyGlassSnapshotRequest?
    private var snapshotRequestId: UUID?
    
    private weak var captureHostView: UIView?
    var isSafeBoundsCaptureEnabled: Bool = true
    private var capturedFrameInHost: (proposed: CGRect, captured: CGRect) = (.zero, .zero)
    private var captureDebounceWorkItem: DispatchWorkItem?
    private(set) var captureMode: LegacyGlassCaptureMode = .staticBackground {
        didSet {
            self.didUpdateCaptureMode(self.captureMode)
        }
    }

    private var isBlurEnabled: Bool {
        self.context.style.isBlurEnabled
    }

    private let inflightSemaphore: DispatchSemaphore
    
    private let textureLoader: MTKTextureLoader
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?
    private var vertexBuffer: MTLBuffer?
    private var samplerState: MTLSamplerState?
    private var uniformsBuffer: MTLBuffer?
    private var additionalTextureUniformsBuffer: MTLBuffer?
    
    private var _additionalTexturePipelineState: MTLRenderPipelineState?
    private var additionalTexturePipelineState: MTLRenderPipelineState? {
        if let cached = self._additionalTexturePipelineState {
            return cached
        }
        guard let device = self.device else {
            return nil
        }
        let pipelineState = self.makeAdditionalTexturePipelineState(device: device)
        self._additionalTexturePipelineState = pipelineState
        return pipelineState
    }
    
    var isTextureUpdateNeeded: Bool = false
    private var texture: MTLTexture?
    private var textureBlurred: MTLTexture?
    private var additionalFrontTexture: MTLTexture?
    private var additionalFrontOrigin: CGPoint = .zero
    private var currentAdditionalFrontImage: CGImage?
    private var lastTextureUpdateTimestamp: CFTimeInterval?
    private var textureUpdateFPS: Double = 0.0
    
    var blurFilterSigma: Float = 1.0 {
        didSet {
            guard self.context.style.isBlurEnabled, let device = self.device else { return }
            self.blurFilter = MPSImageGaussianBlur(device: device, sigma: self.blurFilterSigma)
            self.isBlurredTextureValid = false
        }
    }
    private var isBlurredTextureValid: Bool = false
    private var blurFilter: MPSImageGaussianBlur?
    
    private var isCombinedTextureValid: Bool = false
    private var combinedTexture: MTLTexture?
    private var lastCombinedTextureOrigin: CGPoint = .zero
    
    var brightnessAdaptationMin: Float = 0.0
    var brightnessAdaptationMax: Float = 0.1
    private var averageBackgroundLuma: Float = 0.5
    
    private var lensSize: CGSize {
        self.glassDelegate?.lensSize ?? .zero
    }
    
    private let context: LegacyGlassContext
    
    private var backgroundObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?
    private var activeObserver: NSObjectProtocol?

    init(context: LegacyGlassContext, allowsGroupSnapshotting: Bool) {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            let commandQueue = device.makeCommandQueue()
        else {
            fatalError("Metal device or command queue unavailable")
        }
        
        self.context = context
        self.allowsGroupSnapshotting = allowsGroupSnapshotting

        self.inflightSemaphore = DispatchSemaphore(value: semaphoreValue)
        
        self.commandQueue = commandQueue
        self.textureLoader = MTKTextureLoader(device: device)
        
        super.init(frame: .zero, device: device)

        self.delegate = self
        self.isOpaque = false
        self.enableSetNeedsDisplay = false
        self.isPaused = false
        self.framebufferOnly = false
        self.autoResizeDrawable = false
        self.colorPixelFormat = .bgra8Unorm
        self.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0)
        self.preferredFramesPerSecond = self.currentUpdateFrequency().renderFrameRate
        self.pipelineState = self.makePipelineState(device: device)
        self.vertexBuffer = self.makeQuadVertexBuffer(device: device)
        self.samplerState = self.makeSamplerState(device: device)
        self.uniformsBuffer = self.makeUniformsBuffer(device: device)
        self.additionalTextureUniformsBuffer = self.makeAdditionalTextureUniformsBuffer(device: device)
        
        if self.isBlurEnabled {
            self.blurFilter = MPSImageGaussianBlur(device: device, sigma: self.blurFilterSigma)
            self.isBlurredTextureValid = false
        }

        self.backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let strongSelf = self else { return }
            strongSelf.setIsPaused(true)
        }
        
        self.foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let strongSelf = self else { return }
            strongSelf.setIsPaused(false)
        }
        
        self.activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let strongSelf = self else { return }
            strongSelf.setIsPaused(false)
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        
        if self.superview != nil && self.allowsGroupSnapshotting {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                LegacyGlassSnapshotter.shared.forceVisibilityCheck()
            }
        }
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()

        if self.window != nil && self.allowsGroupSnapshotting {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                LegacyGlassSnapshotter.shared.forceVisibilityCheck()
            }
        }
        
        if self.window != nil {
            self.setIsPaused(false)
        }
    }
    
    deinit {
        self.isPaused = true
        for _ in 0..<semaphoreValue {
            _ = self.inflightSemaphore.wait(timeout: .now() + 0.1)
            self.inflightSemaphore.signal()
        }
        
        if let backgroundObserver = self.backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
        if let foregroundObserver = self.foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
        if let activeObserver = self.activeObserver {
            NotificationCenter.default.removeObserver(activeObserver)
        }
        
        self.snapshotRequest?.invalidate()
        self.snapshotRequest = nil
        self.snapshotRequestId = nil
        self.captureDebounceWorkItem?.cancel()
    }
    
    private func makePipelineState(device: MTLDevice) -> MTLRenderPipelineState? {
        guard
            let library = metalLibrary(device: device),
            let vertexFunction = library.makeFunction(name: "legacyGlassVertex"),
            let fragmentFunction = library.makeFunction(name: "legacyGlassFragment")
        else {
            assertionFailure("Failed to make pipeline state")
            return nil
        }
        
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<simd_float2>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<simd_float2>.stride * 2
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.vertexDescriptor = vertexDescriptor
        descriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    private func makeAdditionalTexturePipelineState(device: MTLDevice) -> MTLRenderPipelineState? {
        guard
            let library = metalLibrary(device: device),
            let vertexFunction = library.makeFunction(name: "legacyGlassVertex"),
            let fragmentFunction = library.makeFunction(name: "additionalTextureFragment")
        else {
            assertionFailure("Failed to make additional texture pipeline state")
            return nil
        }
        
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<simd_float2>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<simd_float2>.stride * 2
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.vertexDescriptor = vertexDescriptor
        descriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    private func makeQuadVertexBuffer(device: MTLDevice) -> MTLBuffer? {
        struct Vertex {
            var position: simd_float2
            var texCoord: simd_float2
        }
        
        let vertices: [Vertex] = [
            Vertex(position: [-1, -1], texCoord: [0, 1]),
            Vertex(position: [1, -1], texCoord: [1, 1]),
            Vertex(position: [-1, 1], texCoord: [0, 0]),
            Vertex(position: [1, 1], texCoord: [1, 0])
        ]
        
        let length = vertices.count * MemoryLayout<Vertex>.stride
        return device.makeBuffer(bytes: vertices, length: length, options: .storageModeShared)
    }
    
    private func makeSamplerState(device: MTLDevice) -> MTLSamplerState? {
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.mipFilter = .notMipmapped
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge
        return device.makeSamplerState(descriptor: descriptor)
    }
    
    private func makeUniformsBuffer(device: MTLDevice) -> MTLBuffer? {
        return device.makeBuffer(
            length: MemoryLayout<LegacyGlassUniforms>.stride,
            options: .storageModeShared
        )
    }
    
    private func makeAdditionalTextureUniformsBuffer(device: MTLDevice) -> MTLBuffer? {
        return device.makeBuffer(
            length: MemoryLayout<AdditionalTextureUniforms>.stride,
            options: .storageModeShared
        )
    }
    
    func setIsPaused(_ isPaused: Bool) {
        guard self.isPaused != isPaused else { return }
        self.isPaused = isPaused
    }
    
    func requestUpdate() {
        self.isTextureUpdateNeeded = true
    }

    func setCaptureHostView(_ captureHostView: UIView) {
        guard self.captureHostView !== captureHostView else { return }

        self.snapshotRequest?.invalidate()
        self.snapshotRequest = nil
        self.snapshotRequestId = nil
        
        self.captureHostView = captureHostView
        
        self.snapshotRequest = LegacyGlassSnapshotter.shared.requestSnapshot(
            hostView: captureHostView,
            renderer: self,
            allowsGroupSnapshotting: self.allowsGroupSnapshotting
        )
        self.snapshotRequestId = self.snapshotRequest?.requestId
        
        self.isTextureUpdateNeeded = true
    }

    func setCaptureMode(_ captureMode: LegacyGlassCaptureMode) {
        guard captureMode != self.captureMode else { return }
        
        switch captureMode {
        case .dynamicBackground:
            self.captureMode = captureMode
        case .staticBackground:
            self.debounceCaptureMode(captureMode, duration: 1.0)
        }
    }
    
    func setAdditionalFrontImage(_ cgImage: CGImage?, atPaddedOrigin origin: CGPoint) {
        let needsTextureUpdate: Bool
        if let cgImage = cgImage {
            if self.currentAdditionalFrontImage !== cgImage {
                needsTextureUpdate = true
                self.currentAdditionalFrontImage = cgImage
            } else {
                needsTextureUpdate = false
            }
        } else {
            needsTextureUpdate = self.additionalFrontTexture != nil
            self.currentAdditionalFrontImage = nil
        }
        
        let originChanged = self.additionalFrontOrigin != origin
        self.additionalFrontOrigin = origin
        
        if needsTextureUpdate {
            if let cgImage = cgImage {
                do {
                    let texture = try self.makeTexture(from: cgImage)
                    self.additionalFrontTexture = texture
                } catch {
                    print("LegacyGlassRenderer: Failed to create additional front texture from cgImage: \(error)")
                    self.additionalFrontTexture = nil
                }
            } else {
                self.additionalFrontTexture = nil
            }
        }
        
        if needsTextureUpdate || originChanged {
            self.updateCombinedTextureIfNeeded()
            if self.isBlurEnabled {
                self.isBlurredTextureValid = false
            }
        }
    }

    func updateAdditionalFrontImageOrigin(at point: CGPoint) {
        self.additionalFrontOrigin = point
    }

    func ensureFastCaptureWithDebounce(to debounceCaptureMode: LegacyGlassCaptureMode, duration: TimeInterval? = nil) {
        self.setCaptureMode(.dynamicBackground(.fast))
        let debounceDuration = duration ?? self.context.qualityProfile.captureAutoUpdateSlowDebounce
        self.debounceCaptureMode(debounceCaptureMode, duration: debounceDuration)
    }
    
    func currentUpdateFrequency() -> LegacyGlassUpdateFrequency {
        switch self.captureMode {
        case .dynamicBackground(let speed):
            switch speed {
            case .fast:
                return self.context.qualityProfile.dynamicFastFrequency
            case .slow:
                return self.context.qualityProfile.dynamicSlowFrequency
            }
        case .staticBackground:
            return self.context.qualityProfile.staticFrequency
        }
    }
    
    func currentCaptureScale() -> CGFloat {
        return self.isBlurEnabled ? self.context.qualityProfile.captureScaleBlurred : self.context.qualityProfile.captureScale
    }

    private func updateTextureIfNeeded() {
        guard let hostView = self.captureHostView else {
            return
        }

        if case .fps(let captureFrameRate, _) = self.currentUpdateFrequency() {
            let now = CACurrentMediaTime()
            let minInterval: CFTimeInterval = 1.0 / captureFrameRate
            if let last = self.lastTextureUpdateTimestamp, (now - last) < minInterval {
                return
            }
        }

        let proposedFrame = self.convert(self.bounds, to: hostView)
        let capturedFrame: CGRect
        if self.isSafeBoundsCaptureEnabled {
            capturedFrame = proposedFrame.intersection(hostView.bounds)
        } else {
            capturedFrame = proposedFrame
        }

        guard capturedFrame.width > 0, capturedFrame.height > 0 else {
            return
        }

        self.capturedFrameInHost = (proposed: proposedFrame, captured: capturedFrame)
        
        if self.allowsGroupSnapshotting, let requestId = self.snapshotRequestId {
            if let cgImage = LegacyGlassSnapshotter.shared.getCroppedSnapshot(requestId: requestId) {
                self.createTexture(from: cgImage)
            }
        } else {
            if let cgImage = LegacyGlassSnapshotter.shared.captureSnapshotDirectly(
                rect: capturedFrame,
                hostView: hostView,
                scale: self.currentCaptureScale(),
                viewToExclude: self.superview,
                useLayerBasedRender: self.useLayerBaseRender
            ) {
                self.createTexture(from: cgImage)
            }
        }
    }
    
    private func updateCombinedTextureIfNeeded() {
        guard let sourceTexture = self.texture else {
            self.combinedTexture = nil
            self.isCombinedTextureValid = false
            return
        }
        
        guard self.additionalFrontTexture != nil else {
            self.combinedTexture = nil
            self.isCombinedTextureValid = false
            return
        }
        
        _ = self.ensureCombinedTexture(for: sourceTexture)
        self.isCombinedTextureValid = false
    }
    
    private func createTexture(from cgImage: CGImage) {
        do {
            let texture = try self.makeTexture(from: cgImage)
            self.texture = texture
            self.textureBlurred = self.isBlurEnabled ? self.ensureBlurredTexture(fromTexture: texture) : nil
            if self.useAdaptiveBrightness {
                self.averageBackgroundLuma = self.computeAverageLuma(from: cgImage)
            }
            self.isCombinedTextureValid = false
            self.updateCombinedTextureIfNeeded()
            self.isTextureUpdateNeeded = false
            self.isBlurredTextureValid = false
        } catch {
            print("LegacyGlassRenderer: Failed to create texture from cgImage: \(error)")
            self.texture = nil
            self.textureBlurred = nil
            self.combinedTexture = nil
            self.isTextureUpdateNeeded = false
            self.isBlurredTextureValid = false
        }
    }
    
    private func ensureBlurredTexture(fromTexture texture: MTLTexture) -> MTLTexture? {
        if self.isTextureMatching(texture, with: self.textureBlurred) {
            return self.textureBlurred
        }
        
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: texture.pixelFormat,
            width: texture.width,
            height: texture.height,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.shaderRead, .shaderWrite]
        
        guard let blurredTexture = texture.device.makeTexture(descriptor: descriptor) else {
            print("LegacyGlassRenderer: Failed to create blurred texture, descriptor: width=\(descriptor.width), height=\(descriptor.height), pixelFormat=\(descriptor.pixelFormat.rawValue)")
            return nil
        }
        return blurredTexture
    }
    
    private func ensureCombinedTexture(for sourceTexture: MTLTexture) -> MTLTexture? {
        guard sourceTexture.width > 0, sourceTexture.height > 0 else {
            return nil
        }
        
        if self.isTextureMatching(sourceTexture, with: self.combinedTexture) {
            return self.combinedTexture
        }
        
        self.combinedTexture = nil
        self.isCombinedTextureValid = false
        
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: self.colorPixelFormat,
            width: sourceTexture.width,
            height: sourceTexture.height,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        
        guard let combinedTexture = sourceTexture.device.makeTexture(descriptor: descriptor) else {
            print("LegacyGlassRenderer: Failed to create combined texture, descriptor: width=\(descriptor.width), height=\(descriptor.height), pixelFormat=\(descriptor.pixelFormat.rawValue)")
            return nil
        }
        
        self.combinedTexture = combinedTexture
        return combinedTexture
    }
    
    private func makeTexture(from cgImage: CGImage) throws -> MTLTexture {
        return try self.textureLoader.newTexture(
            cgImage: cgImage,
            options: [
                MTKTextureLoader.Option.SRGB: false,
                MTKTextureLoader.Option.textureUsage: MTLTextureUsage.shaderRead.rawValue,
                MTKTextureLoader.Option.generateMipmaps: false
            ]
        )
    }
    
    private func updateUniformsBuffer(buffer: MTLBuffer) {
        let canvasWidth = self.bounds.width
        let canvasHeight = self.bounds.height
        
        guard canvasWidth > 0, canvasHeight > 0 else {
            return
        }
        
        guard let hostView = self.captureHostView else {
            return
        }
        
        let requiredSize = MemoryLayout<LegacyGlassUniforms>.stride
        if buffer.length < requiredSize {
            assertionFailure("Uniforms buffer too small: \(buffer.length) < \(requiredSize)")
            return
        }

        let increasingJelly = 1.0 + self.context.interactionJelly
        let decreasingJelly = max(0.75, 1.0 - self.context.interactionJelly)
        let jellyX = self.context.interactionJellyDirection == .horizontal ? increasingJelly : decreasingJelly
        let jellyY = self.context.interactionJellyDirection == .horizontal ? decreasingJelly : increasingJelly

        let baseStretchX = max(0.8, 1.0 + abs(CGFloat(self.context.interactionStretch.x)))
        let baseStretchY = max(0.8, 1.0 + abs(CGFloat(self.context.interactionStretch.y)))
        let maxStretch = max(baseStretchX, baseStretchY)
        let minStretch = min(baseStretchX, baseStretchY)
        let stretchBalance = max(0.0, min(1.0, minStretch / maxStretch))
        let stretchBalanceFactor: CGFloat = 0.3
        let scaleAdjust = 1.0 - (1.0 - stretchBalance) * stretchBalanceFactor
        let stretchX = baseStretchX * scaleAdjust
        let stretchY = baseStretchY * scaleAdjust
        
        let lensSize = self.lensSize

        var lensSizeTransformed = CGSize(
            width: lensSize.width * CGFloat(self.context.interactionScale) * CGFloat(jellyX) * stretchX,
            height: lensSize.height * CGFloat(self.context.interactionScale) * CGFloat(jellyY) * stretchY
        )
        
        let aaMargin: CGFloat = 0
        lensSizeTransformed.width = min(lensSizeTransformed.width, canvasWidth - aaMargin * 2.0)
        lensSizeTransformed.height = min(lensSizeTransformed.height, canvasHeight - aaMargin * 2.0)

        let lensDelta = CGSize(
            width: (lensSizeTransformed.width - lensSize.width),
            height: (lensSizeTransformed.height - lensSize.height)
        )

        let stretchMax = max(self.context.interactionStretchMax, 0.0001)
        let softClamp: (CGFloat) -> CGFloat = { value in
            let x = max(-1.0, min(1.0, value / stretchMax))
            return tanh(x * 1.0)
        }
        let easedPivotX = 0.5 * softClamp(self.context.interactionStretch.x)
        let easedPivotY = 0.5 * softClamp(self.context.interactionStretch.y)
        let deltaFactorX: CGFloat = 0.5 - easedPivotX
        let deltaFactorY: CGFloat = 0.5 - easedPivotY
        
        let cornerRadiusTransformed = self.context.cornerRadius * self.context.interactionScale * stretchY
        
        let lensCenterCanvas = simd_float2(
            Float((self.context.horizontalPadding + lensSizeTransformed.width * 0.5 - lensDelta.width * deltaFactorX) / canvasWidth),
            Float((self.context.verticalPadding + lensSizeTransformed.height * 0.5 - lensDelta.height * deltaFactorY) / canvasHeight)
        )
        
        let lensRadiusCanvas = simd_float2(
            Float((lensSizeTransformed.width * 0.5) / canvasWidth),
            Float((lensSizeTransformed.height * 0.5) / canvasHeight)
        )
        
        let hostBounds = hostView.bounds
        guard hostBounds.width > 0, hostBounds.height > 0 else {
            return
        }
        
        let textureOriginNormalized = simd_float2(
            Float(self.capturedFrameInHost.captured.origin.x / hostBounds.width),
            Float(self.capturedFrameInHost.captured.origin.y / hostBounds.height)
        )
        
        let textureSizeNormalized = simd_float2(
            Float(self.capturedFrameInHost.captured.size.width / hostBounds.width),
            Float(self.capturedFrameInHost.captured.size.height / hostBounds.height)
        )
        
        let glassFrame = self.convert(self.bounds, to: hostView)
            .insetBy(dx: self.context.horizontalPadding, dy: self.context.verticalPadding)
        
        let lensOriginHost = simd_float2(
            Float((glassFrame.origin.x - lensDelta.width * deltaFactorX) / hostBounds.width),
            Float((glassFrame.origin.y - lensDelta.height * deltaFactorY) / hostBounds.height)
        )
        
        let lensSizeHost = simd_float2(
            Float(lensSizeTransformed.width / hostBounds.width),
            Float(lensSizeTransformed.height / hostBounds.height)
        )
        
        let glowProgress = Float(max(0.0, min(1.0, self.context.interactionGlow)))
        let glowCenter = simd_float2(
            Float(self.context.interactionGlowCenter.x),
            Float(self.context.interactionGlowCenter.y)
        )
        
        let timestamp = CACurrentMediaTime()
        if self.context.lastUpdateTimestamp > 0 {
            let deltaTime = Float(timestamp - self.context.lastUpdateTimestamp)
            if deltaTime > 0 {
                let deltaHost = lensOriginHost - self.context.lastHostOrigin
                let speed = CGFloat(length(deltaHost) / deltaTime)
                let targetJelly = min(speed * self.context.interactionJellyGain, self.context.interactionJellyMax)
                self.context.interactionJellyTarget = targetJelly
            }
        }
        
        self.context.lastUpdateTimestamp = timestamp
        self.context.lastHostOrigin = lensOriginHost
        
        self.glassDelegate?.updateContentViewTransform(
            scale: CGPoint(
                x: lensSizeTransformed.width / lensSize.width,
                y: lensSizeTransformed.height / lensSize.height,
            ),
            translation: CGPoint(x: easedPivotX * lensDelta.width, y: easedPivotY * lensDelta.height)
        )

        let brightnessAdaptationStrength = self.useAdaptiveBrightness ? self.context.style.brightnessAdaptationStrength : 0.0
        let activationProgress = Float(max(0.0, min(1.0, self.context.interactionActivationProgress)))
        let idleWeight = 1.0 - activationProgress
        let outerShadowWidth = self.context.style.idleOuterShadowWidth * idleWeight + self.context.style.activeOuterShadowWidth * activationProgress
        let outerShadowOpacity = self.context.style.idleOuterShadowOpacity * idleWeight + self.context.style.activeOuterShadowOpacity * activationProgress
        
        var uniforms = LegacyGlassUniforms(
            canvasSize: simd_float2(Float(canvasWidth), Float(canvasHeight)),
            lensCenterCanvas: lensCenterCanvas,
            lensRadiusCanvas: lensRadiusCanvas,
            cornerRadius: Float(cornerRadiusTransformed),
            refractionStrength: self.context.style.refractionStrength,
            brightnessAdaptationMin: self.brightnessAdaptationMin,
            brightnessAdaptationMax: self.brightnessAdaptationMax,
            brightnessAdaptationStrength: brightnessAdaptationStrength,
            averageBackgroundLuma: self.averageBackgroundLuma,
            textureOriginHost: textureOriginNormalized,
            textureSizeHost: textureSizeNormalized,
            lensOriginHost: lensOriginHost,
            lensSizeHost: lensSizeHost,
            refractionEdgeWidth: self.context.style.refractionEdgeWidth,
            refractionCenterStrength: self.context.style.refractionCenterStrength,
            refractionEdgeStrength: self.context.style.refractionEdgeStrength,
            interactionScale: Float(self.context.interactionScale),
            refractionYScale: self.context.style.refractionYScale,
            chromaticAberrationStrength: self.context.style.chromaticAberrationStrength,
            rimHighlightWidth: self.context.style.rimHighlightWidth,
            rimHighlightStrength: self.context.style.rimHighlightStrength,
            coreRadius: self.context.style.coreRadius,
            glowProgress: glowProgress,
            glowCenter: glowCenter,
            glowRadius: self.context.style.glowRadius,
            glowStrength: self.context.style.glowStrenght,
            outerShadowWidth: outerShadowWidth,
            outerShadowOpacity: outerShadowOpacity,
            tintColor: self.tintColorVector,
            fillColor: self.fillColorVector,
            fillProgress: idleWeight
        )
        memcpy(buffer.contents(), &uniforms, requiredSize)
    }
    
    private func colorVector(from color: UIColor?) -> simd_float4 {
        guard let uiColor = color else {
            return simd_float4(0,0,0,0)
        }
        
        let resolvedColor = uiColor.resolvedColor(with: self.traitCollection)

        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.linearSRGB),
            let cgColor = resolvedColor.cgColor.converted(to: colorSpace, intent: .defaultIntent, options: nil),
            let components = cgColor.components, !components.isEmpty
        else {
            return simd_float4(0, 0, 0, 0)
        }
        
        let r: CGFloat
        let g: CGFloat
        let b: CGFloat
        if components.count >= 3 {
            r = components[0]
            g = components[1]
            b = components[2]
        } else {
            r = components[0]
            g = components[0]
            b = components[0]
        }
        
        let a = components.count > 3 ? components[3] : cgColor.alpha
        return simd_float4(Float(r), Float(g), Float(b), Float(a))
    }

    private func computeAverageLuma(from cgImage: CGImage) -> Float {
        guard
            let dataProvider = cgImage.dataProvider,
            let data = dataProvider.data,
            let ptr = CFDataGetBytePtr(data)
        else {
            return 0.5
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = cgImage.bytesPerRow
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        guard bytesPerPixel >= 3 else {
            return 0.5
        }

        let info = cgImage.bitmapInfo
        let isLittleEndian = info.contains(.byteOrder32Little)
        let isBGR = isLittleEndian || info.contains(.byteOrder16Little)
        let rIndex = isBGR ? 2 : 0
        let gIndex = 1
        let bIndex = isBGR ? 0 : 2
        let aIndex = bytesPerPixel > 3 ? 3 : -1

        let sampleStep = max(1, min(2, min(width, height) / 16))

        var sum: Float = 0
        var weightSum: Float = 0

        var y = 0
        while y < height {
            var x = 0
            while x < width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let a: Float
                if aIndex >= 0 {
                    a = Float(ptr[offset + aIndex]) / 255.0
                    if a <= 0.0 {
                        x += sampleStep
                        continue
                    }
                } else {
                    a = 1.0
                }

                let r = Float(ptr[offset + rIndex])
                let g = Float(ptr[offset + gIndex])
                let b = Float(ptr[offset + bIndex])

                let luma = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
                sum += luma * a
                weightSum += a
                x += sampleStep
            }
            y += sampleStep
        }

        guard weightSum > 0 else { return 0.5 }
        
        let average = sum / weightSum
        return min(max(average, 0.0), 1.0)
    }
    
    private func debounceCaptureMode(_ captureMode: LegacyGlassCaptureMode, duration: TimeInterval) {
        self.captureDebounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.captureMode = captureMode
        }
        self.captureDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }
    
    private func didUpdateCaptureMode(_ captureMode: LegacyGlassCaptureMode) {
        print(captureMode)
        self.preferredFramesPerSecond = self.currentUpdateFrequency().renderFrameRate
        self.isTextureUpdateNeeded = true
        LegacyGlassSnapshotter.shared.updateMinCaptureFrameRate()
    }
}

// MARK: - MTKViewDelegate

extension LegacyGlassRenderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        if self.useAdditionalFrontImage {
            self.combinedTexture = nil
            self.isCombinedTextureValid = false
            self._additionalTexturePipelineState = nil
        }
    }
    
    func draw(in view: MTKView) {
        guard view.bounds.width > LegacyGlassRenderer.minRenderSize.width, view.bounds.height > LegacyGlassRenderer.minRenderSize.height else {
            return
        }

        guard self.inflightSemaphore.wait(timeout: .now()) == .success else {
            return
        }

        autoreleasepool {
            guard
                let renderPassDescriptor = view.currentRenderPassDescriptor,
                let commandBuffer = self.commandQueue.makeCommandBuffer(),
                let drawable = view.currentDrawable
            else {
                self.inflightSemaphore.signal()
                print("LegacyGlassRenderer: draw - failed to get renderPassDescriptor, commandBuffer, or drawable")
                return
            }

            switch self.captureMode {
            case .dynamicBackground:
                self.updateTextureIfNeeded()
            case .staticBackground:
                if self.texture == nil || self.isTextureUpdateNeeded {
                    self.updateTextureIfNeeded()
                }
            }

            var activeTexture: MTLTexture? = self.texture

            if self.isBlurEnabled, let sourceTexture = self.texture {
                var needsUpdateTexture = true
                if self.captureMode == .staticBackground {
                    let sizeMatches = self.isTextureMatching(sourceTexture, with: self.textureBlurred)
                    needsUpdateTexture = !(self.isBlurredTextureValid && sizeMatches)
                }

                if needsUpdateTexture, let blurFilter = self.blurFilter, let destinationTexture = self.textureBlurred {
                    blurFilter.encode(
                        commandBuffer: commandBuffer,
                        sourceTexture: sourceTexture,
                        destinationTexture: destinationTexture
                    )
                    self.isBlurredTextureValid = true
                }

                if let texture = self.textureBlurred, self.isBlurredTextureValid {
                    activeTexture = texture
                }
            }
            
            if
                self.useAdditionalFrontImage,
                let sourceTexture = activeTexture,
                let additionalTexture = self.additionalFrontTexture
            {
                let needsUpdate = !self.isCombinedTextureValid || self.lastCombinedTextureOrigin != self.additionalFrontOrigin || !self.isTextureMatching(sourceTexture, with: self.combinedTexture)
                
                if needsUpdate, let combinedTexture = self.ensureCombinedTexture(for: sourceTexture) {
                    if self.renderAdditionalTexture(
                        commandBuffer: commandBuffer,
                        sourceTexture: sourceTexture,
                        additionalTexture: additionalTexture,
                        destinationTexture: combinedTexture
                    ) {
                        self.isCombinedTextureValid = true
                        self.lastCombinedTextureOrigin = self.additionalFrontOrigin
                        activeTexture = combinedTexture
                    }
                } else if let combinedTexture = self.combinedTexture, self.isCombinedTextureValid {
                    activeTexture = combinedTexture
                }
            }

            if
                let pipelineState = self.pipelineState,
                let vertexBuffer = self.vertexBuffer,
                let texture = activeTexture,
                let uniformsBuffer = self.uniformsBuffer
            {
                self.updateUniformsBuffer(buffer: uniformsBuffer)
                guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
                    self.inflightSemaphore.signal()
                    print("LegacyGlassRenderer: draw - failed to create renderEncoder")
                    return
                }
                renderEncoder.setRenderPipelineState(pipelineState)
                renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
                renderEncoder.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
                renderEncoder.setFragmentTexture(texture, index: 0)
                renderEncoder.setFragmentSamplerState(self.samplerState, index: 0)
                renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                renderEncoder.endEncoding()
            }
            
            commandBuffer.present(drawable)
            let semaphore = self.inflightSemaphore
            commandBuffer.addCompletedHandler { _ in
                semaphore.signal()
            }
            commandBuffer.commit()
        }
    }
    
    private func renderAdditionalTexture(
        commandBuffer: MTLCommandBuffer,
        sourceTexture: MTLTexture,
        additionalTexture: MTLTexture,
        destinationTexture: MTLTexture
    ) -> Bool {
        guard
            let pipelineState = self.additionalTexturePipelineState,
            let vertexBuffer = self.vertexBuffer,
            let uniformsBuffer = self.additionalTextureUniformsBuffer
        else {
            print("LegacyGlassRenderer: renderAdditionalTexture - missing pipelineState, vertexBuffer, or uniformsBuffer")
            return false
        }
        
        guard
            sourceTexture.width > 0, sourceTexture.height > 0,
            additionalTexture.width > 0, additionalTexture.height > 0,
            destinationTexture.width > 0, destinationTexture.height > 0
        else {
            return false
        }
        
        let canvasSize = self.bounds.size
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return false
        }
        
        let canvasSizeFloat = simd_float2(
            Float(canvasSize.width),
            Float(canvasSize.height)
        )
        
        let backgroundTextureSizeFloat: simd_float2
        if self.isSafeBoundsCaptureEnabled {
            backgroundTextureSizeFloat = simd_float2(
                Float(sourceTexture.width),
                Float(sourceTexture.height)
            )
        } else {
            let proposedFrame = self.capturedFrameInHost.proposed
            let captureScale = Float(self.currentCaptureScale())
            backgroundTextureSizeFloat = simd_float2(
                Float(proposedFrame.width * CGFloat(captureScale)),
                Float(proposedFrame.height * CGFloat(captureScale))
            )
        }
        
        guard backgroundTextureSizeFloat.x > 0, backgroundTextureSizeFloat.y > 0 else {
            return false
        }
        
        let scaleX = canvasSizeFloat.x / backgroundTextureSizeFloat.x
        let scaleY = canvasSizeFloat.y / backgroundTextureSizeFloat.y
        
        let additionalTextureSizeInPixels = simd_float2(
            Float(additionalTexture.width),
            Float(additionalTexture.height)
        )
        
        let additionalTextureSizeCanvas = simd_float2(
            additionalTextureSizeInPixels.x * scaleX,
            additionalTextureSizeInPixels.y * scaleY
        )
        
        let additionalTextureOriginCanvas = simd_float2(
            Float(self.additionalFrontOrigin.x),
            Float(self.additionalFrontOrigin.y)
        )
        
        let cornerRadius = Float(additionalTexture.height) * 0.5
        
        var uniforms = AdditionalTextureUniforms(
            canvasSize: canvasSizeFloat,
            additionalTextureOriginCanvas: additionalTextureOriginCanvas,
            additionalTextureSizeCanvas: additionalTextureSizeCanvas,
            backgroundTextureSize: backgroundTextureSizeFloat,
            cornerRadius: cornerRadius,
            backgroundColor: self.additionalFrontImageBackgroundColorVector
        )
        
        let uniformsSize = MemoryLayout<AdditionalTextureUniforms>.stride
        if uniformsBuffer.length >= uniformsSize {
            memcpy(uniformsBuffer.contents(), &uniforms, uniformsSize)
        }
        
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = destinationTexture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        descriptor.colorAttachments[0].storeAction = .store
        
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            print("LegacyGlassRenderer: renderAdditionalTexture - failed to create renderEncoder")
            return false
        }
        
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
        renderEncoder.setFragmentTexture(sourceTexture, index: 0)
        renderEncoder.setFragmentTexture(additionalTexture, index: 1)
        renderEncoder.setFragmentSamplerState(self.samplerState, index: 0)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()
        
        return true
    }

    
    private func isTextureMatching(_ texture: MTLTexture, with anotherTexture: MTLTexture?) -> Bool {
        guard anotherTexture != nil else { return false }
        return texture.device === anotherTexture?.device
            && texture.width == anotherTexture?.width
            && texture.height == anotherTexture?.height
            && texture.pixelFormat == anotherTexture?.pixelFormat
    }
}

