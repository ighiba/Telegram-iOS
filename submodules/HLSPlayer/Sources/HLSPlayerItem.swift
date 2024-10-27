import Foundation

public final class HLSPlayerItem {
    public enum Status {
        case unknown
        case readyToPlay
        case failed(Error)
    }
    
    public var didChangeStatus: ((HLSPlayerItem.Status) -> Void)?
    public var didChangePresentationSize: ((CGSize) -> Void)?
    
    var didPrepareMediaSource: ((HLSMediaSource) -> Void)?
    var didSwitchSelectedStream: ((HLSStream) -> Void)?
    
    private(set) var status: HLSPlayerItem.Status = .unknown {
        didSet {
            didChangeStatus?(status)
        }
    }
    
    public var startsOnFirstEligibleVariant: Bool = true
    
    public var preferredPeakBitRate: Double = 0 {
        didSet {
            didSetPreferredPeakBitRate(preferredPeakBitRate)
        }
    }
    
    public var presentationSize: CGSize {
        streamManager.currentStreamPresentationSize()
    }
    
    private let streamManager: HLSStreamManager
    var mediaSource: HLSMediaSource?
    
    public let url: URL
    
    public init(url: URL) {
        self.url = url
        self.streamManager = HLSStreamManager()
        self.prepareMediaSourceForPlayback()
    }
    
    func downgradeStreamQuality() {
        if let downgradedStream = streamManager.streamWithDowngradedQuality() {
            print("Downgrade stream quality")
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
                    self.didPrepareMediaSource?(mediaSource)
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
                    self?.didChangePresentationSize?(optimalStream.presentationSize)
                }
            }
        } else {
            guard let optimalStream = streamManager.streamWithOptimalQuality(forBitrate: bitrate) else { return }
            streamManager.setCurrentStream(optimalStream)
            didSwitchSelectedStream?(optimalStream)
            didChangePresentationSize?(optimalStream.presentationSize)
        }
    }
}
