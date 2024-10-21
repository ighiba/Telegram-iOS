import Foundation

public final class HLSPlayerItem {
    public enum Status {
        case unknown
        case readyToPlay
        case failed(Error)
    }
    
    var didPreparedMediaSource: ((HLSMediaSource) -> Void)?
    var didSwitchSelectedStream: ((HLSStream) -> Void)?
    
    private(set) var status: HLSPlayerItem.Status = .unknown {
        didSet {
            NotificationCenter.default.post(name: HLSPlayerItem.statusDidChangeNotification, object: self, userInfo: ["newStatus": status])
        }
    }
    
    public var preferredPeakBitRate: Double = 0 {
        didSet {
            didSetPreferredPeakBitRate(preferredPeakBitRate)
        }
    }
    
    public let url: URL
    
    private let streamManager: HLSStreamManager
    var mediaSource: HLSMediaSource?
    
    init(url: URL) {
        self.url = url
        self.streamManager = HLSStreamManager()
        self.prepareMediaSourceForPlayback()
    }
    
    func downgradeStreamQuality() {
        if let downgradedStream = streamManager.streamWithDowngradedQuality() {
            print("DOWNGRADE STREAM")
            streamManager.setCurrentStream(downgradedStream)
            didSwitchSelectedStream?(downgradedStream)
        }
    }
    
    private func prepareMediaSourceForPlayback() {
        streamManager.fetchMediaSource(masterPlaylistUrl: url, initOnQueue: .global()) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let mediaSource):
                    self.mediaSource = mediaSource
                    self.status = .readyToPlay
                    self.didPreparedMediaSource?(mediaSource)
                case .failure(let error):
                    self.status = .failed(error)
                }
            }
        }
    }
    
    private func didSetPreferredPeakBitRate(_ bitrate: Double) {
        if bitrate == 0 {
            streamManager.streamWithOptimalAutoQuality { [weak self] optimalStream in
                guard let optimalStream else { return }
                DispatchQueue.main.async {
                    self?.streamManager.setCurrentStream(optimalStream)
                    self?.didSwitchSelectedStream?(optimalStream)
                }
            }
        } else {
            guard let optimalStream = streamManager.streamWithOptimalQuality(forBitrate: bitrate) else { return }
            streamManager.setCurrentStream(optimalStream)
            didSwitchSelectedStream?(optimalStream)
        }
    }
}

extension HLSPlayerItem {
    public static let statusDidChangeNotification = NSNotification.Name("statusDidChangeNotification")
}
