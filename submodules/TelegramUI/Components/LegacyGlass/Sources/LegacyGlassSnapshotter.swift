import UIKit
import CoreGraphics
import Display

private let minRequestFrameSize = LegacyGlassRenderer.minRenderSize

protocol LegacyGlassSnapshotRequest: AnyObject {
    var requestId: UUID { get }

    func invalidate()
}

final class LegacyGlassSnapshotter {
    private final class RequestToken: LegacyGlassSnapshotRequest {
        weak var snapshotter: LegacyGlassSnapshotter?
        weak var hostView: UIView?
        weak var renderer: LegacyGlassRenderer?
        
        let requestId: UUID
        let creationTimestamp: CFTimeInterval
        var isActive: Bool = true
        
        init(snapshotter: LegacyGlassSnapshotter, hostView: UIView, renderer: LegacyGlassRenderer) {
            self.snapshotter = snapshotter
            self.hostView = hostView
            self.renderer = renderer
            self.requestId = UUID()
            self.creationTimestamp = CACurrentMediaTime()
            self.isActive = true
        }
        
        func invalidate() {
            guard let snapshotter = self.snapshotter else {
                return
            }
            snapshotter.removeRequest(self)
            self.snapshotter = nil
        }
        
        deinit {
            self.invalidate()
        }
    }
    
    public static let shared = LegacyGlassSnapshotter()
    
    private var displayLink: SharedDisplayLinkDriver.Link?
    
    private var requests: [RequestToken] = []
    private var requestFrames: [UUID: CGRect] = [:]
    
    private(set) var currentSnapshot: CGImage?
    private weak var captureHostView: UIView? {
        didSet {
            self.didUpdateCaptureHostView(oldHostView: oldValue)
        }
    }
    private var captureRegion: CGRect = .zero
    private var captureScale: CGFloat = 1.0
    private var captureFrameRate: Double = 60.0

    private var hasRecentHostViewChange: Bool = false

    private var hostViewChangeTimestamp: CFTimeInterval?
    private var lastCaptureTimestamp: CFTimeInterval?
    private var lastVisibilityCheckTimestamp: CFTimeInterval?

    private var orientationObserver: NSObjectProtocol?

    private let groupRendererFormat: UIGraphicsImageRendererFormat = makeRendererFormat()
    private let directRendererFormat: UIGraphicsImageRendererFormat = makeRendererFormat()
    
