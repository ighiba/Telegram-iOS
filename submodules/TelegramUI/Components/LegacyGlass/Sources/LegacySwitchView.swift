import UIKit
import Display

private let verticalPadding: CGFloat = 15.0
private let horizontalPadding: CGFloat = 15.0

public final class LegacySwitchView: UIControl {

    public override var intrinsicContentSize: CGSize {
        return CGSize(width: 63.0, height: 28.0)
    }

    public private(set) var isOn: Bool = false
    private var isDragging: Bool = false
    private var isKnobMoved: Bool = false
    
    private let knobSize = CGSize(width: 37.0, height: 24.0)
    private let knobInset: CGFloat = 2.0
    private let dragMovementThreshold: CGFloat = 5.0
    private var dragStartKnobOriginX: CGFloat = 0.0
    private var dragStartLocationX: CGFloat = 0.0
    
    private var knobAnimationDuration: CFTimeInterval = 0.5
    private var knobAnimator: DisplayLinkAnimator?
    private var trackFadeAnimator: DisplayLinkAnimator?
    
    public override var backgroundColor: UIColor? {
        get { self.captureContainerView.backgroundColor }
        set { self.captureContainerView.backgroundColor = newValue }
    }
    public var knobTintColor: UIColor = .white {
        didSet { self.updateTrackAppearance(animated: true) }
    }
    public var onTintColor: UIColor = UIColor(red: 0.4, green: 0.81, blue: 0.4, alpha: 1.0) {
        didSet { self.updateTrackAppearance(animated: true) }
    }
    public var offTintColor: UIColor = UIColor(red: 0.92, green: 0.92, blue: 0.96, alpha: 0.3) {
        didSet { self.updateTrackAppearance(animated: true) }
    }
    public override var tintColor: UIColor! {
        didSet { self.updateTrackAppearance(animated: false) }
    }

    private var panGestureRecognizer: UIPanGestureRecognizer?
    
    private let captureContainerMaskView = UIView()
    private let captureContainerView = UIView()
    private let containerView = UIView()
    private let backView = UIView()
    private let trackView = UIView()
    public let knobView: LegacyGlassKnobView
    
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    
    public override init(frame: CGRect) {
        var quality = LegacyGlassQualityProfile.automatic
        quality.captureScale = LegacyGlassQualityProfile.high.captureScale
        self.knobView = LegacyGlassKnobView(style: .switchKnob, qualityProfile: quality, size: self.knobSize)
        
        super.init(frame: frame)

        self.backgroundColor = .white
        self.backView.backgroundColor = self.offTintColor
        self.trackView.backgroundColor = self.onTintColor
        
        self.captureContainerMaskView.clipsToBounds = true
        self.containerView.layer.masksToBounds = true

        self.captureContainerMaskView.isUserInteractionEnabled = false
        self.captureContainerView.isUserInteractionEnabled = false
        self.containerView.isUserInteractionEnabled = false
        self.backView.isUserInteractionEnabled = false
        self.trackView.isUserInteractionEnabled = false

        self.knobView.isUserInteractionEnabled = false
        self.knobView.legacyGlassView.fillColor = .white
        self.knobView.legacyGlassView.useAdaptiveBrightness = true
        self.knobView.legacyGlassView.isActivationEnabled = true
        self.knobView.legacyGlassView.isScalingEnabled = true
        self.knobView.legacyGlassView.isJellyEnabled = true
        self.knobView.legacyGlassView.interactionJellyDirection = .horizontal
        self.knobView.legacyGlassView.cornerRadius = self.knobSize.height * 0.5
        self.knobView.legacyGlassView.interactionScaleMax = 1.54
        self.knobView.legacyGlassView.interactionJellyDamping = 75.0
        self.knobView.legacyGlassView.verticalPadding = verticalPadding
        self.knobView.legacyGlassView.horizontalPadding = horizontalPadding
        self.knobView.legacyGlassView.setCaptureHostView(self.captureContainerView)
        self.syncGlassDurationsToKnob()
        
        self.containerView.addSubview(self.backView)
        self.containerView.addSubview(self.trackView)
        self.captureContainerView.addSubview(self.containerView)
        self.captureContainerMaskView.addSubview(self.captureContainerView)
        self.addSubview(self.captureContainerMaskView)
        self.addSubview(self.knobView)

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
        self.captureContainerMaskView.frame = self.bounds
        self.captureContainerView.frame = self.captureContainerMaskView.bounds.insetBy(dx: -15, dy: -5)
        self.containerView.frame = self.captureContainerView.bounds.insetBy(dx: 15, dy: 5)
        self.backView.frame = self.containerView.bounds
        self.trackView.frame = self.containerView.bounds
        self.containerView.layer.cornerRadius = self.bounds.height * 0.5
        self.updateKnobLayout(animated: false)
    }
    
