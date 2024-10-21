import Foundation
import AVFoundation
import MetalKit

private let rateBounds: (min: Float, max: Float) = (0.0, 2.5)
private let frameRateBounds: (min: Int, max: Int)  = (30, 90)
private let volumeBounds: (min: Float, max: Float)  = (0.0, 1.0)

final class HLSPlayerContext {
    let controlClock: CMClock
    let controlTimebase: CMTimebase
    fileprivate(set) var rate: Float
    fileprivate(set) var startTime: CMTime
    fileprivate(set) var duration: CMTime
    fileprivate(set) var lastPresentationTimestamp: CMTime
    fileprivate(set) var isDecondingEnded: Bool = false
    
    init(controlClock: CMClock, controlTimebase: CMTimebase, rate: Float = 1.0, startTime: CMTime = .zero, duration: CMTime = .zero) {
        self.controlClock = controlClock
        self.controlTimebase = controlTimebase
        self.rate = rate
        self.startTime = startTime
        self.duration = duration
        self.lastPresentationTimestamp = startTime
    }
}

public final class HLSPlayer {
    
    // MARK: - Properties
    
    private(set) var isPlaying: Bool = false
    private(set) var isPlaybackStarted: Bool = false
    
    public var rate: Float = 1.0 {
        didSet {
            rate = min(rateBounds.max, max(0.2, rate))
            didSetRate(rate)
        }
    }
    
    public var defaultRate: Float = 1.0 {
        didSet {
            defaultRate = min(rateBounds.max, max(rateBounds.min, rate))
        }
    }
    
    public var volume: Float = 1.0 {
        didSet {
            volume = min(volumeBounds.max, max(volumeBounds.min, volume))
            didSetVolume(volume)
        }
    }
    
    public var isMuted: Bool = false {
        didSet {
            didSetIsMuted(isMuted)
        }
    }
    
    private var videoPlaybackFrameRate: Int = 24 {
        didSet {
            updateVideoRenderFrameRate()
        }
    }
    
    private var preferAutoQuality: Bool {
        currentItem?.preferredPeakBitRate == 0
    }
    
    private var videoPlaybackFrameRateActual: Int {
        let multipliedFps = Int(Float(videoPlaybackFrameRate) * rate)
        return min(frameRateBounds.max, max(frameRateBounds.min, multipliedFps))
    }
    
    public var metalView: MTKView {
        mediaRenderer.videoRenderer.metalView
    }
    
    private(set) var currentItem: HLSPlayerItem?
    
    private let mediaDecoder: HLSMediaDecoder
    private let mediaRenderer: HLSMediaRenderer
    
    private let playerContext: HLSPlayerContext
    private let bufferManagersContext: HLSBufferManagersContext
    
    private var videoFrameBufferManager: HLSBufferManager<HLSMediaFrame> {
        bufferManagersContext.videoFrameBufferManager
    }
    private var audioFrameBufferManager: HLSBufferManager<HLSMediaFrame> {
        bufferManagersContext.audioFrameBufferManager
    }
    
    private let decodeQueue = DispatchQueue(label: "com.hlsplayer.decodeQueue", qos: .userInitiated)
    
    private var endOfStreamDebounceTimer: Timer?
    private var endOfStreamPosition: CMTime?
    
    // MARK: - Init
    
    convenience public init(url: URL) {
        self.init()
        self.replaceCurrentItem(with: HLSPlayerItem(url: url))
    }
    
    convenience public init(currentItem: HLSPlayerItem) {
        self.init()
        self.replaceCurrentItem(with: currentItem)
    }
    
    public init() {
        let controlClock = CMClockGetHostTimeClock()
        var controlTimebase: CMTimebase!
        CMTimebaseCreateWithSourceClock(allocator: nil, sourceClock: controlClock, timebaseOut: &controlTimebase)
        CMTimebaseSetRate(controlTimebase, rate: 0.0)
        
        let playerContext =  HLSPlayerContext(
            controlClock: controlClock,
            controlTimebase: controlTimebase
        )
        let bufferManagersContext = HLSBufferManagersContext(
            videoFrameBufferManager: HLSBufferManager(maxBufferSize: 60, label: "Video", isLoggingEnabled: false),
            textureBufferManager: HLSBufferManager(maxBufferSize: 60, label: "Texture", isLoggingEnabled: false),
            audioFrameBufferManager: HLSBufferManager(maxBufferSize: 60, label: "Audio", isLoggingEnabled: false),
            pcmBufferManager: HLSBufferManager(maxBufferSize: 60, label: "PCM", isLoggingEnabled: false)
        )
        let mediaRenderer = HLSMediaRenderer(
            playerContext: playerContext,
            bufferManagersContext: bufferManagersContext
        )
        
        self.mediaDecoder = HLSMediaDecoder()
        self.playerContext = playerContext
        self.bufferManagersContext = bufferManagersContext
        self.mediaRenderer = mediaRenderer
        self.setup()
    }
    
    // MARK: - Methods
    
