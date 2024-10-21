import Foundation
import FFMpegBinding

public final class HLSMediaSource {
    enum Error: Swift.Error {
        case cantOpenInput
        case cantFindStreamInfo
        case unknown
    }
    
    public var url: URL
    public var formatContext: FFMpegAVFormatContext?
    public var videoStreamContext: HLSVideoStreamContext?
    public var audioStreamContext: HLSAudioStreamContext?
    
    public init?(url: URL) {
        self.url = url
        try? openMediaSource(url: url)
    }
    
    public func switchStream(url: URL) {
        try? openMediaSource(url: url)
        print("SWITCHED")
    }
    
    private func openMediaSource(url: URL) throws {
        let formatContext = FFMpegAVFormatContext()
        guard formatContext.openInput(url.absoluteString) else {
            throw HLSMediaSource.Error.cantOpenInput
        }
        guard formatContext.findStreamInfo() else {
            throw HLSMediaSource.Error.cantFindStreamInfo
        }
        
        self.url = url
        self.formatContext = formatContext
        self.videoStreamContext = self.createStreamContext(for: FFMpegAVFormatStreamTypeVideo, formatContext: formatContext)
        self.audioStreamContext = self.createStreamContext(for: FFMpegAVFormatStreamTypeAudio, formatContext: formatContext)
    }
    
    public func getMediaDuration() -> CMTime? {
        if let audioDuration = audioStreamContext?.duration, isValidDuration(audioDuration) {
            return audioDuration
        } else if let videoDuration = videoStreamContext?.duration, isValidDuration(videoDuration) {
            return videoDuration
        }
        return nil
    }
    
    private func createStreamContext<T: HLSStreamContext>(for streamType: FFMpegAVFormatStreamType, formatContext: FFMpegAVFormatContext) -> T? {
        for streamIndexNumber in formatContext.streamIndices(for: streamType) {
            let streamIndex = streamIndexNumber.int32Value
            if formatContext.isAttachedPic(atStreamIndex: streamIndex) {
                continue
            }
            
            let codecId = formatContext.codecId(atStreamIndex: streamIndex)
            
            let fpsAndTimebase = formatContext.fpsAndTimebase(forStreamIndex: streamIndex, defaultTimeBase: CMTimeMake(value: 1, timescale: 40000))
            let (fps, timebase) = (fpsAndTimebase.fps, fpsAndTimebase.timebase)
            let duration = CMTimeMake(value: formatContext.duration(atStreamIndex: streamIndex), timescale: timebase.timescale)
            let startTime = CMTimeMake(value: formatContext.startTime(atStreamIndex: streamIndex), timescale: timebase.timescale)
            
            guard let codec = FFMpegAVCodec.find(forId: codecId) else { continue }
            
            let codecContext = FFMpegAVCodecContext(codec: codec)
            if formatContext.codecParams(atStreamIndex: streamIndex, to: codecContext), codecContext.open() {
                
                return T(
                    index: streamIndex,
                    fps: fps, timebase: timebase,
                    duration: duration,
                    startTime: startTime,
                    codecContext: codecContext
                )
            }
        }
        
        return nil
    }
    
    private func isValidDuration(_ duration: CMTime) -> Bool {
        return duration.seconds > 0
    }
}
