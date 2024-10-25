import Foundation
import UIKit

struct HLSStream: Equatable {
    struct Resolution: Equatable {
        let width: Int
        let height: Int
    }
    
    var bandwidth: Int
    var resolution: Resolution
    var presentationSize: CGSize { CGSize(width: resolution.width, height: resolution.width) }
    var url: URL
}

private extension HLSStream.Resolution {
    static let fullHd1080p = HLSStream.Resolution(width: 1920, height: 1080)
    static let hd720p = HLSStream.Resolution(width: 1280, height: 720)
    static let sd480p = HLSStream.Resolution(width: 852, height: 480)
    static var screen: HLSStream.Resolution {
        HLSStream.Resolution(width: Int(UIScreen.main.nativeBounds.width), height: Int(UIScreen.main.nativeBounds.height))
    }
}

final class HLSStreamManager {
    enum Error: Swift.Error {
        case masterPlaylistDownloadFailed
        case masterPlaylistInvalid
        case mediaSourceOpenFailed
        case noStreamsAvailable
        case unknown
    }
    
    enum NetworkCondition {
        case good
        case moderate
        case poor
        case unknown
    }
    
    private let m3u8Parser = M3U8Parser()
    
    private var availableStreams: [HLSStream] = []
    
    private var currentStream: HLSStream?
    private var currentMediaSource: HLSMediaSource?
    
    deinit {
        print("\(Self.self) deinit")
    }
    
    func fetchMediaSource(masterPlaylistUrl: URL, initOnQueue queue: DispatchQueue, completion: @escaping (Result<HLSMediaSource, HLSStreamManager.Error>) -> Void) {
        URLSession.shared.dataTask(with: createRequestGET(url: masterPlaylistUrl)) { [weak self] data, response, error in
            if let error {
                print("Error downloading master playlist: \(error.localizedDescription)")
                completion(.failure(.masterPlaylistDownloadFailed))
                return
            }
            
            guard let data, let playlistStr = String(data: data, encoding: .utf8) else {
                print("Invalid master playlist. Failed to convert data to string.")
                completion(.failure(.masterPlaylistInvalid))
                return
            }
            
            guard let self else {
                completion(.failure(.unknown))
                return
            }
            
            let streams = self.m3u8Parser.parseMasterPlaylist(playlistStr, url: masterPlaylistUrl)
            self.availableStreams = streams
            
            self.streamWithOptimalAutoQuality { optimalStream in
                guard let optimalStream else {
                    completion(.failure(.noStreamsAvailable))
                    return
                }
                self.setCurrentStream(optimalStream)
                
                queue.async {
                    if let mediaSource = HLSMediaSource(url: optimalStream.url) {
                        self.currentMediaSource = mediaSource
                        completion(.success(mediaSource))
                    } else {
                        completion(.failure(.mediaSourceOpenFailed))
                    }
                }
            }
        }.resume()
    }
    
    func setCurrentStream(_ stream: HLSStream) {
        currentStream = stream
    }
    
    func streamWithDowngradedQuality() -> HLSStream? {
        let sortedStreams = availableStreams.sorted { $0.bandwidth > $1.bandwidth }
        guard let currentStream, currentStream != sortedStreams.last else { return nil }
        guard let currentStreamIndex = sortedStreams.firstIndex(of: currentStream), currentStreamIndex < sortedStreams.count - 1 else { return nil }
        return sortedStreams[currentStreamIndex + 1]
    }
    
    func streamWithOptimalResolution(screenResolution: HLSStream.Resolution) -> HLSStream? {
        var closestDifference = Int.max
        var optimalStream: HLSStream?

        for stream in availableStreams {
            let resolutionDifference = abs(stream.resolution.width * stream.resolution.height - screenResolution.width * screenResolution.height)
            if resolutionDifference < closestDifference {
                closestDifference = resolutionDifference
                optimalStream = stream
            }
        }
        
        return optimalStream
    }
    
    func streamWithOptimalQuality(forBitrate bitrate: Double) -> HLSStream? {
        let sortedStreams = availableStreams.sorted { $0.bandwidth < $1.bandwidth }
        var closestDifference = Int.max
        var optimalStream: HLSStream?
        
        for stream in sortedStreams {
            let difference = abs(stream.bandwidth - Int(bitrate))
            if difference < closestDifference {
                closestDifference = difference
                optimalStream = stream
            }
        }
        
        return optimalStream
    }
    
    func streamWithOptimalAutoQuality(completion: @escaping (HLSStream?) -> Void) {
        let streams = availableStreams
        testNetworkCondition { networkCondition in
            guard let optimalStream = self.streamWithOptimalQuality(for: networkCondition, screenResolution: .screen, in: streams) else {
                completion(nil)
                return
            }
            completion(optimalStream)
        }
    }
    
