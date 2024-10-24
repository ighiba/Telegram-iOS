import Foundation
import MetalKit
import CoreMedia

typealias HLSVideoBufferTask = HLSMediaTask<HLSTexture>

public struct HLSTexture {
    enum PresintationTimeState {
        case onTime
        case behindTime
        case aheadOfTime
    }
    
    let y: MTLTexture
    let uv: MTLTexture
    let pts: CMTime
    
    func presentationTimeState(forTime currentPlaybackTime: CMTime) -> PresintationTimeState {
        let timeDifference = CMTimeSubtract(currentPlaybackTime, pts)
        
        if CMTimeCompare(timeDifference, CMTimeMake(value: 1, timescale: 10)) > 0 {
            return .behindTime
        } else if CMTimeCompare(timeDifference, CMTimeMake(value: -1, timescale: 10)) < 0 {
            return .aheadOfTime
        } else {
            return .onTime
        }
    }
}

public final class HLSVideoRenderer: NSObject, HLSRenderer {
    struct Vertex {
        var position: SIMD4<Float>
        var texCoord: SIMD4<Float>
    }
    
    public var requestVideoFrames: ((Int) -> [HLSMediaFrame])?
    public var didRenderTextureWithPts: ((CMTime) -> Void)?
    public var didBufferBecomeReady: (() -> Void)?
    
    public var isBufferReady: Bool = false {
        didSet {
            if isBufferReady && !oldValue {
                didBufferBecomeReady?()
            }
        }
    }
    
    public var shouldIgnoreAheadOfTimeNextFrame: Bool = false
    
    public let metalView: MTKView
    
    private var vertexCount: Int = 0
    private var vertexBuffer: MTLBuffer?
    private var samplerState: MTLSamplerState?
    
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    
    private let textureBufferManager: HLSBufferManager<HLSTexture>
    private var firstTexture: HLSTexture?
    private var lastTexture: HLSTexture?
    
    private var taskQueue: SimpleQueue<HLSVideoBufferTask>
    private let videoRenderQueue: DispatchQueue = DispatchQueue(label: "com.hlsplayer.videoRenderQueue", qos: .userInitiated)
    
    public let timebase: CMTimebase
    
    public init(timebase: CMTimebase, textureBufferManager: HLSBufferManager<HLSTexture>) {
        self.timebase = timebase
        self.textureBufferManager = textureBufferManager
//        self.textureBufferManager.callbackQueue = videoRenderQueue
        self.taskQueue = SimpleQueue()
        let device = MTLCreateSystemDefaultDevice()
        self.metalView = MTKView(frame: .zero, device: device)
        self.device = device
        self.commandQueue = device?.makeCommandQueue()
        super.init()
        self.setup()
    }
    
    deinit {
        print("\(Self.self) deinit")
    }
    
    private func setup() {
        device = MTLCreateSystemDefaultDevice()
        commandQueue = device.makeCommandQueue()
        
        metalView.device = device
        metalView.delegate = self
        metalView.isPaused = true
        
        pipelineState = configurePipelaneState()
        samplerState = configureSamplerState()
        
        setupVertexBuffer()
        
        taskQueue.didStartQueue = { [weak self] in
            self?.startTextureBufferization()
        }
        
        textureBufferManager.didFilledBuffer = { [weak self] in
            self?.isBufferReady = true
        }
        
        textureBufferManager.didFreedBuffer = { [weak self] _ in
            self?.updateTextureBuffer()
        }
    }
    
    public func reset() {
        requestVideoFrames = nil
        didBufferBecomeReady = nil
    }
    
    private func configurePipelaneState() -> MTLRenderPipelineState? {
        let mainBundle = Bundle(for: HLSPlayer.self)
        
        guard let path = mainBundle.path(forResource: "HLSPlayerBundle", ofType: "bundle") else {
            return nil
        }
        guard let bundle = Bundle(path: path) else {
            return nil
        }
        
        guard let device = MTLCreateSystemDefaultDevice() else {
            return nil
        }

        guard let defaultLibrary = try? device.makeDefaultLibrary(bundle: bundle) else {
            return nil
        }

        guard let commandQueue = device.makeCommandQueue() else {
            return nil
        }
        self.commandQueue = commandQueue
        
        let pipelineDescriptor = configurePipelineDescriptor(library: defaultLibrary, pixelFormat: metalView.colorPixelFormat)
        return try? device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }
    
    private func configurePipelineDescriptor(library: MTLLibrary?, pixelFormat: MTLPixelFormat) -> MTLRenderPipelineDescriptor {
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        
        pipelineDescriptor.vertexFunction = library?.makeFunction(name: "vertexShader")
        pipelineDescriptor.fragmentFunction = library?.makeFunction(name: "fragmentShader")
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.vertexDescriptor = configureVertexDescriptor()
        
        return pipelineDescriptor
    }
    
    private func configureVertexDescriptor() -> MTLVertexDescriptor {
        let vertexDescriptor = MTLVertexDescriptor()
        
        vertexDescriptor.attributes[0].format = .float4
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        
        vertexDescriptor.attributes[1].format = .float4
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD4<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0

        vertexDescriptor.layouts[0].stride = MemoryLayout<Vertex>.stride
        vertexDescriptor.layouts[0].stepRate = 1

        return vertexDescriptor
    }
    
    private func configureSamplerState() -> (any MTLSamplerState)? {
        let samplerDescriptor = MTLSamplerDescriptor()
        
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge

        return device.makeSamplerState(descriptor: samplerDescriptor)
    }
    
