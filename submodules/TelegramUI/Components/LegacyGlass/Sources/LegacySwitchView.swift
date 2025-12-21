import UIKit
import Display

private let verticalPadding: CGFloat = 15.0
private let horizontalPadding: CGFloat = 15.0

public final class LegacySwitchView: UIControl {

    public override var intrinsicContentSize: CGSize {
        return CGSize(width: 63.0, height: 28.0)
    }

    public private(set) var isOn: Bool = false {
        didSet {
            guard self.isOn != oldValue else { return }
            self.sendActions(for: .valueChanged)
        }
    }
    private var isDragging: Bool = false
    private var isThumbMoved: Bool = false
    private var isTrackFadeDrivenByThumb: Bool = false
    
    private let thumbSize = CGSize(width: 37.0, height: 24.0)
    private let thumbInset: CGFloat = 2.0
    private let dragMovementThreshold: CGFloat = 5.0
    private var dragStartThumbOriginX: CGFloat = 0.0
    private var dragStartLocationX: CGFloat = 0.0
    
    private var thumbAnimationLink: SharedDisplayLinkDriver.Link?
    private var thumbAnimationDurationSetting: CFTimeInterval = 0.5
    private var thumbAnimationStartTime: CFTimeInterval = 0.0
    private var thumbAnimationDuration: CFTimeInterval = 0.0
    private var thumbAnimationStartX: CGFloat = 0.0
    private var thumbAnimationEndX: CGFloat = 0.0
    
    private var trackFadeLink: SharedDisplayLinkDriver.Link?
    private var trackFadeStartTime: CFTimeInterval = 0.0
    private var trackFadeDuration: CFTimeInterval = 0.0
    private var trackFadeStartAlpha: CGFloat = 0.0
    private var trackFadeEndAlpha: CGFloat = 0.0
    
    public override var backgroundColor: UIColor? {
        get { self.captureContainerView.backgroundColor }
        set { self.captureContainerView.backgroundColor = newValue }
    }
    public var thumbTintColor: UIColor = .white {
        didSet { self.updateTrackAppearance(animated: true) }
    }
    public var onTintColor: UIColor = .systemGreen {
        didSet { self.updateTrackAppearance(animated: true) }
    }
    public var offTintColor: UIColor = .tertiaryLabel {
        didSet { self.updateTrackAppearance(animated: true) }
    }
    public override var tintColor: UIColor! {
        didSet { self.updateTrackAppearance(animated: false) }
    }

    private var panGestureRecognizer: UIPanGestureRecognizer?
    
    private let captureContainerView = UIView()
    private let containerView = UIView()
    private let backView = UIView()
    private let trackView = UIView()
    public let thumbView: LegacyGlassKnobView
    
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    
    public override init(frame: CGRect) {
        let style = LegacyGlassStyle(
            refractionStrength: -0.32,
            refractionEdgeWidth: 0.95,
            refractionCenterStrength: -1.67,
            refractionEdgeStrength: 2.9,
            refractionXScale: 1.0,
            refractionYScale: 0.9,
            dimmingStrength: 0.65,
            rimHighlightWidth: 1.0,
            rimHighlightStrength: 0.5,
            chromaticAberrationStrength: 0.37,
            coreRadius: 0.33,
            idleOuterShadowWidth: 0.0,
            idleOuterShadowOpacity: 0.0,
            activeOuterShadowWidth: 0.2,
            activeOuterShadowOpacity: 0.1,
            isBlurEnabled: false
        )
        self.thumbView = LegacyGlassKnobView(style: style, qualityProfile: .automatic, size: self.thumbSize)
        
        super.init(frame: frame)

        self.backgroundColor = .white
        self.backView.backgroundColor = self.offTintColor
        self.trackView.backgroundColor = self.onTintColor
        
        self.containerView.layer.masksToBounds = true

        self.captureContainerView.isUserInteractionEnabled = false
        self.containerView.isUserInteractionEnabled = false
        self.backView.isUserInteractionEnabled = false
        self.trackView.isUserInteractionEnabled = false

        self.thumbView.isUserInteractionEnabled = false
        self.thumbView.legacyGlassView.fillColor = .white
        self.thumbView.legacyGlassView.isActivationEnabled = true
        self.thumbView.legacyGlassView.isScalingEnabled = true
        self.thumbView.legacyGlassView.isJellyEnabled = true
        self.thumbView.legacyGlassView.interactionJellyDirection = .horizontal
        self.thumbView.legacyGlassView.cornerRadius = self.thumbSize.height * 0.5
        self.thumbView.legacyGlassView.interactionScaleMax = 1.54
        self.thumbView.legacyGlassView.verticalPadding = verticalPadding
        self.thumbView.legacyGlassView.horizontalPadding = horizontalPadding
        self.thumbView.legacyGlassView.setCaptureHostView(self.captureContainerView)
        
        self.containerView.addSubview(self.backView)
        self.containerView.addSubview(self.trackView)
        self.captureContainerView.addSubview(self.containerView)
        self.addSubview(self.captureContainerView)
        self.addSubview(self.thumbView)

        self.updateTrackAppearance(animated: false)
        
        self.isExclusiveTouch = true
        
        let panGesture = ImmediatePanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delaysTouchesBegan = false
        panGesture.cancelsTouchesInView = true
        panGesture.maximumNumberOfTouches = 1
        self.addGestureRecognizer(panGesture)
        self.panGestureRecognizer = panGesture
       
    }