    private init() {
        self.displayLink = SharedDisplayLinkDriver.shared.add(framesPerSecond: .max) { [weak self] _ in
            self?.captureSnapshot()
        }
        self.displayLink?.isPaused = true
        
        self.orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateRequestsVisibility()
                self?.updateCaptureRegion()
            }
        }
    }
    
    deinit {
        self.displayLink?.invalidate()
        self.displayLink = nil
        if let orientationObserver = self.orientationObserver {
            NotificationCenter.default.removeObserver(orientationObserver)
        }
    }

    func requestSnapshot(hostView: UIView, renderer: LegacyGlassRenderer, allowsGroupSnapshotting: Bool) -> LegacyGlassSnapshotRequest? {
        guard allowsGroupSnapshotting else { return nil }
        
        let token = RequestToken(snapshotter: self, hostView: hostView, renderer: renderer)
        if allowsGroupSnapshotting {
            self.requests.append(token)
            self.updateCaptureHostView()
            self.updateMinCaptureFrameRate()
            self.updateCaptureScale()
            self.updateCaptureRegion()
            self.startSnapshottingIfNeeded()
        }
        
        return token
    }
    
    private func updateCaptureScale() {
        var minScale: CGFloat = UIScreen.main.scale
        
        for request in self.requests {
            if request.isActive && request.hostView != nil, let renderer = request.renderer {
                minScale = min(minScale, renderer.currentCaptureScale())
            }
        }

        self.captureScale = minScale
    }
    
    func updateMinCaptureFrameRate() {
        var frameRate: Double = 1.0
        var hasActiveRequests = false
        
        for request in self.requests {
            if request.isActive && request.hostView != nil, let renderer = request.renderer {
                frameRate = max(frameRate, renderer.currentUpdateFrequency().captureFrameRate)
                hasActiveRequests = true
            }
        }
        
        if !hasActiveRequests {
            frameRate = 60.0
        }

        self.captureFrameRate = frameRate
    }

    func captureSnapshotDirectly(rect: CGRect, hostView: UIView, scale: CGFloat, viewToExclude: UIView? = nil, useLayerBasedRender: Bool = false) -> CGImage? {
        guard rect.width > 0, rect.height > 0 else {
            return nil
        }
        
        self.directRendererFormat.scale = scale
        let imageRenderer = UIGraphicsImageRenderer(
            bounds: CGRect(origin: .zero, size: rect.size),
            format: self.directRendererFormat
        )

        return self.captureSnapshotImage(
            using: imageRenderer,
            hostView: hostView,
            rect: rect,
            viewToExclude: viewToExclude,
            useLayerBasedRender: useLayerBasedRender
        )
    }

    func getCroppedSnapshot(requestId: UUID) -> CGImage? {
        guard let snapshot = self.currentSnapshot else {
            return nil
        }
        
        guard let targetFrame = self.requestFrames[requestId] else {
            return nil
        }
        
        guard targetFrame.width > 0, targetFrame.height > 0 else {
            return nil
        }
        
        guard self.captureRegion.width > 0, self.captureRegion.height > 0 else {
            return nil
        }
        
        let scale = self.captureScale
        let pixelRect = CGRect(
            x: targetFrame.origin.x * scale,
            y: targetFrame.origin.y * scale,
            width: targetFrame.size.width * scale,
            height: targetFrame.size.height * scale
        )
        
        guard let croppedImage = snapshot.cropping(to: pixelRect) else {
            return nil
        }

        return croppedImage
    }
    
    private func startSnapshottingIfNeeded() {
        let hasActiveRequests = self.requests.contains { request in
            request.isActive && request.hostView != nil && request.renderer != nil
        }
        
        if hasActiveRequests && self.displayLink?.isPaused == true {
            self.displayLink?.isPaused = false
        } else if !hasActiveRequests && self.displayLink != nil {
            self.displayLink?.isPaused = true
            self.invalidateSnapshot()
        }
    }

    private func invalidateSnapshot() {
        self.currentSnapshot = nil
        self.captureRegion = .zero
        self.requestFrames.removeAll()
    }
    
    private func captureSnapshot() {
        guard let hostView = self.captureHostView else {
            return
        }
        
        let now = CACurrentMediaTime()
        let minInterval: CFTimeInterval = 1.0 / self.captureFrameRate
        if let last = self.lastCaptureTimestamp, (now - last) < minInterval {
            return
        }
        
        let visibilityCheckInterval: CFTimeInterval = 0.2
        if let lastCheck = self.lastVisibilityCheckTimestamp {
            if (now - lastCheck) >= visibilityCheckInterval {
                self.updateRequestsVisibility()
                self.lastVisibilityCheckTimestamp = now
            }
        } else {
            self.updateRequestsVisibility()
            self.lastVisibilityCheckTimestamp = now
        }
        
        guard self.isHostViewVisible(hostView) else {
            return
        }

        self.updateCaptureRegion()
        self.updateCaptureScale()
        
        guard self.captureRegion.width > 0, self.captureRegion.height > 0 else {
            return
        }
        
        self.lastCaptureTimestamp = now
        
        if self.hasRecentHostViewChange, let timestamp = self.hostViewChangeTimestamp {
            let timeSinceChange = now - timestamp
            if timeSinceChange > 1.0 {
                self.hasRecentHostViewChange = false
                for request in requests {
                    if let renderer = request.renderer {
                        renderer.setIsPaused(false)
                    }
                }
            }
        }

        self.groupRendererFormat.scale = self.captureScale
        let imageRenderer = UIGraphicsImageRenderer(
            bounds: CGRect(origin: .zero, size: self.captureRegion.size),
            format: self.groupRendererFormat
        )
        
        self.currentSnapshot = self.captureSnapshotImage(
            using: imageRenderer,
            hostView: hostView,
            rect: self.captureRegion,
            useLayerBasedRender: self.hasRecentHostViewChange
        )
    }

    private func captureSnapshotImage(
        using imageRenderer: UIGraphicsImageRenderer,
        hostView: UIView,
        rect: CGRect,
        viewToExclude: UIView? = nil,
        useLayerBasedRender: Bool = false
    ) -> CGImage? {
        return imageRenderer.image { context in
            let cgContext = context.cgContext
            cgContext.translateBy(x: -rect.minX, y: -rect.minY)
            
            if useLayerBasedRender {
                let wasHidden = viewToExclude?.isHidden ?? false
                viewToExclude?.isHidden = true
                hostView.layer.render(in: cgContext)
                viewToExclude?.isHidden = wasHidden
            } else {
                hostView.drawHierarchy(in: hostView.bounds, afterScreenUpdates: false)
            }
        }.cgImage
    }
    
    private func removeRequest(_ token: RequestToken) {
        self.requests.removeAll { $0 === token }
        self.requestFrames.removeValue(forKey: token.requestId)
        self.updateCaptureHostView()
        self.updateMinCaptureFrameRate()
        self.updateCaptureScale()
        self.updateCaptureRegion()
        self.startSnapshottingIfNeeded()
    }

    private func updateRequestsVisibility(ignoreAge: Bool = false) {
        let now = CACurrentMediaTime()
        let minRequestAge: CFTimeInterval = 0.5
        var needsUpdate = false
        
        for request in self.requests {
            if !ignoreAge && request.isActive {
                let requestAge = now - request.creationTimestamp
                if requestAge < minRequestAge {
                    continue
                }
            }

            guard request.renderer != nil else {
                if request.isActive {
                    request.isActive = false
                    needsUpdate = true
                }
                continue
            }

            guard let hostView = request.hostView, self.isHostViewVisible(hostView) else {
                if request.isActive {
                    request.isActive = false
                    needsUpdate = true
                }
                continue
            }

            let isVisible = request.renderer.map { self.isRendererVisible($0) } ?? false
            if isVisible && !request.isActive {
                request.isActive = true
                needsUpdate = true
            } else if !isVisible && request.isActive {
                request.isActive = false
                needsUpdate = true
            }
        }

        if needsUpdate {
            let oldHostView = self.captureHostView
            self.updateCaptureHostView()
            
            if oldHostView !== self.captureHostView {
                self.invalidateSnapshot()
            }
            
            self.updateMinCaptureFrameRate()
            self.updateCaptureScale()
            self.updateCaptureRegion()
            self.startSnapshottingIfNeeded()
        }
    }

    private func isRendererVisible(_ renderer: LegacyGlassRenderer) -> Bool {
        if renderer.isHidden {
            return false
        }

        guard renderer.window != nil else {
            return false
        }

        if renderer.bounds.width <= 0 || renderer.bounds.height <= 0 {
            return false
        }

        return true
    }

    private func isHostViewVisible(_ hostView: UIView) -> Bool {
        guard let window = hostView.window else {
            return false
        }
        
        if window.isHidden {
            return false
        }
        
        if !window.isKeyWindow {
            return false
        }

        if hostView.bounds.width <= 0 || hostView.bounds.height <= 0 {
            return false
        }
        
        return true
    }

    func forceVisibilityCheck() {
        self.updateRequestsVisibility(ignoreAge: true)
    }
    
    private func updateCaptureRegion() {
        guard let hostView = self.captureHostView else {
            self.captureRegion = .zero
            self.requestFrames.removeAll()
            return
        }
        
        var unionRect: CGRect?
        var updatedFrames: [UUID: CGRect] = [:]
        
        for request in self.requests {
            guard request.isActive else {
                continue
            }
            
            guard let renderer = request.renderer else {
                continue
            }
            
            let rendererBounds = renderer.bounds
            guard rendererBounds.width > 0, rendererBounds.height > 0 else {
                continue
            }
            
            let rendererFrameInHost = renderer.convert(rendererBounds, to: hostView)
            
            let frameInHost = rendererFrameInHost.intersection(hostView.bounds)
            guard frameInHost.width > minRequestFrameSize.width, frameInHost.height > minRequestFrameSize.height else {
                continue
            }

            if let existing = unionRect {
                unionRect = existing.union(frameInHost)
            } else {
                unionRect = frameInHost
            }
            
            updatedFrames[request.requestId] = frameInHost
        }
        
        let oldCaptureRegion = self.captureRegion
        
        if let captureRegion = unionRect {
            self.captureRegion = captureRegion
            
            if !oldCaptureRegion.equalTo(captureRegion) {
                let regionChanged = abs(oldCaptureRegion.origin.x - captureRegion.origin.x) > 1.0
                || abs(oldCaptureRegion.origin.y - captureRegion.origin.y) > 1.0
                || abs(oldCaptureRegion.width - captureRegion.width) > 1.0
                || abs(oldCaptureRegion.height - captureRegion.height) > 1.0
                
                if regionChanged {
                    self.currentSnapshot = nil
                }
            }

            for (id, frame) in updatedFrames {
                self.requestFrames[id] = CGRect(
                    x: frame.origin.x - captureRegion.origin.x,
                    y: frame.origin.y - captureRegion.origin.y,
                    width: frame.width,
                    height: frame.height
                )
            }
            
            let activeRequestIds = Set(self.requests.filter { $0.isActive }.map { $0.requestId })
            self.requestFrames = self.requestFrames.filter { activeRequestIds.contains($0.key) }
        } else {
            self.captureRegion = .zero
            let hasActiveRequests = self.requests.contains { $0.isActive }
            if !hasActiveRequests {
                self.requestFrames.removeAll()
                self.invalidateSnapshot()
            }
        }
    }
    
    private func updateCaptureHostView() {
        for request in self.requests.reversed() {
            if request.isActive, let hostView = request.hostView {
                self.setNewCaptureHostView(hostView)
                return
            }
        }
        
        for request in self.requests.reversed() {
            if let hostView = request.hostView {
                self.setNewCaptureHostView(hostView)
                return
            }
        }
        
        self.setNewCaptureHostView(nil)
    }
    
    private func setNewCaptureHostView(_ captureHostView: UIView?) {
        if captureHostView != nil, captureHostView !== self.captureHostView {
            self.hasRecentHostViewChange = true
            self.hostViewChangeTimestamp = CACurrentMediaTime()
        }
        self.captureHostView = captureHostView
    }

    private func didUpdateCaptureHostView(oldHostView: UIView?) {
        if let newHostView = self.captureHostView {
            for request in self.requests {
                if request.hostView === newHostView, self.isHostViewVisible(newHostView) {
                    request.isActive = true
                    request.renderer?.setIsPaused(false)
                } else {
                    request.isActive = false
                    request.renderer?.setIsPaused(true)
                }
            }
        } else {
            for request in self.requests {
                request.isActive = false
                request.renderer?.setIsPaused(true)
            }
        }
    }
    
}

private func makeRendererFormat() -> UIGraphicsImageRendererFormat {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1.0
    format.opaque = false
    format.preferredRange = .standard
    return format
}