    private func setup() {
        mediaRenderer.delegate = self
        
        mediaRenderer.didPreparedForRendering = { [weak self] in
            if self?.isPlaying != false {
                self?.mediaRenderer.startRendering()
            }
        }
        
        videoFrameBufferManager.didFreedBuffer = { [weak self] availableBufferSize in
            guard let self else { return }
            self.decodeQueue.async {
                let pendingFrameCount = self.mediaDecoder.enqueuedFramesCount(withType: .video)
                let videoBufferSize = self.videoFrameBufferManager.bufferSize
                let videoBufferSizeMax = self.videoFrameBufferManager.maxBufferSize
                guard pendingFrameCount + videoBufferSize < videoBufferSizeMax else { return }
                let framesToDecodeCount = videoBufferSizeMax - pendingFrameCount - videoBufferSize
                let videoDecodeTask = HLSDecodeTask(frameType: .video, decodeCount: framesToDecodeCount) { decodedFrames, remainingFrames in
                    self.videoFrameBufferManager.addItems(decodedFrames)
                    self.audioFrameBufferManager.addItems(remainingFrames)
                }
                self.mediaDecoder.enqueueDecodeTask(videoDecodeTask)
            }
        }
        
        audioFrameBufferManager.didFreedBuffer = { [weak self] availableBufferSize in
            guard let self else { return }
            self.decodeQueue.async {
                let pendingFrameCount = self.mediaDecoder.enqueuedFramesCount(withType: .audio)
                let audioBufferSize = self.audioFrameBufferManager.bufferSize
                let audioBufferSizeMax = self.audioFrameBufferManager.maxBufferSize
                guard pendingFrameCount + audioBufferSize < audioBufferSizeMax else { return }
                let framesToDecodeCount = audioBufferSizeMax - pendingFrameCount - audioBufferSize
                let audioDecodeTask = HLSDecodeTask(frameType: .audio, decodeCount: framesToDecodeCount) { decodedFrames, remainingFrames in
                    self.audioFrameBufferManager.addItems(decodedFrames)
                    self.videoFrameBufferManager.addItems(remainingFrames)
                }
                self.mediaDecoder.enqueueDecodeTask(audioDecodeTask)
            }
        }
        
        mediaDecoder.didSeekStart = { [weak self] seekType in
            print("DID SEEK START with type: \(seekType)")
            if seekType == .default {
                self?.isMuted = true
                self?.mediaRenderer.stopRendering()
                self?.bufferManagersContext.flushBuffers()
            }
        }
        
        mediaDecoder.didSeekEnd = { [weak self] seekType in
            guard let self else { return }
            if seekType == .default {
                self.mediaRenderer.audioRenderer.resetPlayer()
                CMTimebaseSetTime(self.playerContext.controlTimebase, time: self.playerContext.startTime)
                self.mediaRenderer.videoRenderer.shouldIgnoreAheadOfTimeNextFrame = true
                self.mediaRenderer.startRendering()
                self.isMuted = false
            }
            print("DID SEEK END with type: \(seekType)")
        }
        
        mediaDecoder.didFoundEndOfFilePosition = { [weak self] endOfStreamPosition in
            self?.playerContext.isDecondingEnded = true
            self?.endOfStreamPosition = endOfStreamPosition
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
//            self.stopPlayback()
//            self.currentItem?.preferredPeakBitRate = 14000000
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
//                self.startPlayback()
//                print("TO AUTO QUALITY")
//                self.currentItem?.preferredPeakBitRate = 0
            }
        }
    }
    
    public func replaceCurrentItem(with item: HLSPlayerItem) {
        endPlayback()
        currentItem = item
        currentItem?.didSwitchSelectedStream = { [weak self] newStream in
            self?.didSwitchSelectedStream(newStream)
        }
    }
    
    public func play() {
        if !isPlaybackStarted {
            isPlaybackStarted = true
            startPlayback()
        } else {
            mediaRenderer.startRendering()
        }
        isPlaying = true
    }
    
    public func pause() {
        mediaRenderer.pauseRendering()
        isPlaying = false
    }
    
    private func startPlayback() {
        guard let currentItem else {
            print("HLSPlayer.startPlayback: No currentItem")
            return
        }
        
        print("startPlayback")
        
        let videoDecodeTask = HLSDecodeTask(frameType: .video, decodeCount: 30) { decodedVideoFrames, remainingFrames in
            self.videoFrameBufferManager.addItems(decodedVideoFrames)
            self.audioFrameBufferManager.addItems(remainingFrames)
        }
        let audioDecodeTask = HLSDecodeTask(frameType: .audio, decodeCount: 30) { decodedAudioFrames, remainingFrames in
            self.videoFrameBufferManager.addItems(remainingFrames)
            self.audioFrameBufferManager.addItems(decodedAudioFrames)
        }
        
        mediaDecoder.enqueueDecodeTask(videoDecodeTask)
        mediaDecoder.enqueueDecodeTask(audioDecodeTask)
        
        if let mediaSource = currentItem.mediaSource {
            openMediaSource(mediaSource)
            self.isPlaybackStarted = true
        } else {
            currentItem.didPreparedMediaSource = { [weak self] mediaSource in
                self?.openMediaSource(mediaSource)
                self?.isPlaybackStarted = true
            }
        }
    }
    
    private func endPlayback() {
        print("endPlayback")
        isPlaying = false
        isPlaybackStarted = false
        mediaDecoder.stopDecoding()
        mediaRenderer.stopRendering()
        bufferManagersContext.flushBuffers()
        endOfStreamPosition = nil
        endOfStreamDebounceTimer?.invalidate()
        endOfStreamDebounceTimer = nil
    }
    
    private func openMediaSource(_ mediaSource: HLSMediaSource) {
        videoPlaybackFrameRate = Int(mediaSource.videoStreamContext?.fps.value ?? 0)
        playerContext.startTime = mediaSource.videoStreamContext?.startTime ?? .zero
        playerContext.duration = mediaSource.getMediaDuration() ?? .zero
        decodeQueue.async { [weak self] in
            self?.mediaDecoder.openMediaSource(mediaSource)
            self?.mediaDecoder.startDecoding()
            self?.mediaRenderer.startRendering()
        }
    }
    
    public func currentTime() -> CMTime {
        return CMTimebaseGetTime(playerContext.controlTimebase)
    }
    
    private func didSwitchSelectedStream(_ newStream: HLSStream) {
        mediaRenderer.resetBufferingStatistics()
        DispatchQueue.global().async { [weak self] in
            print("LOAD NEW MEDIA SOURCE")
            guard let newMediaSource = HLSMediaSource(url: newStream.url) else {
                print("Failed to load new media source")
                return
            }
            print("LOADED")
            self?.decodeQueue.async {
                print("START SEEK")
                self?.mediaDecoder.switchStream(newMediaSource: newMediaSource)
            }
        }
    }
    
    private func didSetRate(_ rate: Float) {
        playerContext.rate = rate
        mediaRenderer.setAudioPlaybackRate(rate)
        mediaRenderer.setVideoPlaybackFrameRate(videoPlaybackFrameRateActual)
    }
    
    private func didSetVolume(_ volume: Float) {
        if !isMuted {
            mediaRenderer.setVolume(volume)
        }
    }
    
    private func didSetIsMuted(_ isMuted: Bool) {
        let targetVolume = isMuted ? 0.0 : volume
        mediaRenderer.setVolume(targetVolume)
    }
    
    private func updateVideoRenderFrameRate() {
        mediaRenderer.setVideoPlaybackFrameRate(videoPlaybackFrameRateActual)
    }
}