    required init?(coder: NSCoder) {
        return nil
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        self.captureContainerView.frame = self.bounds.insetBy(dx: -horizontalPadding, dy: -verticalPadding)
        self.containerView.frame = self.captureContainerView.bounds.insetBy(dx: horizontalPadding, dy: verticalPadding)
        self.backView.frame = self.containerView.bounds
        self.trackView.frame = self.containerView.bounds
        self.containerView.layer.cornerRadius = self.bounds.height * 0.5
        self.updateThumbLayout(animated: false)
    }
    
    public override func sizeToFit() {
        self.bounds.size = self.intrinsicContentSize
        self.setNeedsLayout()
    }
    
    private func updateThumbLayout(animated: Bool) {
        let targetFrame = self.calculateThumbFrame()
        if animated {
            self.syncGlassDurationsToThumb()
            self.startThumbAnimation(to: targetFrame, duration: self.thumbAnimationDurationSetting)
        } else {
            self.thumbView.frame = targetFrame
        }
    }
    
    private func calculateThumbFrame() -> CGRect {
        let thumbOriginX: CGFloat
        if self.isOn {
            thumbOriginX = self.bounds.width - self.thumbInset - self.thumbSize.width
        } else {
            thumbOriginX = self.thumbInset
        }
        return CGRect(origin: CGPoint(x: thumbOriginX, y: self.thumbInset), size: self.thumbSize)
    }
    
    public override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard self.isEnabled else { return false }

        self.resetDragState()
        self.isDragging = true
        self.syncGlassDurationsToThumb()
        self.feedbackGenerator.prepare()
        
        let location = touch.location(in: self)
        self.dragStartLocationX = location.x
        self.dragStartThumbOriginX = self.thumbView.frame.minX
        self.thumbView.interactionBegan(at: location)
        
