import Foundation
import CoreMedia
import FFMpegBinding

private var isSimulatorEnvironment: Bool {
    #if targetEnvironment(simulator)
    return true
    #else
    return false
    #endif
}

class SimpleQueue<T> {
    var didStartQueue: (() -> Void)?
    
    private let queueLock: NSLock
    private var items: [T]
    
    init() {
        self.queueLock = NSLock()
        self.items = []
    }
    
    func enqueue(_ item: T) {
        queueLock.lock()
        items.append(item)
        queueLock.unlock()
        if items.count == 1 {
            didStartQueue?()
        }
    }
    
    func dequeue() -> T? {
        queueLock.lock()
        if items.count > 0 {
            let item = items.removeFirst()
            queueLock.unlock()
            return item
        }
        queueLock.unlock()
        return nil
    }
    
    func reset() {
        queueLock.lock()
        items = []
        queueLock.unlock()
    }
    
    func count() -> Int {
        return items.count
    }
    
    func filterCount(_ filter: (T) -> Bool) -> Int {
        return items.filter(filter).count
    }
    
    func map<U>(_ transform: (T) -> U) -> [U] {
        return items.map(transform)
    }
}

public enum HLSSeekType {
    case `default`
    case streamSwitch
}

public struct HLSDecodeTask {
    let frameType: HLSMediaFrameType
    let decodeCount: Int
    let completion: (([HLSMediaFrame], [HLSMediaFrame]) -> Void)?
}

protocol HLSDecoder: AnyObject {
    func decode(frame: HLSMediaDecodableFrame) -> HLSMediaFrame?
}

public final class HLSMediaDecoder {
    private enum DecoderState {
        case noSource
        case ready
        case decoding
        case stopped
    }
    
    private struct SeekStatus {
        enum MediaState {
            case seeked
            case notSeeked
        }
        var seekType: HLSSeekType
        var pts: CMTime
        var videoState: MediaState = .notSeeked
        var audioState: MediaState = .notSeeked
    }
    
    private var isEnabled = false
    
    public var didSeekStart: ((HLSSeekType) -> Void)?
    public var didSeekEnd: ((HLSSeekType) -> Void)?
    public var didFoundEndOfFilePosition: ((CMTime) -> Void)?
    
    private var lastSeekStatus: SeekStatus?
    private var lastDecodedVideoFramePts: CMTime?
    private var lastDecodedAudioFramePts: CMTime?
    
    private var decoderState: DecoderState = .noSource
    private var currentDecodeTask: HLSDecodeTask?
    
    private var taskQueue: SimpleQueue<HLSDecodeTask>
    private var decodeSemaphore = DispatchSemaphore(value: 1)
    
    private var audioDecoder: HLSAudioDecoder?
    private var videoDecoder: HLSVideoDecoder?
    
    private var mediaSource: HLSMediaSource?
    private var formatContext: FFMpegAVFormatContext? { mediaSource?.formatContext }
    
    public init() {
        self.taskQueue = SimpleQueue()
    }
    
    deinit {
        print("\(Self.self) deinit")
    }
    
    public func reset() {
        mediaSource = nil
        decoderState = .noSource
        taskQueue.reset()
    }
    
    public func openMediaSource(_ mediaSource: HLSMediaSource) {
        self.mediaSource = mediaSource
        
        if let videoCodecContext = mediaSource.videoStreamContext?.codecContext {
            if !isSimulatorEnvironment {
                videoCodecContext.enableHardwareAcceleration()
            }
            videoDecoder = HLSVideoDecoder(codecContext: videoCodecContext)
        }
        
        if let audioCodecContext = mediaSource.audioStreamContext?.codecContext {
            audioDecoder = HLSAudioDecoder(codecContext: audioCodecContext)
        }
        
        decoderState = .ready
    }
    
    public func enqueuedFramesCount(withType frameType: HLSMediaFrameType) -> Int {
        var enqueuedFramesCount = taskQueue.filterCount({ $0.frameType == frameType })
        if let currentDecodeTask, currentDecodeTask.frameType == frameType {
            enqueuedFramesCount += currentDecodeTask.decodeCount
        }
        return enqueuedFramesCount
    }
    
    public func enqueueDecodeTask(_ decodeTask: HLSDecodeTask) {
        taskQueue.enqueue(decodeTask)
        if decoderState == .ready {
            startDecoding()
        }
    }
    