    public override func sizeToFit() {
        self.bounds.size = self.intrinsicContentSize
        self.setNeedsLayout()
    }
    
    private func updateKnobLayout(animated: Bool) {
        let targetFrame = self.calculateKnobFrame()
        if animated {
            self.syncGlassDurationsToKnob()
            self.startKnobAnimation(to: targetFrame, duration: self.knobAnimationDuration)
        } else {
            self.knobView.frame = targetFrame
        }
    }
    
    private func calculateKnobFrame() -> CGRect {
        let knobOriginX: CGFloat
        if self.isOn {
            knobOriginX = self.bounds.width - self.knobInset - self.knobSize.width
        } else {
            knobOriginX = self.knobInset
        }
        return CGRect(origin: CGPoint(x: knobOriginX, y: self.knobInset), size: self.knobSize)
    }
    
    public override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard self.isEnabled else { return false }

        self.resetDragState()
        self.isDragging = true
        self.syncGlassDurationsToKnob()
        self.feedbackGenerator.prepare()
        
        let location = touch.location(in: self)
        self.dragStartLocationX = location.x
        self.dragStartKnobOriginX = self.knobView.frame.minX
        self.knobView.interactionBegan(at: location)
        
        return true
    }
    
    public override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard self.isEnabled, self.isDragging else { return false }
        
        let location = touch.location(in: self)
        let deltaX = location.x - self.dragStartLocationX
        let minX = self.knobInset
        let maxX = self.bounds.width - self.knobInset - self.knobSize.width
        let proposedX = self.dragStartKnobOriginX + deltaX
        let clampedX = min(max(proposedX, minX), maxX)

        self.knobView.frame.origin.x = clampedX
        
        let deltaFromStart = location.x - self.dragStartLocationX
        if abs(deltaFromStart) > self.dragMovementThreshold {
            self.isKnobMoved = true
        }

        let fraction = (clampedX - minX) / max(maxX - minX, 1.0)
        let threshold: CGFloat = 0.2
        if fraction <= threshold, self.isOn {
            self.startTrackFadeAnimation(toOn: false, duration: self.knobAnimationDuration * 0.4)
            self.setOn(false, animated: false, shouldUpdateAppearance: false, playHaptic: true)
        } else if fraction >= 1.0 - threshold, !self.isOn {
            self.startTrackFadeAnimation(toOn: true, duration: self.knobAnimationDuration * 0.4)
            self.setOn(true, animated: false, shouldUpdateAppearance: false, playHaptic: true)
        }
        
        self.knobView.interactionUpdate(at: location)
        
        return true
    }
    
    public override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        self.syncGlassDurationsToKnob()
        self.knobView.interactionEnded(shouldCompleteToPeak: !self.isKnobMoved)
        
        guard self.isEnabled else { return }
        
        let fraction = self.knobView.frame.midX / max(self.bounds.width, 1.0)
        
        if self.isKnobMoved {
            self.setOn(fraction >= 0.5, animated: true, shouldUpdateAppearance: true, playHaptic: true)
        } else {
            self.setOn(!self.isOn, animated: true, shouldUpdateAppearance: true, playHaptic: true)
        }
        
        self.resetDragState()
    }
    
    public override func cancelTracking(with event: UIEvent?) {
        super.cancelTracking(with: event)
        self.resetDragState()
        self.updateKnobLayout(animated: false)
        self.updateTrackAppearance(animated: false)
    }
    
    public func setOn(_ isOn: Bool, animated: Bool, shouldSendAction: Bool = true) {
        self.setOn(isOn, animated: animated, shouldSendAction: shouldSendAction, shouldUpdateAppearance: true, playHaptic: false)
    }

    private func setOn(_ isOn: Bool, animated: Bool, shouldSendAction: Bool = true, shouldUpdateAppearance: Bool, playHaptic: Bool) {
        let isValueChanged = self.isOn != isOn
        self.isOn = isOn
        if isValueChanged && shouldSendAction {
            self.sendActions(for: .valueChanged)
        }

        if shouldUpdateAppearance {
            let isInCorrectPosition = self.calculateKnobFrame().origin.x == self.knobView.frame.origin.x
            if isValueChanged || !isInCorrectPosition {
                self.updateKnobLayout(animated: animated && !isInCorrectPosition)
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
            self.startTrackFadeAnimation(toOn: self.isOn, duration: self.knobAnimationDuration)
        } else {
            self.stopTrackFadeAnimation()
            self.trackView.alpha = self.isOn ? 1.0 : 0.0
        }
    }
    
    private func resetDragState() {
        self.isDragging = false
        self.isKnobMoved = false
        self.dragStartLocationX = 0.0
        self.dragStartKnobOriginX = self.isOn ? (self.bounds.width - self.knobInset - self.knobSize.width) : self.knobInset
    }
    
    private func syncGlassDurationsToKnob() {
        let halfDuration = CGFloat(self.knobAnimationDuration * 0.5)
        self.knobView.legacyGlassView.interactionScaleUpDuration = halfDuration
        self.knobView.legacyGlassView.interactionScaleDownDuration = halfDuration
        self.knobView.legacyGlassView.interactionActivationUpDuration = halfDuration
        self.knobView.legacyGlassView.interactionActivationDownDuration = halfDuration
    }
    
    private func startKnobAnimation(to targetFrame: CGRect, duration: CFTimeInterval) {
        self.stopKnobAnimation()
        self.stopTrackFadeAnimation()
        
        let startX = self.knobView.frame.origin.x
        let endX = targetFrame.origin.x
        let animationDuration = max(0.01, duration)
        let deltaX = endX - startX
        
        let trackFadeStartAlpha = self.trackView.alpha
        let trackFadeEndAlpha = self.isOn ? 1.0 : 0.0
        
        self.knobAnimator = DisplayLinkAnimator(
            duration: animationDuration,
            from: 0.0,
            to: 1.0,
            update: { [weak self] linearProgress in
                guard let self = self else { return }
                let easedProgress = 1.0 - pow(1.0 - linearProgress, 3.0)
                let easedX = startX + deltaX * easedProgress
                self.knobView.frame.origin.x = easedX
                
                let fadeEased = easedProgress
                self.trackView.alpha = trackFadeStartAlpha * (1.0 - fadeEased) + trackFadeEndAlpha * fadeEased
            },
            completion: { [weak self] in
                guard let self = self else { return }
                self.knobView.frame = CGRect(origin: CGPoint(x: endX, y: self.knobInset), size: self.knobSize)
                self.trackView.alpha = trackFadeEndAlpha
            }
        )
    }
    
    private func startTrackFadeAnimation(toOn: Bool, duration: CFTimeInterval) {
        self.stopTrackFadeAnimation()
        
        let startAlpha = self.trackView.alpha
        let endAlpha: CGFloat = toOn ? 1.0 : 0.0
        let animationDuration = max(0.01, duration)
        
        self.trackFadeAnimator = DisplayLinkAnimator(
            duration: animationDuration,
            from: 0.0,
            to: 1.0,
            update: { [weak self] linearProgress in
                guard let self = self else { return }
                let easedProgress = 1.0 - pow(1.0 - linearProgress, 3.0)
                self.trackView.alpha = startAlpha * (1.0 - easedProgress) + endAlpha * easedProgress
            },
            completion: { [weak self] in
                guard let self = self else { return }
                self.trackView.alpha = endAlpha
            }
        )
    }
    
    private func stopKnobAnimation() {
        self.knobAnimator?.invalidate()
        self.knobAnimator = nil
    }
    
    private func stopTrackFadeAnimation() {
        self.trackFadeAnimator?.invalidate()
        self.trackFadeAnimator = nil
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