        return true
    }
    
    public override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard self.isEnabled, self.isDragging else { return false }
        
        let location = touch.location(in: self)
        let deltaX = location.x - self.dragStartLocationX
        let minX = self.thumbInset
        let maxX = self.bounds.width - self.thumbInset - self.thumbSize.width
        let proposedX = self.dragStartThumbOriginX + deltaX
        let clampedX = min(max(proposedX, minX), maxX)

        self.thumbView.frame.origin.x = clampedX
        
        let deltaFromStart = location.x - self.dragStartLocationX
        if abs(deltaFromStart) > self.dragMovementThreshold {
            self.isThumbMoved = true
        }

        let fraction = (clampedX - minX) / max(maxX - minX, 1.0)
        let threshold: CGFloat = 0.2
        if fraction <= threshold, self.isOn {
            self.startTrackFadeAnimation(toOn: false, duration: self.thumbAnimationDurationSetting * 0.4)
            self.setOn(false, animated: false, shouldUpdateAppearance: false, playHaptic: true)
        } else if fraction >= 1.0 - threshold, !self.isOn {
            self.startTrackFadeAnimation(toOn: true, duration: self.thumbAnimationDurationSetting * 0.4)
            self.setOn(true, animated: false, shouldUpdateAppearance: false, playHaptic: true)
        }
        
        self.thumbView.interactionUpdate(at: location)
        
        return true
    }
    
    public override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        self.syncGlassDurationsToThumb()
        self.thumbView.interactionEnded(shouldCompleteToPeak: !self.isThumbMoved)
        
        guard self.isEnabled else { return }
        
        let fraction = self.thumbView.frame.midX / max(self.bounds.width, 1.0)
        
        if self.isThumbMoved {
            self.setOn(fraction >= 0.5, animated: true, shouldUpdateAppearance: true, playHaptic: true)
        } else {
            self.setOn(!self.isOn, animated: true, shouldUpdateAppearance: true, playHaptic: true)
        }
        
        self.resetDragState()
    }
    
    public override func cancelTracking(with event: UIEvent?) {
        super.cancelTracking(with: event)
        self.resetDragState()
        self.updateThumbLayout(animated: false)
        self.updateTrackAppearance(animated: false)
    }
    
    public func setOn(_ isOn: Bool, animated: Bool) {
        self.setOn(isOn, animated: animated, shouldUpdateAppearance: true, playHaptic: false)
    }

    private func setOn(_ isOn: Bool, animated: Bool, shouldUpdateAppearance: Bool, playHaptic: Bool) {
        let isValueChanged = self.isOn != isOn
        self.isOn = isOn

        if shouldUpdateAppearance {
            let isInCorrectPosition = self.calculateThumbFrame().origin.x == self.thumbView.frame.origin.x
            if isValueChanged || !isInCorrectPosition {
                self.updateThumbLayout(animated: animated && !isInCorrectPosition)
            }
            self.updateTrackAppearance(animated: animated)
        }
        
        if playHaptic, isValueChanged {
            self.feedbackGenerator.impactOccurred()
            self.feedbackGenerator.prepare()
        }
    }
    
    private func updateTrackAppearance(animated: Bool) {
        self.backView.backgroundColor = self.offTintColor
        self.trackView.backgroundColor = self.onTintColor
        
        if animated {
            self.startTrackFadeAnimation(toOn: self.isOn, duration: self.thumbAnimationDurationSetting)
        } else {
            self.stopTrackFadeAnimation()
            self.trackView.alpha = self.isOn ? 1.0 : 0.0
        }
    }
    
    private func resetDragState() {
        self.isDragging = false
        self.isThumbMoved = false
        self.dragStartLocationX = 0.0
        self.dragStartThumbOriginX = self.isOn ? (self.bounds.width - self.thumbInset - self.thumbSize.width) : self.thumbInset
    }
    
    private func syncGlassDurationsToThumb() {
        let halfDuration = CGFloat(self.thumbAnimationDurationSetting * 0.5)
        self.thumbView.legacyGlassView.interactionScaleUpDuration = halfDuration
        self.thumbView.legacyGlassView.interactionScaleDownDuration = halfDuration
        self.thumbView.legacyGlassView.interactionActivationUpDuration = halfDuration
        self.thumbView.legacyGlassView.interactionActivationDownDuration = halfDuration
    }
    
    private func startThumbAnimation(to targetFrame: CGRect, duration: CFTimeInterval) {
        self.stopThumbAnimation()
        self.stopTrackFadeAnimation()
        
        self.thumbAnimationStartX = self.thumbView.frame.origin.x
        self.thumbAnimationEndX = targetFrame.origin.x
        self.thumbAnimationDuration = max(0.01, duration)
        self.thumbAnimationStartTime = CACurrentMediaTime()
        
        self.trackFadeStartAlpha = self.trackView.alpha
        self.trackFadeEndAlpha = self.isOn ? 1.0 : 0.0
        self.trackFadeDuration = self.thumbAnimationDuration
        self.trackFadeStartTime = self.thumbAnimationStartTime
        self.isTrackFadeDrivenByThumb = true
        
        self.thumbAnimationLink = SharedDisplayLinkDriver.shared.add(framesPerSecond: .max) { [weak self] _ in
            self?.thumbAnimationTick()
        }
    }
    
    private func stopThumbAnimation() {
        self.thumbAnimationLink?.invalidate()
        self.thumbAnimationLink = nil
    }

    private func startTrackFadeAnimation(toOn: Bool, duration: CFTimeInterval) {
        self.stopTrackFadeAnimation()
        
        self.trackFadeStartAlpha = self.trackView.alpha
        self.trackFadeEndAlpha = toOn ? 1.0 : 0.0
        self.trackFadeDuration = max(0.01, duration)
        self.trackFadeStartTime = CACurrentMediaTime()
        self.isTrackFadeDrivenByThumb = false
        
        self.trackFadeLink = SharedDisplayLinkDriver.shared.add(framesPerSecond: .max) { [weak self] _ in
            self?.trackFadeTick()
        }
    }
    
    private func stopTrackFadeAnimation() {
        self.trackFadeLink?.invalidate()
        self.trackFadeLink = nil
    }
    
    private func trackFadeTick() {
        guard self.trackFadeLink != nil else { return }
        
        let now = CACurrentMediaTime()
        let tRaw = (now - self.trackFadeStartTime) / max(self.trackFadeDuration, 0.0001)
        let t = CGFloat(min(max(tRaw, 0.0), 1.0))
        let eased = 1.0 - pow(1.0 - t, 3.0)
        
        self.trackView.alpha = self.trackFadeStartAlpha * (1.0 - eased) + self.trackFadeEndAlpha * eased

        if t >= 1.0 - .ulpOfOne {
            self.trackView.alpha = self.trackFadeEndAlpha
            self.stopTrackFadeAnimation()
        }
    }
    
    private func thumbAnimationTick() {
        guard self.thumbAnimationLink != nil else { return }
        
        let now = CACurrentMediaTime()
        let tRaw = (now - self.thumbAnimationStartTime) / max(self.thumbAnimationDuration, 0.0001)
        let t = CGFloat(min(max(tRaw, 0.0), 1.0))
        
        let eased = 1.0 - pow(1.0 - t, 3.0)
        self.thumbView.frame.origin.x = self.thumbAnimationStartX * (1.0 - eased) + self.thumbAnimationEndX * eased
        
        if self.isTrackFadeDrivenByThumb, self.trackFadeDuration > 0.0 {
            let fadeT = CGFloat(min(max((now - self.trackFadeStartTime) / self.trackFadeDuration, 0.0), 1.0))
            let fadeEased = 1.0 - pow(1.0 - fadeT, 3.0)
            self.trackView.alpha = self.trackFadeStartAlpha * (1.0 - fadeEased) + self.trackFadeEndAlpha * fadeEased
        }
        
        if t >= 1.0 - .ulpOfOne {
            self.thumbView.frame = CGRect(origin: CGPoint(x: self.thumbAnimationEndX, y: self.thumbInset), size: self.thumbSize)
            self.trackView.alpha = self.trackFadeEndAlpha
            self.stopThumbAnimation()
            if self.isTrackFadeDrivenByThumb {
                self.stopTrackFadeAnimation()
            }
        }
    }

}

extension LegacySwitchView: UIGestureRecognizerDelegate {
    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        
    }
    
    public override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === self.panGestureRecognizer else {
            return false
        }
        guard self.isEnabled else {
            return false
        }
        if let panRecognizer = gestureRecognizer as? UIPanGestureRecognizer {
            let velocity = panRecognizer.velocity(in: self)
            return abs(velocity.x) > abs(velocity.y)
        }
        return false
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === self.panGestureRecognizer {
            if otherGestureRecognizer is UIPanGestureRecognizer {
                if let _ = otherGestureRecognizer.view as? UIScrollView {
                    return true
                }
            }
        }
        return false
    }
    
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }
}

private final class ImmediatePanGestureRecognizer: UIPanGestureRecognizer {
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
    if state == .possible { state = .began }
        super.touchesMoved(touches, with: event)
    }
}
