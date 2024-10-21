import Foundation
import FFMpegBinding

public enum HLSMediaFrameType {
    case video
    case audio
}

public final class HLSMediaDecodableFrame {
    public let type: HLSMediaFrameType
    public let packet: FFMpegPacket
    public let pts: CMTime
    public let dts: CMTime
    public let duration: CMTime
    
    public init(type: HLSMediaFrameType, packet: FFMpegPacket, pts: CMTime, dts: CMTime, duration: CMTime) {
        self.type = type
        self.pts = pts
        self.dts = dts
        self.duration = duration
        self.packet = packet
    }
}

public final class HLSMediaFrame {
    public let type: HLSMediaFrameType
    public let sampleBuffer: CMSampleBuffer
    
    public init(type: HLSMediaFrameType, sampleBuffer: CMSampleBuffer) {
        self.type = type
        self.sampleBuffer = sampleBuffer
    }
    
    public var position: CMTime {
        return CMSampleBufferGetPresentationTimeStamp(self.sampleBuffer)
    }
    
    public var duration: CMTime {
        return CMSampleBufferGetDuration(self.sampleBuffer)
    }
}