    private func setupVertexBuffer() {
        let vertices: [Vertex] = [
            Vertex(position: SIMD4<Float>(-1, -1, 0, 1), texCoord: SIMD4<Float>(0, 1, 0, 0)),
            Vertex(position: SIMD4<Float>(-1, 1, 0, 1), texCoord: SIMD4<Float>(0, 0, 0, 0)),
            Vertex(position: SIMD4<Float>(1, -1, 0, 1), texCoord: SIMD4<Float>(1, 1, 0, 0)),
            Vertex(position: SIMD4<Float>(1, 1, 0, 1), texCoord: SIMD4<Float>(1, 0, 0, 0)),
        ]
        vertexCount = vertices.count
        vertexBuffer = device.makeBuffer(bytes: vertices, length: MemoryLayout<Vertex>.size * vertices.count, options: [])
    }
    
    public func setPreferredFramesPerSecond(_ frameRate: Int) {
        metalView.preferredFramesPerSecond = frameRate
    }
    
    public func updateTextureBuffer() {
        videoRenderQueue.async { [weak self] in
            guard let needItemsCount = self?.neededMediaFramesCount(), needItemsCount > 0 else { return }
            self?.enqueueTextureBufferingTask(count: needItemsCount)
        }
    }
    
    private func neededMediaFramesCount() -> Int {
        let enqueuedTaskItems = taskQueue.map(\.count).reduce(0, +)
        let bufferSize = textureBufferManager.bufferSize
        let maxBufferSize = textureBufferManager.maxBufferSize
        return maxBufferSize - enqueuedTaskItems - bufferSize
    }
    
    private func enqueueTextureBufferingTask(count: Int) {
        let task = HLSVideoBufferTask(count: count) { [weak self] textures in
            self?.textureBufferManager.addItems(textures)
        }
        taskQueue.enqueue(task)
    }
    
    private func startTextureBufferization() {
        while let task = taskQueue.dequeue() {
            let textures = createTextures(count: task.count)
            task.completion?(textures)
        }
    }
    
    private func createTextures(count: Int) -> [HLSTexture] {
        guard let requestedVideoFrames = requestVideoFrames?(count) else { return [] }
        return requestedVideoFrames.compactMap { createTexture(decodedFrame: $0) }
    }
    
    private func createTexture(decodedFrame: HLSMediaFrame) -> HLSTexture? {
        let sampleBuffer = decodedFrame.sampleBuffer
        guard let cvPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        
        var yCVMetalTexture: CVMetalTexture?
        var uvCVMetalTexture: CVMetalTexture?
        
        var textureCache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        
        guard let textureCache else {return nil }
        
        let yPixelFormat: MTLPixelFormat = .r8Unorm
        let uvPixelFormat: MTLPixelFormat = .rg8Unorm
        
        let width = CVPixelBufferGetWidth(cvPixelBuffer)
        let height = CVPixelBufferGetHeight(cvPixelBuffer)
        let uvWidth = width / 2
        let uvHeight = height / 2
        
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, cvPixelBuffer, nil, yPixelFormat, width, height, 0, &yCVMetalTexture)
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, cvPixelBuffer, nil, uvPixelFormat, uvWidth, uvHeight, 1, &uvCVMetalTexture)
        
        guard let yCVMetalTexture, let uvCVMetalTexture else {
            return nil
        }

        let yTexture = CVMetalTextureGetTexture(yCVMetalTexture)
        let uvTexture = CVMetalTextureGetTexture(uvCVMetalTexture)
        
        guard let yTexture, let uvTexture else {
            return nil
        }
        
        return HLSTexture(y: yTexture, uv: uvTexture, pts: decodedFrame.position)
    }
    
    private func nextTexture() -> HLSTexture? {
        return textureBufferManager.getNextItem()
    }
}

extension HLSVideoRenderer: MTKViewDelegate {
    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        else {
            return
        }
        
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        
        let timebaseTime = CMTimebaseGetTime(timebase)
        
        var textureForRender: HLSTexture?
        if let firstTexture = textureBufferManager.firstItem {
            switch firstTexture.presentationTimeState(forTime: timebaseTime) {
            case .onTime:
                textureForRender = nextTexture()
            case .behindTime:
                while let nextTexture = nextTexture() {
                    let presentationTimeState = nextTexture.presentationTimeState(forTime: timebaseTime)
                    if presentationTimeState == .behindTime {
                        continue
                    } else if presentationTimeState != .behindTime, nextTexture.pts >= firstTexture.pts {
                        textureForRender = nextTexture
                        break
                    }
                }
            case .aheadOfTime:
                if shouldIgnoreAheadOfTimeNextFrame {
                    shouldIgnoreAheadOfTimeNextFrame = false
                    textureForRender = nextTexture()
                } else {
                    textureForRender = lastTexture ?? nextTexture()
                }
            }
        } else {
            textureForRender = lastTexture
        }
    
        if let textureForRender {
            setFragments(texture: textureForRender, encoder: encoder)
        } else if let lastTexture {
            setFragments(texture: lastTexture, encoder: encoder)
        }
        
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    public func renderFirstTexture() {
        lastTexture = firstTexture
        firstTexture = nil
        draw(in: metalView)
    }
    
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {

    }
    
    private func setFragments(texture: HLSTexture, encoder: MTLRenderCommandEncoder) {
        encoder.setFragmentTexture(texture.y, index: 0)
        encoder.setFragmentTexture(texture.uv, index: 1)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: vertexCount)
        lastTexture = texture
        if firstTexture == nil {
            firstTexture = texture
        }
        didRenderTextureWithPts?(texture.pts)
    }
}
