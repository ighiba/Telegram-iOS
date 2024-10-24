import Foundation
import AVFoundation

public enum HLSRendererState {
    case unprepared
    case rendering
    case paused
    case stopped
}

public protocol HLSMediaRendererDelegate: AnyObject {
    func didRenderFrame(withPts pts: CMTime)
    func didChangeIsBuffering(_ isBuffering: Bool)
    func didUpdateBufferingStatistics(bufferingCount: Int, totalBufferingTime: TimeInterval, playbackTime: TimeInterval)
}

public protocol HLSRenderer: AnyObject {
    var didBufferBecomeReady: (() -> Void)? { get set }
    var isBufferReady: Bool { get }
    var timebase: CMTimebase { get }
}

public final class HLSMediaRenderer {
    public var didPreparedForRendering: (() -> Void)?
    
    public weak var delegate: HLSMediaRendererDelegate?
    
    private(set) var rendererState: HLSRendererState = .unprepared {
        didSet {
            didChangeRendererState(rendererState)
        }
    }
    
    private var isBuffering: Bool = false {
        didSet {
            didChangeIsBuffering(isBuffering)
        }
    }
    
    public var hasAudioStream: Bool = true
    
    private var bufferingCount: Int = 0
    private var totalBufferingTime: Double = 0.0
    private var bufferingStartTime: Date?
    private var bufferingTimer: Timer?
    
    private let playerContext: HLSPlayerContext
    private let bufferManagersContext: HLSBufferManagersContext
    
    public let videoFrameBufferManager: HLSBufferManager<HLSMediaFrame>
    public let audioFrameBufferManager: HLSBufferManager<HLSMediaFrame>
    
    public let videoRenderer: HLSVideoRenderer
    public let audioRenderer: HLSAudioRenderer
    
    init(playerContext: HLSPlayerContext, bufferManagersContext: HLSBufferManagersContext) {
        self.playerContext = playerContext
        self.bufferManagersContext = bufferManagersContext
        self.videoFrameBufferManager = bufferManagersContext.videoFrameBufferManager
        self.audioFrameBufferManager = bufferManagersContext.audioFrameBufferManager
        self.videoRenderer = HLSVideoRenderer(timebase: playerContext.controlTimebase, textureBufferManager: bufferManagersContext.textureBufferManager)
        self.audioRenderer = HLSAudioRenderer(timebase: playerContext.controlTimebase, pcmBufferManager: bufferManagersContext.pcmBufferManager)
        self.setup()
    }
    
    deinit {
        print("\(Self.self) deinit")
    }
    
    private func setup() {
        videoRenderer.didBufferBecomeReady = { [weak self] in
            guard let self else { return }
            let isAudioBufferReady = self.hasAudioStream ? self.audioRenderer.isBufferReady : true
            self.handleBufferReady(
                isVideoBufferReady: true,
                isAudioBufferReady: isAudioBufferReady
            )
        }
        
        audioRenderer.didBufferBecomeReady = { [weak self] in
            guard let self else { return }
            self.handleBufferReady(
                isVideoBufferReady: self.videoRenderer.isBufferReady,
                isAudioBufferReady: true
            )
        }
        
        videoFrameBufferManager.didAddItems = { [weak self] in
            self?.videoRenderer.updateTextureBuffer()
        }
        
        audioFrameBufferManager.didAddItems = { [weak self] in
            self?.audioRenderer.updatePCMBuffer()
        }
        
        videoRenderer.requestVideoFrames = { [weak self] requestFramesCount in
            return self?.videoFrameBufferManager.getNextItems(count: requestFramesCount) ?? []
        }
        
        audioRenderer.requestAudioFrames = { [weak self] requestFramesCount in
            return self?.audioFrameBufferManager.getNextItems(count: requestFramesCount) ?? []
        }
        
        videoRenderer.didRenderTextureWithPts = { [weak self] lastRenderPts in
            guard self?.hasAudioStream == false else { return }
            self?.delegate?.didRenderFrame(withPts: lastRenderPts)
        }
        
        audioRenderer.didRenderAudioBufferWithPts = { [weak self] lastRenderPts in
            guard self?.hasAudioStream == true else { return }
            self?.delegate?.didRenderFrame(withPts: lastRenderPts)
        }
        
        bufferManagersContext.textureBufferManager.didEmptiedBuffer = { [weak self] in
            guard let self else { return }
            handleBufferEmptied(isBufferReadyFlag: &self.videoRenderer.isBufferReady)
        }
        
        bufferManagersContext.pcmBufferManager.didEmptiedBuffer = { [weak self] in
            guard let self else { return }
            guard audioRenderer.isAudioPlayerNeedsBuffering else { return }
            handleBufferEmptied(isBufferReadyFlag: &self.audioRenderer.isBufferReady)
        }
    }
    
