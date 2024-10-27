import Foundation
import VideoToolbox
import FFMpegBinding

private let bufferCount = 32

final class HLSVideoDecoder: HLSDecoder {
    private var videoFrame: FFMpegAVFrame = FFMpegAVFrame()
    private var uvPlane: (UnsafeMutablePointer<UInt8>, Int)?
    
    private var codecContext: FFMpegAVCodecContext
    
    init(codecContext: FFMpegAVCodecContext) {
        self.codecContext = codecContext
    }
    
    func setup(codecContext: FFMpegAVCodecContext) {
        self.codecContext = codecContext
    }
    
    func decode(frame: HLSMediaDecodableFrame) -> HLSMediaFrame? {
        let status = frame.packet.send(toDecoder: codecContext)
        guard status >= 0 else {
            return nil
        }
        
        let result = codecContext.receive(into: videoFrame)
        guard result == .success else {
            print("Error receive video frame \(result)")
            return nil
        }
        
        let pts = CMTimeMake(value: videoFrame.pts, timescale: frame.pts.timescale)
        let dts = frame.dts
        let duration = frame.duration
        
        guard let sampleBuffer = createSampleBuffer(from: videoFrame, pts: pts, dts: dts, duration: duration) else { return nil }
        
        return HLSMediaFrame(type: .video, sampleBuffer: sampleBuffer)
    }
    
    private func createSampleBuffer(from frame: FFMpegAVFrame, pts: CMTime, dts: CMTime, duration: CMTime) -> CMSampleBuffer? {
        if frame.pixelFormat == .VIDEOTOOLBOX {
            return createSampleBuffer(videoToolboxFrame: frame, pts: pts, dts: dts, duration: duration)
        } else {
            return createSampleBuffer(yuvFrame: frame, pts: pts, dts: dts, duration: duration)
        }
    }
    
    private func createSampleBuffer(videoToolboxFrame frame: FFMpegAVFrame, pts: CMTime, dts: CMTime, duration: CMTime) -> CMSampleBuffer? {
        guard frame.pixelFormat == .VIDEOTOOLBOX, frame.data[3] != nil else {
            print("Frame is not in AV_PIX_FMT_VIDEOTOOLBOX format")
            return nil
        }
        
        let pixelBuffer = unsafeBitCast(frame.data[3], to: CVPixelBuffer.self)
        
        return createSampleBuffer(fromPixelBuffer: pixelBuffer, pts: pts, dts: dts, duration: duration)
    }
    
    private func createSampleBuffer(yuvFrame frame: FFMpegAVFrame, pts: CMTime, dts: CMTime, duration: CMTime) -> CMSampleBuffer? {
        guard frame.lineSize[1] == frame.lineSize[2] else {
            print("Frame is not in YUV software decoded format")
            return nil
        }
        
        let pixelFormat: OSType
        switch frame.pixelFormat {
            case .YUV:
                pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            case .YUVA:
                pixelFormat = kCVPixelFormatType_420YpCbCr8VideoRange_8A_TriPlanar
            default:
                pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        }
        
        let ioSurfaceProperties = NSMutableDictionary()
        ioSurfaceProperties["IOSurfaceIsGlobal"] = true as NSNumber
        
        var options: [String: Any] = [kCVPixelBufferBytesPerRowAlignmentKey as String: frame.lineSize[0] as NSNumber]
        options[kCVPixelBufferIOSurfacePropertiesKey as String] = ioSurfaceProperties

        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(frame.width),
            Int(frame.height),
            pixelFormat,
            options as CFDictionary,
            &pixelBuffer
        )
        
        guard let pixelBuffer else {
            return nil
        }

        let status = CVPixelBufferLockBaseAddress(pixelBuffer, [])
        guard status == kCVReturnSuccess else {
            return nil
        }

        var base: UnsafeMutableRawPointer
        let srcPlaneSize = Int(frame.lineSize[1]) * Int(frame.height / 2)
        let uvPlaneSize = srcPlaneSize * 2

        let uvPlane: UnsafeMutablePointer<UInt8>
        if let (existingUvPlane, existingUvPlaneSize) = self.uvPlane, existingUvPlaneSize == uvPlaneSize {
            uvPlane = existingUvPlane
        } else {
            if let (existingDstPlane, _) = self.uvPlane {
                free(existingDstPlane)
            }
            uvPlane = malloc(uvPlaneSize)!.assumingMemoryBound(to: UInt8.self)
            self.uvPlane = (uvPlane, uvPlaneSize)
        }
                
        fillDstPlane(uvPlane, frame.data[1]!, frame.data[2]!, srcPlaneSize)

        let bytesPerRowY = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let bytesPerRowUV = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
        
        base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)!
        if bytesPerRowY == frame.lineSize[0] {
            memcpy(base, frame.data[0]!, bytesPerRowY * Int(frame.height))
        } else {
            var dest = base
            var src = frame.data[0]!
            let lineSize = Int(frame.lineSize[0])
            for _ in 0 ..< Int(frame.height) {
                memcpy(dest, src, lineSize)
                dest = dest.advanced(by: bytesPerRowY)
                src = src.advanced(by: lineSize)
            }
        }

        base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)!
        if bytesPerRowUV == frame.lineSize[1] * 2 {
            memcpy(base, uvPlane, Int(frame.height / 2) * bytesPerRowUV)
        } else {
            var dest = base
            var src = uvPlane
            let lineSize = Int(frame.lineSize[1]) * 2
            for _ in 0 ..< Int(frame.height / 2) {
                memcpy(dest, src, lineSize)
                dest = dest.advanced(by: bytesPerRowUV)
                src = src.advanced(by: lineSize)
            }
        }
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        
        return createSampleBuffer(fromPixelBuffer: pixelBuffer, pts: pts, dts: dts, duration: duration)
    }
    
    private func createSampleBuffer(fromPixelBuffer pixelBuffer: CVPixelBuffer, pts: CMTime, dts: CMTime, duration: CMTime) -> CMSampleBuffer? {
        var videoInfo: CMVideoFormatDescription?
        let descriptionStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: nil,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &videoInfo
        )
        
        guard descriptionStatus == noErr, let videoInfo else { return nil }
        
        var timingInfo = CMSampleTimingInfo(duration: duration, presentationTimeStamp: pts, decodeTimeStamp: dts)
        
        var sampleBuffer: CMSampleBuffer?
        let result = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: videoInfo,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )

        guard descriptionStatus == noErr else {
            print("Error creating CMSampleBuffer: \(result)")
            return nil
        }

        return sampleBuffer
    }
}
