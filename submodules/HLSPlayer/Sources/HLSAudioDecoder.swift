import Foundation
import FFMpegBinding

final class HLSAudioDecoder: HLSDecoder {
    private var audioFrame: FFMpegAVFrame = FFMpegAVFrame()
    
    private var swResample: FFMpegSWResample?
    private var formatDescription: CMAudioFormatDescription?
    
    private var codecContext: FFMpegAVCodecContext
    
    init(codecContext: FFMpegAVCodecContext, destinationSampleRate: Int = 44100, destinationChannelCount: Int = 1) {
        self.codecContext = codecContext
        self.setup(codecContext: codecContext, destinationSampleRate: destinationSampleRate, destinationChannelCount: destinationChannelCount)
    }
    
    func setup(codecContext: FFMpegAVCodecContext, destinationSampleRate: Int = 44100, destinationChannelCount: Int = 1) {
        self.swResample = FFMpegSWResample(
            sourceChannelCount: Int(codecContext.channels()),
            sourceSampleRate: Int(codecContext.sampleRate()),
            sourceSampleFormat: codecContext.sampleFormat(),
            destinationChannelCount: destinationChannelCount,
            destinationSampleRate: destinationSampleRate,
            destinationSampleFormat: FFMPEG_AV_SAMPLE_FMT_S16
        )
        
        var audioStreamBasicDescription = AudioStreamBasicDescription(
            mSampleRate: Float64(destinationSampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(2 * destinationChannelCount),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(2 * destinationChannelCount),
            mChannelsPerFrame: UInt32(destinationChannelCount),
            mBitsPerChannel: 16,
            mReserved: 0
        )
        
        var channelLayout = AudioChannelLayout()
        memset(&channelLayout, 0, MemoryLayout<AudioChannelLayout>.size)
        channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
        
        var formatDescription: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: nil,
            asbd: &audioStreamBasicDescription,
            layoutSize: MemoryLayout<AudioChannelLayout>.size,
            layout: &channelLayout,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        
        self.formatDescription = formatDescription
    }
    
    func decode(frame: HLSMediaDecodableFrame) -> HLSMediaFrame? {
        let status = frame.packet.send(toDecoder: codecContext)
        guard status == 0 else {
            return nil
        }
        while true {
            let result = codecContext.receive(into: audioFrame)
            if case .success = result {
                if let convertedFrame = convertAudioFrame(audioFrame, pts: frame.pts) {
                    return convertedFrame
                }
            } else {
                break
            }
        }
        return nil
    }
    
    private func convertAudioFrame(_ frame: FFMpegAVFrame, pts: CMTime) -> HLSMediaFrame? {
        guard let swResample, let data = swResample.resample(frame) else {
            return nil
        }
        
        guard let bytes = malloc(data.count) else {
            return nil
        }
        
        var blockBuffer: CMBlockBuffer?
        data.copyBytes(to: bytes.assumingMemoryBound(to: UInt8.self), count: data.count)
        let status = CMBlockBufferCreateWithMemoryBlock(
            allocator: nil,
            memoryBlock: bytes,
            blockLength: data.count,
            blockAllocator: nil,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: data.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        
        guard status == noErr, let blockBuffer, let formatDescription else {
            return nil
        }
        
        var sampleBuffer: CMSampleBuffer?
        let resultStatus = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: Int(data.count / 2),
            presentationTimeStamp: pts,
            packetDescriptions: nil,
            sampleBufferOut: &sampleBuffer
        )
        
        guard resultStatus == noErr, let sampleBuffer else {
            return nil
        }
        
        return HLSMediaFrame(type: .audio, sampleBuffer: sampleBuffer)
    }
}