    public func startDecoding() {
        decodeSemaphore.wait()
        defer { decodeSemaphore.signal() }
        isEnabled = true
        while let task = taskQueue.dequeue() {
            currentDecodeTask = task
            decoderState = .decoding
            let decodedFrames = decodeTask(task)
            let taskFrames = decodedFrames.taskFrames
            let remainingFrames = decodedFrames.remaining
            task.completion?(taskFrames, remainingFrames)
            guard isEnabled else { break }
        }
        currentDecodeTask = nil
        decoderState = .ready
    }
    
    public func stopDecoding() {
        isEnabled = false
        decoderState = .stopped
    }
    
    private func decodeTask(_ task: HLSDecodeTask) -> (taskFrames: [HLSMediaFrame], remaining: [HLSMediaFrame]) {
        var decodedFrames: [HLSMediaFrame] = []
        var remainingDecodedFrames: [HLSMediaFrame] = []
        
        guard let mediaSource else { return (decodedFrames, remainingDecodedFrames) }
        
        let videoStreamIndex = mediaSource.videoStreamContext?.index ?? -1
        let audioStreamIndex = mediaSource.audioStreamContext?.index ?? -1
        
        var decodedFramesCount = 0
        while decodedFramesCount <= task.decodeCount {
            guard let packet = readPacket() else { return (decodedFrames, remainingDecodedFrames) }
            
            var currentFrameType: HLSMediaFrameType?
            var streamContext: HLSStreamContext?
            
            if packet.streamIndex == audioStreamIndex {
                currentFrameType = .audio
                streamContext = mediaSource.audioStreamContext
            } else if packet.streamIndex == videoStreamIndex {
                currentFrameType = .video
                streamContext = mediaSource.videoStreamContext
            } else {
                continue
            }
            
            guard let currentFrameType, let streamContext else { continue }
            
            let decodableFrame = createDecodableFrame(type: currentFrameType, packet: packet, streamContext: streamContext)
            guard let mediaFrame = decode(frame: decodableFrame) else { continue }
            
            if let lastSeekStatus {
                var isFramePositionValid = true
                switch lastSeekStatus.seekType {
                case .default:
                    let positionDifference = CMTimeSubtract(lastSeekStatus.pts, mediaFrame.position)
                    let absPositionDifference = CMTimeAbsoluteValue(positionDifference)
                    isFramePositionValid = absPositionDifference <= CMTime(value: 1, timescale: 1)
                case .streamSwitch:
                    if mediaFrame.type == .video, let lastDecodedVideoFramePts {
                        isFramePositionValid = mediaFrame.position.seconds >= lastDecodedVideoFramePts.seconds
                    } else if let lastDecodedAudioFramePts {
                        isFramePositionValid = mediaFrame.position.seconds >= lastDecodedAudioFramePts.seconds
                    }
                }
                
                switch mediaFrame.type {
                case .video:
                    if lastSeekStatus.videoState == .notSeeked {
                        guard isFramePositionValid else { continue }
                        self.lastSeekStatus?.videoState = .seeked
                        print("VIDEO \(mediaFrame.position.seconds) seek reached for \(mediaFrame.type)")
                    }
                case .audio:
                    if lastSeekStatus.audioState == .notSeeked {
                        guard isFramePositionValid else { continue }
                        self.lastSeekStatus?.audioState = .seeked
                        print("AUDIO \(mediaFrame.position.seconds) seek reached for \(mediaFrame.type)")
                    }
                }
                
                if lastSeekStatus.videoState == .seeked && lastSeekStatus.audioState == .seeked {
                    print("seek reached for didSeek")
                    self.lastSeekStatus = nil
                    didSeekEnd?(lastSeekStatus.seekType)
                }
            }
            
            updateLastFramePts(withFrame: mediaFrame)
            
            if mediaFrame.type == task.frameType {
                decodedFramesCount += 1
                decodedFrames.append(mediaFrame)
            } else {
                remainingDecodedFrames.append(mediaFrame)
            }
        }
        
        return (decodedFrames, remainingDecodedFrames)
    }
    
