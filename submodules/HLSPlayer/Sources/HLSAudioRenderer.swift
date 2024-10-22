import Foundation
import AVFoundation
import Accelerate

typealias HLSAudioBufferTask = HLSMediaTask<HLSAudioBuffer>

struct HLSMediaTask<Item> {
    let count: Int
    let completion: (([Item]) -> Void)?
}

struct HLSAudioBuffer {
    let buffer: AVAudioPCMBuffer
    let pts: CMTime
}

protocol HLSAudioRendererDelegate: AnyObject {
    func didRenderAudioBuffer(withPts pts: CMTime)
}

public final class HLSAudioRenderer: NSObject, HLSRenderer, HLSAudioRendererDelegate {
    public var requestAudioFrames: ((Int) -> [HLSMediaFrame])?
    public var didRenderAudioBufferWithPts: ((CMTime) -> Void)?
    public var didBufferBecomeReady: (() -> Void)?
    
    public var isBufferReady: Bool = false {
        didSet {
            if isBufferReady && !oldValue {
                didBufferBecomeReady?()
            }
        }
    }
    
    public var isAudioPlayerNeedsBuffering: Bool {
        audioPlayer.audioBufferSize / 2 <= audioPlayer.scheduledBufferCount
    }
    
    let audioPlayer: HLSAudioPlayer
    
    private let pcmBufferManager: HLSBufferManager<HLSAudioBuffer>
    private let taskQueue: SimpleQueue<HLSAudioBufferTask>
    
    private let audioRenderQueue: DispatchQueue = DispatchQueue(label: "com.hlsplayer.audioRenderQueue", qos: .userInitiated)
    
    public let timebase: CMTimebase
    
    init(timebase: CMTimebase, pcmBufferManager: HLSBufferManager<HLSAudioBuffer>) {
        self.timebase = timebase
        self.audioPlayer = HLSAudioPlayer(audioBufferSize: 60)
        self.pcmBufferManager = pcmBufferManager
//        self.pcmBufferManager.callbackQueue = audioRenderQueue
        self.taskQueue = SimpleQueue()
        super.init()
        self.audioPlayer.delegate = self
        self.setup()
    }
    
    deinit {
        print("\(Self.self) deinit")
    }
    
    private func setup() {
        taskQueue.didStartQueue = { [weak self] in
            self?.startAudioBufferization()
        }
        
        pcmBufferManager.didFilledBuffer = { [weak self] in
            self?.audioRenderQueue.async {
                self?.isBufferReady = true
            }
        }
        
        pcmBufferManager.didAddItems = { [weak self] in
            self?.audioRenderQueue.async {
                self?.updatePlayerScheduleBuffer()
            }
        }
        
        pcmBufferManager.didFreedBuffer = { [weak self] _ in
            self?.audioRenderQueue.async {
                self?.updatePCMBuffer()
            }
        }
        
        audioPlayer.didFreedScheduleBuffer = { [weak self] in
            self?.audioRenderQueue.async {
                self?.updatePlayerScheduleBuffer()
            }
        }
    }
    
    public func resetPlayer() {
        audioRenderQueue.async { [weak self] in
            self?.audioPlayer.reset()
        }
    }
    
    public func startPlayer() {
        audioRenderQueue.async { [weak self] in
            self?.audioPlayer.play()
        }
    }
    
    public func pausePlayer() {
        audioRenderQueue.async { [weak self] in
            self?.audioPlayer.pause()
        }
    }
    
    public func stopPlayer() {
        audioRenderQueue.async { [weak self] in
            self?.audioPlayer.stop()
        }
    }
    
    public func setVolume(_ volume: Float) {
        audioRenderQueue.async { [weak self] in
            self?.audioPlayer.playerNode.volume = volume
        }
    }
    
    public func didRenderAudioBuffer(withPts pts: CMTime) {
        didRenderAudioBufferWithPts?(pts)
    }
    