    public func reset() {
        stopBuffering()
        bufferingTimer?.invalidate()
        bufferingTimer = nil
        videoRenderer.reset()
        audioRenderer.reset()
    }
    
    public func startRendering() {
        print("START RENDERING")
        guard rendererState != .unprepared else { return }
        startPlayback()
    }
    
    public func pauseRendering() {
        print("PAUSE RENDERING")
        pausePlayback()
    }
    
    public func stopRendering() {
        if hasAudioStream {
            audioRenderer.stopPlayer()
        } else {
            CMTimebaseSetRate(playerContext.controlTimebase, rate: 0.0)
        }
        videoRenderer.metalView.isPaused = true
        rendererState = .stopped
    }
    
    private func startPlayback() {
        if hasAudioStream {
            audioRenderer.startPlayer()
        } else {
            CMTimebaseSetRate(playerContext.controlTimebase, rate: Float64(playerContext.rate))
        }
        videoRenderer.metalView.isPaused = false
        rendererState = .rendering
    }
    
    private func pausePlayback() {
        if hasAudioStream {
            audioRenderer.pausePlayer()
        } else {
            CMTimebaseSetRate(playerContext.controlTimebase, rate: 0.0)
        }
        videoRenderer.metalView.isPaused = true
        rendererState = .paused
    }
    
    private func startBuffering() {
        guard !isBuffering else { return }
        print("START BUFFERING")
        isBuffering = true
        bufferingCount += 1
        bufferingStartTime = Date()
        pausePlayback()
        startBufferingTimer()
    }
    
    private func stopBuffering() {
        print("STOP BUFFERING")
        isBuffering = false
        bufferingTimer?.invalidate()
        bufferingTimer = nil
        
        if let bufferingStartTime {
            let bufferingTime = Date().timeIntervalSince(bufferingStartTime)
            totalBufferingTime += bufferingTime
            delegate?.didUpdateBufferingStatistics(
                bufferingCount: bufferingCount,
                totalBufferingTime: totalBufferingTime,
                playbackTime: CMTimebaseGetTime(playerContext.controlTimebase).seconds
            )
            #if DEBUG
            print("Buffering duration: \(bufferingTime) seconds; Total: \(totalBufferingTime)")
            #endif
        }
        
        bufferingStartTime = nil
        startPlayback()
    }
    
    private func startBufferingTimer() {
        bufferingTimer?.invalidate()
        bufferingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkBufferingStatus()
        }
    }
    
    private func checkBufferingStatus() {
        handleBufferReady(isVideoBufferReady: videoRenderer.isBufferReady, isAudioBufferReady: audioRenderer.isBufferReady)
    }
    
    public func resetBufferingStatistics() {
        bufferingCount = 0
        totalBufferingTime = 0
    }
    
    public func setPlaybackRate(_ rate: Float) {
        if hasAudioStream {
            audioRenderer.audioPlayer.setRate(rate)
        } else if !CMTimebaseGetRate(playerContext.controlTimebase).isZero {
            CMTimebaseSetRate(playerContext.controlTimebase, rate: Float64(rate))
        }
    }
    
    public func setVideoPlaybackFrameRate(_ frameRate: Int) {
        videoRenderer.setPreferredFramesPerSecond(frameRate)
    }
    
    public func setVolume(_ volume: Float) {
        audioRenderer.audioPlayer.setVolume(volume)
    }
    
    private func handleBufferReady(isVideoBufferReady: Bool, isAudioBufferReady: Bool) {
        if playerContext.isDecondingEnded {
            stopBuffering()
            return
        }
        
        guard isVideoBufferReady && isAudioBufferReady else { return }
        
        if isBuffering {
            stopBuffering()
        } else {
            rendererState = .rendering
            didPreparedForRendering?()
        }
    }
    
    private func handleBufferEmptied(isBufferReadyFlag: inout Bool ) {
        guard !playerContext.isDecondingEnded else { return }
        startBuffering()
        isBufferReadyFlag = false
    }
    
    private func isControlTimeValid(comparingWith time: CMTime) -> Bool {
        let controlTime = CMTimebaseGetTime(playerContext.controlTimebase)
        let absTimeDifference = CMTimeSubtract(controlTime, time)
        return CMTimeAbsoluteValue(absTimeDifference) < CMTime(value: 1, timescale: 10)
    }
    
    private func didChangeRendererState(_ rendererState: HLSRendererState) {
        #if DEBUG
        print("-=RENDERER STATE: \(rendererState)=-")
        #endif
    }
    
    private func didChangeIsBuffering(_ isBuffering: Bool) {
        delegate?.didChangeIsBuffering(isBuffering)
    }
}