    func currentStreamPresentationSize() -> CGSize {
        guard let currentStream else { return .zero }
        return CGSize(width: currentStream.resolution.width, height: currentStream.resolution.height)
    }
    
    private func streamWithOptimalQuality(
        for networkCondition: HLSStreamManager.NetworkCondition,
        screenResolution: HLSStream.Resolution,
        in streams: [HLSStream]
    ) -> HLSStream? {
        guard !streams.isEmpty else { return nil }
        
        let sortedStreams = streams.sorted { $0.bandwidth < $1.bandwidth }
        let filteredStreams = sortedStreams.filter { stream in
            stream.resolution.width <= screenResolution.height &&
            stream.resolution.height <= screenResolution.width
        }
        
        let availableStreams = filteredStreams.isEmpty ? sortedStreams : filteredStreams
        
        var selectedStream: HLSStream?
        switch networkCondition {
        case .good:
            selectedStream = streamWithOptimalResolution(screenResolution: screenResolution)
        case .moderate:
            selectedStream = availableStreams.first { $0.resolution.height >= 720 } ?? availableStreams[availableStreams.count / 2]
        case .poor, .unknown:
            selectedStream = availableStreams.first
        }
        
        return selectedStream
    }
    
    private func testNetworkCondition(completion: @escaping (NetworkCondition) -> Void) {
        let testUrls = [
            URL(string: "https://telegram.org")!,
            URL(string: "https://google.com")!,
            URL(string: "https://apple.com")!
        ]
        
        var latencies: [TimeInterval] = []
        let group = DispatchGroup()
        
        for testUrl in testUrls {
            group.enter()
            let startTime = Date()
            
            URLSession.shared.dataTask(with: testUrl) { data, response, error in
                let latency = Date().timeIntervalSince(startTime) * 1000
                if error == nil && data != nil {
                    latencies.append(latency)
                }
                group.leave()
            }.resume()
        }
        
        group.notify(queue: .global()) {
            guard !latencies.isEmpty else {
                completion(.unknown)
                return
            }
            
            let averageLatency = latencies.reduce(0, +) / Double(latencies.count)
            let networkCondition = self.networkCondition(forLatency: averageLatency)
            print(averageLatency)
            completion(networkCondition)
        }
    }
    
    private func networkCondition(forLatency latency: TimeInterval) -> HLSStreamManager.NetworkCondition {
        switch latency {
        case 0...500:
            return .good
        case 500...1500:
            return .moderate
        case 1500...:
            return .poor
        default:
            return .unknown
        }
    }
    
    private func createRequestGET(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return request
    }
}

final class M3U8Parser {
    func parseMasterPlaylist(_ playlist: String, url: URL) -> [HLSStream] {
        var streams = [HLSStream]()
        var bandwidth = 0
        var resolution = HLSStream.Resolution(width: 0, height: 0)
        
        let lines = playlist.components(separatedBy: "\n")
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard !trimmedLine.isEmpty else { continue }
            
            if trimmedLine.hasPrefix("#EXT-X-STREAM-INF:") {
                if let bandwidthRange = trimmedLine.range(of: "BANDWIDTH="),
                   let resolutionRange = trimmedLine.range(of: "RESOLUTION=") {
                    
                    let bandwidthStr = trimmedLine[bandwidthRange.upperBound...]
                        .components(separatedBy: ",")[0]
                    bandwidth = Int(bandwidthStr) ?? 0
                    
                    let resolutionArr = trimmedLine[resolutionRange.upperBound...]
                        .components(separatedBy: ",")[0]
                        .components(separatedBy: "x")
                        .map { Int($0) ?? 0 }
                    guard resolutionArr.count == 2 else { continue }
                    resolution = .init(width: resolutionArr[0], height: resolutionArr[1])
                }
            } else if !trimmedLine.hasPrefix("#"), let playlistUrl = createAbsoluteUrl(from: url, with: trimmedLine) {
                let stream = HLSStream(bandwidth: bandwidth, resolution: resolution, url: playlistUrl)
                streams.append(stream)
            }
        }
        
        return streams
    }
    
    private func createAbsoluteUrl(from url: URL, with relativePath: String) -> URL? {
        if relativePath.hasPrefix("http://") || relativePath.hasPrefix("https://") {
            return URL(string: relativePath)
        } else {
            let baseUrlStr = url.deletingLastPathComponent().absoluteString
            let absoluteUrlStr = baseUrlStr + relativePath
            return URL(string: absoluteUrlStr)
        }
    }
}

private let testMasterPlaylist = """
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=2074088,RESOLUTION=1920x1080
hls_level_1080.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=1015040,RESOLUTION=1280x720
hls_level_720.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=527200,RESOLUTION=852x480
hls_level_480.m3u8
"""
