import Foundation
import CoreMedia
import FFMpegBinding

public class HLSStreamContext {
    public let index: Int32
    public let fps: CMTime
    public let timebase: CMTime
    public let duration: CMTime
    public let startTime: CMTime
    public let codecContext: FFMpegAVCodecContext
    
    public required init(index: Int32, fps: CMTime, timebase: CMTime, duration: CMTime, startTime: CMTime, codecContext: FFMpegAVCodecContext) {
        self.index = index
        self.fps = fps
        self.timebase = timebase
        self.duration = duration
        self.startTime = startTime
        self.codecContext = codecContext
    }
}

public final class HLSAudioStreamContext: HLSStreamContext {
    public let sampleRate: Int
    public let channelCount: Int
    
    public init(
        index: Int32,
        fps: CMTime,
        timebase: CMTime,
        duration: CMTime,
        startTime: CMTime,
        codecContext: FFMpegAVCodecContext,
        sampleRate: Int = 44100,
        channelCount: Int = 1
    ) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        super.init(index: index, fps: fps, timebase: timebase, duration: duration, startTime: startTime, codecContext: codecContext)
    }
    
    public required init(index: Int32, fps: CMTime, timebase: CMTime, duration: CMTime, startTime: CMTime, codecContext: FFMpegAVCodecContext) {
        self.sampleRate = 44100
        self.channelCount = 1
        super.init(index: index, fps: fps, timebase: timebase, duration: duration, startTime: startTime, codecContext: codecContext)
    }
    
    deinit {
        print("\(Self.self) deinit")
    }
}

public final class HLSVideoStreamContext: HLSStreamContext {
    public required init(index: Int32, fps: CMTime, timebase: CMTime, duration: CMTime, startTime: CMTime, codecContext: FFMpegAVCodecContext) {
        super.init(index: index, fps: fps, timebase: timebase, duration: duration, startTime: startTime, codecContext: codecContext)
    }
    
    deinit {
        print("\(Self.self) deinit")
    }
}