    public func updatePCMBuffer() {
        audioRenderQueue.async { [weak self] in
            guard let needItemsCount = self?.neededMediaFramesCount(), needItemsCount > 0 else { return }
            self?.enqueueAudioBufferingTask(count: needItemsCount)
        }
    }
    
    private func updatePlayerScheduleBuffer() {
        guard case .need(let count) = audioPlayer.audioBufferState else { return }
        guard let audioBuffers = pcmBufferManager.getNextItems(count: count) else { return }
        audioPlayer.scheduleAudioBuffers(audioBuffers)
    }
    
    private func neededMediaFramesCount() -> Int {
        let enqueuedTaskItems = taskQueue.map(\.count).reduce(0, +)
        let bufferSize = pcmBufferManager.bufferSize
        let maxBufferSize = pcmBufferManager.maxBufferSize
        return maxBufferSize - enqueuedTaskItems - bufferSize
    }
    
    private func enqueueAudioBufferingTask(count: Int) {
        let task = HLSAudioBufferTask(count: count) { [weak self] items in
            self?.pcmBufferManager.addItems(items)
        }
        taskQueue.enqueue(task)
    }
    
    private func startAudioBufferization() {
        while let task = taskQueue.dequeue() {
            let audioBuffers = createAudioBuffers(count: task.count)
            task.completion?(audioBuffers)
        }
    }
    
    private func createAudioBuffers(count: Int) -> [HLSAudioBuffer] {
        guard let requestedAudioFrames = requestAudioFrames?(count) else { return [] }
        return requestedAudioFrames.compactMap { createAudioBuffer(from: $0) }
    }
    
    private func createAudioBuffer(from mediaFrame: HLSMediaFrame) -> HLSAudioBuffer? {
        guard mediaFrame.type == .audio else { return nil }
        guard let pcmBuffer = AVAudioPCMBuffer.create(from: mediaFrame.sampleBuffer) else { return nil }
        return HLSAudioBuffer(buffer: pcmBuffer, pts: mediaFrame.position)
    }
}

final class HLSAudioPlayer {
    fileprivate var didFreedScheduleBuffer: (() -> Void)?
    
    fileprivate var audioBufferState: HLSBufferState {
        if scheduledBufferCount < audioBufferSize {
            return .need(count: audioBufferSize - scheduledBufferCount)
        } else {
            return .full
        }
    }
    
    fileprivate var scheduledBufferCount: Int = 0 {
        didSet {
            if scheduledBufferCount < 0 {
                scheduledBufferCount = 0
            }
            if scheduledBufferCount < audioBufferSize && oldValue > scheduledBufferCount {
                didFreedScheduleBuffer?()
            }
        }
    }
    
    fileprivate weak var delegate: HLSAudioRendererDelegate?
    
    private var isEnabled = true
    
    fileprivate var audioBufferSize: Int
    
    fileprivate var playerNode: AVAudioPlayerNode
    fileprivate let audioEngine: AVAudioEngine
    fileprivate let audioFormat: AVAudioFormat
    fileprivate let audioSession: AVAudioSession
    fileprivate let timePitch: AVAudioUnitTimePitch
    fileprivate let audioMixerNode: AVAudioMixerNode
    