extension HLSPlayer: HLSMediaRendererDelegate {
    public func didEndBuffering(bufferingCount: Int, totalBufferingTime: TimeInterval, playbackTime: TimeInterval) {
        let shouldDowngradeQuality = shouldDowngradeQuality(bufferingCount: bufferingCount, totalBufferingTime: totalBufferingTime, playbackTime: playbackTime)
        print(shouldDowngradeQuality)
        
        if shouldDowngradeQuality, preferAutoQuality {
            currentItem?.downgradeStreamQuality()
        }
    }
    
    func shouldDowngradeQuality(bufferingCount: Int, totalBufferingTime: TimeInterval, playbackTime: TimeInterval) -> Bool {
        guard playbackTime < playerContext.duration.seconds * 0.9 else { return false }
        
        let bufferingFrequencyThreshold = 5
        let bufferingTimeThresholdRatio = 0.3
        
        let bufferingRatio = totalBufferingTime / playbackTime
        let bufferingFrequencyRatio = Double(bufferingCount) / playbackTime

        print("bufferingCount \(bufferingCount)")
        print("bufferingRatio \(bufferingRatio)")
        print("bufferingFrequencyRatio \(bufferingFrequencyRatio)")
        
        return bufferingCount >= bufferingFrequencyThreshold &&
               bufferingRatio >= bufferingTimeThresholdRatio
    }
    
    public func didRenderFrame(withPts pts: CMTime) {
        playerContext.lastPresentationTimestamp = pts
        
//        print("lastPts: \(pts.seconds), duration: \(playerContext.duration.seconds)")

        let tolerance: Double = 0.1
        if let endOfStreamPosition = endOfStreamPosition {
            guard abs(pts.seconds - endOfStreamPosition.seconds) <= tolerance else { return }
            DispatchQueue.main.async {
                self.debounceEndOfStreamTimer()
            }
        } else if playerContext.duration.seconds > 0 {
            guard abs(pts.seconds - playerContext.duration.seconds) <= tolerance else { return }
            DispatchQueue.main.async {
                self.debounceEndOfStreamTimer()
            }
        }
    }
    
    private func isBuffersEmpty() -> Bool {
        return bufferManagersContext.isBuffersEmpty()
    }
    
    private func debounceEndOfStreamTimer() {
        endOfStreamDebounceTimer?.invalidate()
        endOfStreamDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in
            if self.isBuffersEmpty() {
                print("END OF STREAM - No more frames in buffers")
                self.endPlayback()
            }
        }
    }
}