    private func readPacket() -> FFMpegPacket? {
        guard let formatContext else { return nil }
        let packet = FFMpegPacket()
        let result = formatContext.readFrameWithResult(into: packet)
        if result == 0 {
            return packet
        } else if result == FFMPEG_CONSTANT_AVERROR_EOF {
            if let lastDecodedVideoFramePts {
                didFoundEndOfFilePosition?(lastDecodedVideoFramePts)
            } else if let lastDecodedVideoFramePts {
                didFoundEndOfFilePosition?(lastDecodedVideoFramePts)
            }
        }
        return nil
    }
    
    private func decode(frame: HLSMediaDecodableFrame) -> HLSMediaFrame? {
        switch frame.type {
        case .video:
            return videoDecoder?.decode(frame: frame)
        case .audio:
            return audioDecoder?.decode(frame: frame)
        }
    }
    
    private func createDecodableFrame(
        type: HLSMediaFrameType,
        packet: FFMpegPacket,
        streamContext: HLSStreamContext
    ) -> HLSMediaDecodableFrame {
        let pts = CMTimeMake(value: packet.pts, timescale: streamContext.timebase.timescale)
        let dts = CMTimeMake(value: packet.dts, timescale: streamContext.timebase.timescale)
        
        let duration: CMTime
        
        let frameDuration = packet.duration
        if frameDuration != 0 {
            duration = CMTimeMake(value: frameDuration * streamContext.timebase.value, timescale: streamContext.timebase.timescale)
        } else {
            duration = CMTimeMake(value: Int64(streamContext.fps.timescale), timescale: Int32(streamContext.fps.value))
        }
        
        return HLSMediaDecodableFrame(type: type, packet: packet, pts: pts, dts: dts, duration: duration)
    }
    
    private func updateLastFramePts(withFrame frame: HLSMediaFrame) {
        if frame.type == .video {
            lastDecodedVideoFramePts = frame.position
        } else {
            lastDecodedAudioFramePts = frame.position
        }
    }
    
    public func switchStream(newMediaSource: HLSMediaSource) {
        self.mediaSource = newMediaSource
        
        let videoStreamContext = mediaSource?.videoStreamContext
        let audioStreamContext = mediaSource?.audioStreamContext
        
        if let videoCodecContext = videoStreamContext?.codecContext {
            if !isSimulatorEnvironment {
                videoCodecContext.enableHardwareAcceleration()
            }
            videoDecoder?.setup(codecContext: videoCodecContext)
        }
        
        if let audioCodecContext = audioStreamContext?.codecContext {
            audioDecoder?.setup(codecContext: audioCodecContext)
        }
        
        if let lastDecodedAudioFramePts, let audioStreamContext {
            seekTo(pts: lastDecodedAudioFramePts, inStream: audioStreamContext, seekType: .streamSwitch)
        } else if let lastDecodedVideoFramePts, let videoStreamContext {
            seekTo(pts: lastDecodedVideoFramePts, inStream: videoStreamContext, seekType: .streamSwitch)
        }
    }
    
    public func seekTo(timestamp: Double, seekType: HLSSeekType = .default) {
        guard let mediaSource else { return }
        if let videoStreamContext = mediaSource.videoStreamContext {
            seekTo(timestamp: timestamp, inStream: videoStreamContext, seekType: seekType)
            didSeekStart?(seekType)
        } else if let audioStreamContext = mediaSource.audioStreamContext {
            seekTo(timestamp: timestamp, inStream: audioStreamContext, seekType: seekType)
            didSeekStart?(seekType)
        }
    }
    
    public func seekTo(timestamp: Double, inStream streamContext: HLSStreamContext, seekType: HLSSeekType) {
        let timebase = streamContext.timebase
        let startTimeCorrection = streamContext.startTime.seconds
        let correctedTimestamp = timestamp + startTimeCorrection
        let pts = CMTimeMakeWithSeconds(correctedTimestamp, preferredTimescale: timebase.timescale)
        seekTo(pts: pts, inStream: streamContext, seekType: seekType)
    }
    
    public func seekTo(pts: CMTime, inStream streamContext: HLSStreamContext, seekType: HLSSeekType) {
        lastSeekStatus = nil
        let streamIndex = streamContext.index
        formatContext?.seekFrame(forStreamIndex: streamIndex, pts: pts.value, positionOnKeyframe: true)
        lastSeekStatus = SeekStatus(seekType: seekType, pts: pts)
        streamContext.codecContext.flushBuffers()
    }
}