    public init(audioBufferSize: Int, sampleRate: Float64 = 44100.0, channelCount: AVAudioChannelCount = 1) {
        self.audioBufferSize = audioBufferSize
        self.playerNode = AVAudioPlayerNode()
        self.audioEngine = AVAudioEngine()
        self.audioFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channelCount)!
        self.audioSession = .sharedInstance()
        self.timePitch = AVAudioUnitTimePitch()
        self.audioMixerNode = AVAudioMixerNode()
        self.setup()
    }
    
    deinit {
        print("\(Self.self) deinit")
    }
    
    private func setup() {
        audioEngine.attach(playerNode)
        audioEngine.attach(timePitch)
        audioEngine.attach(audioMixerNode)
        
        audioEngine.connect(playerNode, to: timePitch, format: audioFormat)
        audioEngine.connect(timePitch, to: audioMixerNode, format: audioFormat)
        audioEngine.connect(audioMixerNode, to: audioEngine.mainMixerNode, format: audioFormat)
        
        timePitch.pitch = 0.0

        do {
            try audioSession.setCategory(.playback, options: .mixWithOthers)
            try audioSession.setActive(true)
        } catch {
            print("Error creating audio session: \(error)")
        }

        do {
            try audioEngine.start()
        } catch {
            print("Error starting audio engine: \(error)")
        }
    }
    
    public func reset() {
        isEnabled = false
        
        playerNode.stop()
        print("stop")
        audioEngine.pause()
        audioEngine.reset()
        
        do {
            try audioEngine.start()
        } catch {
            print("Error restarting audio engine: \(error)")
        }
        
        audioEngine.attach(playerNode)
        audioEngine.attach(timePitch)
        audioEngine.attach(audioMixerNode)
        
        audioEngine.connect(playerNode, to: timePitch, format: audioFormat)
        audioEngine.connect(timePitch, to: audioMixerNode, format: audioFormat)
        audioEngine.connect(audioMixerNode, to: audioEngine.mainMixerNode, format: audioFormat)
        
        timePitch.pitch = 0.0
        
        audioBufferSize = 0
        scheduledBufferCount = 0
    }
    
    public func play() {
        audioBufferSize = 60
        audioEngine.prepare()
        try? audioEngine.start()
        playerNode.play()
        isEnabled = true
    }
    
    public func pause() {
        playerNode.pause()
    }
    
    public func stop() {
        playerNode.stop()
        audioEngine.stop()
    }
    
    public func setRate(_ rate: Float) {
        timePitch.rate = max(0.2, min(2.5, rate))
    }
    
    public func setVolume(_ volume: Float) {
        audioMixerNode.outputVolume = max(0.0, min(1.0, volume))
    }
    
    public func scheduleAudioBuffers(_ audioBuffers: [HLSAudioBuffer]) {
        guard isEnabled else { return }
        scheduledBufferCount += audioBuffers.count
        for audioBuffer in audioBuffers {
            guard isEnabled else { break }
            scheduleAudioBuffer(audioBuffer)
        }
    }
    
    private func scheduleAudioBuffer(_ audioBuffer: HLSAudioBuffer) {
        let pts = audioBuffer.pts
        playerNode.scheduleBuffer(audioBuffer.buffer) { [weak self] in
            self?.scheduledBufferCount -= 1
            self?.delegate?.didRenderAudioBuffer(withPts: pts)
        }
    }
}

extension AVAudioPCMBuffer {
    static func create(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let basicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description)
        else {
            return nil
        }
        
        let sampleRate = basicDescription.pointee.mSampleRate
        let channelsPerFrame = basicDescription.pointee.mChannelsPerFrame
        
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return nil
        }
        
        let audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channelsPerFrame),
            interleaved: true
        )
        
        let samplesCount = CMSampleBufferGetNumSamples(sampleBuffer)
        let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat!, frameCapacity: AVAudioFrameCount(samplesCount))!
        buffer.frameLength = buffer.frameCapacity
        
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: nil, dataPointerOut: &dataPointer)
        guard status == noErr else {
            return nil
        }
        
        guard let channel = buffer.floatChannelData?[0], let data = dataPointer else {
            return nil
        }
        
        let data16 = UnsafeRawPointer(data).assumingMemoryBound(to: Int16.self)
        convertSamplesAccelerate(data16, channel, count: samplesCount)
        
        return buffer
    }
}

private func convertSamplesAccelerate(_ input: UnsafePointer<Int16>, _ output: UnsafeMutablePointer<Float>, count: Int) {
    var scale: Float = 1.0 / Float(Int16.max)
    vDSP_vflt16(input, 1, output, 1, vDSP_Length(count))
    vDSP_vsmul(output, 1, &scale, output, 1, vDSP_Length(count))
}
