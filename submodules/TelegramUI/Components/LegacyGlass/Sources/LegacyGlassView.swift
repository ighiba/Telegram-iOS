import UIKit
import Metal
import MetalKit
import simd
import Display

final class LegacyGlassContext {
    var style: LegacyGlassStyle
    var qualityProfile: LegacyGlassQualityProfile
    
    var horizontalPadding: CGFloat = 0.0
    var verticalPadding: CGFloat = 0.0
    var cornerRadius: CGFloat = 0.0

    var lastHostOrigin: simd_float2 = .zero
    var lastUpdateTimestamp: CFTimeInterval = 0.0
    
    var interactionActivationProgress: CGFloat = 0.0
    var interactionActivationTarget: CGFloat = 0.0
    
    var interactionScale: CGFloat = 1.0
    var interactionScaleTarget: CGFloat = 1.0
    
    var interactionJelly: CGFloat = 0.0
    var interactionJellyVelocity: CGFloat = 0.0
    var interactionJellyTarget: CGFloat = 0.0
    let interactionJellyGain: CGFloat = 0.1
    let interactionJellyMax: CGFloat = 0.2
    var interactionJellyDamping: CGFloat = 18.0
    var interactionJellyDirection: LegacyGlassInteraction.JellyDirection = .horizontal

    var interactionStretch: CGPoint = .zero
    var interactionStretchVelocity: CGPoint = .zero
    var interactionStretchTarget: CGPoint = .zero
    let interactionStretchGain: CGFloat = 0.008
    let interactionStretchMax: CGFloat = 0.15
    let interactionStretchDamping: CGFloat = 25.0
    let interactionStretchEaseFactor: CGFloat = 1.0
    
    var interactionGlow: CGFloat = 0.0
    var interactionGlowVelocity: CGFloat = 0.0
    var interactionGlowTarget: CGFloat = 0.0
    var interactionGlowCenter: CGPoint = .zero
    var interactionGlowSmoothing: CGFloat = 10.0
    
    public init(style: LegacyGlassStyle, qualityProfile: LegacyGlassQualityProfile) {
        self.style = style
        self.qualityProfile = qualityProfile
    }
}

public enum LegacyGlassInteraction {
    public enum JellyDirection {
        case vertical
        case horizontal
    }
}

public final class LegacyGlassView: UIView {
    
    public var willActivate: ((TimeInterval) -> Void)?
    public var willDeactivate: ((TimeInterval) -> Void)?
    
    public var onCaptureBegan: (() -> Void)?
    public var onCaptureEnded: (() -> Void)?

    public var isActivationEnabled: Bool = false
    public var isScalingEnabled: Bool = false
    public var isJellyEnabled: Bool = false
    public var isStretchEnabled: Bool = false
    public var isGlowEnabled: Bool = false
    
    private var isPressActive: Bool = false
    
    public var autoUpdatesOnScroll: Bool = false {
        didSet {
            self.updateNestedHostScrollObservers()
        }
    }
    
    public var useAdditionalFrontImage: Bool {
        get { self.rendererView.useAdditionalFrontImage }
        set { self.rendererView.useAdditionalFrontImage = newValue }
    }
    
    public var useLayerBaseRender: Bool {
        get { self.rendererView.useLayerBaseRender }
        set { self.rendererView.useLayerBaseRender = newValue }
    }
    
    public var isIdleImageEnabled: Bool {
        get { self.context.style.isIdleImageEnabled }
        set {
            self.context.style.isIdleImageEnabled = newValue
            self.updateIdleRenderingPolicy()
        }
    }
    
    public var qualityProfile: LegacyGlassQualityProfile {
        return self.context.qualityProfile
    }

    public var captureMode: LegacyGlassCaptureMode {
        self.rendererView.captureMode
    }
    
    public var captureScale: CGFloat {
        self.rendererView.currentCaptureScale()
    }
    
    public var hasAdditionalFrontImage: Bool {
        self.rendererView.hasAdditionalFrontImage
    }
    
    public var isSafeBoundsCaptureEnabled: Bool {
        get { self.rendererView.isSafeBoundsCaptureEnabled }
        set { self.rendererView.isSafeBoundsCaptureEnabled = newValue }
    }
    
    public var dimmingMin: Float {
        get { self.rendererView.dimmingMin }
        set { self.rendererView.dimmingMin = newValue }
    }
    
    public var dimmingMax: Float {
        get { self.rendererView.dimmingMax }
        set { self.rendererView.dimmingMax = newValue }
    }

    public override var tintColor: UIColor? {
        get { self.rendererView.tintColor }
        set { self.rendererView.tintColor = newValue }
    }
    
    public var fillColor: UIColor? {
        get { self.rendererView.fillColor }
        set { self.rendererView.fillColor = newValue }
    }

    public var additionalFrontImageBackgroundColor: UIColor? {
        get { self.rendererView.additionalFrontImageBackgroundColor }
        set { self.rendererView.additionalFrontImageBackgroundColor = newValue }
    }
    
    public var horizontalPadding: CGFloat {
        get { self.context.horizontalPadding }
        set { self.context.horizontalPadding = newValue }
    }
    
    public var verticalPadding: CGFloat {
        get { self.context.verticalPadding }
        set { self.context.verticalPadding = newValue }
    }

    public var cornerRadius: CGFloat {
        get { self.context.cornerRadius }
        set { self.context.cornerRadius = newValue }
    }
    
    public var interactionJellyDirection: LegacyGlassInteraction.JellyDirection {
        get { self.context.interactionJellyDirection }
        set { self.context.interactionJellyDirection = newValue }
    }
    
    public var interactionJellyDamping: CGFloat {
        get { self.context.interactionJellyDamping }
        set { self.context.interactionJellyDamping = newValue }
    }
    
    public var interactionGlowSmoothing: CGFloat {
        get { self.context.interactionGlowSmoothing }
        set { self.context.interactionGlowSmoothing = newValue }
    }

    public var interactionScaleUpDuration: CGFloat = 0.12
    public var interactionScaleDownDuration: CGFloat = 0.16
    public var interactionActivationUpDuration: CGFloat = 0.12
    public var interactionActivationDownDuration: CGFloat = 0.16
    
    public var interactionScaleMax: CGFloat = 1.05
    
    private let scaleAnimator = LegacyGlassAnimator()
    private let activationAnimator = LegacyGlassAnimator()
    private var interactionDisplayLink: SharedDisplayLinkDriver.Link?
        
    private weak var nestedHostScrollView: UIScrollView?
    private var nestedHostScrollObservations: [NSKeyValueObservation] = []
    
    private weak var captureHostViewOverride: UIView?
    
    var idleImagePadding: CGFloat = 10.0
    private var idleImage: UIImage?
    private var idleImageView: UIImageView?
    
    public var contentView = UIView()
    
    let context: LegacyGlassContext
    let rendererView: LegacyGlassRenderer
    
    public init(style: LegacyGlassStyle, qualityProfile: LegacyGlassQualityProfile, idleImage: UIImage? = nil, allowsGroupSnapshotting: Bool) {
        let context = LegacyGlassContext(style: style, qualityProfile: qualityProfile)
        self.context = context
        self.rendererView = LegacyGlassRenderer(context: context, allowsGroupSnapshotting: allowsGroupSnapshotting)

        super.init(frame: .zero)
        
        self.rendererView.glassDelegate = self
        
        self.isOpaque = false
        self.backgroundColor = .clear
        
        self.contentView.isUserInteractionEnabled = false
        self.rendererView.isUserInteractionEnabled = false
        
        self.rendererView.fillColor = self.fillColor
        
        self.addSubview(self.rendererView)
        
        if let idleImage, self.context.style.isIdleImageEnabled {
            self.idleImage = idleImage
            let idleImageView = UIImageView(image: idleImage)
            idleImageView.alpha = self.idleImage == nil ? 0.0 : 1.0
            idleImageView.image = self.idleImage
            idleImageView.isOpaque = false
            idleImageView.backgroundColor = .clear
            idleImageView.contentMode = .scaleToFill
            idleImageView.clipsToBounds = false
            idleImageView.isUserInteractionEnabled = false
            self.addSubview(idleImageView)
            self.idleImageView = idleImageView
            self.updateIdleRenderingPolicy()
        }

        self.addSubview(self.contentView)
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.nestedHostScrollObservations.removeAll()
    }
    
    override public func layoutSubviews() {
        super.layoutSubviews()
        self.updateOverlayLayout()

        let safeBoundsSize = clampBoundsSize(self.bounds.size)
        let safeBounds = CGRect(origin: self.bounds.origin, size: safeBoundsSize)
        self.rendererView.frame = safeBounds.insetBy(dx: -self.horizontalPadding, dy: -self.verticalPadding)
        
        let clampedDrawableSize = clampBoundsSize(self.rendererView.bounds.size)
        self.rendererView.drawableSize = clampedDrawableSize
        self.contentView.frame = self.bounds
        
        if let idleImageView {
            let padding = self.idleImagePadding
            idleImageView.frame = self.bounds.insetBy(dx: -padding, dy: -padding)
            idleImageView.layer.cornerRadius = 0
            idleImageView.layer.masksToBounds = false
        }

        if self.context.style.isIdleImageEnabled {
            self.rendererView.isHidden = false
        }
        
        if self.context.style.isIdleImageEnabled && !self.bounds.isEmpty {
            self.updateIdleImageView()
            if self.window != nil {
                self.prerenderFirstMetalFrame()
            }
        }
    }
    
    override public func didMoveToWindow() {
        super.didMoveToWindow()
        self.updateNestedHostScrollObservers()
        self.updateOverlayLayout()
        
        if self.context.style.isIdleImageEnabled {
            self.setNeedsLayout()
            self.layoutIfNeeded()
            self.updateIdleImageView()
            self.prerenderFirstMetalFrame()
        }
    }
    
    override public func didMoveToSuperview() {
        super.didMoveToSuperview()
        self.updateNestedHostScrollObservers()
        if self.context.style.isIdleImageEnabled {
            self.setNeedsLayout()
            self.layoutIfNeeded()
            self.updateIdleImageView()
        }
    }
    
    override public func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard let point = touches.first?.location(in: self) else { return }
        self.interactionBegan(at: point)
    }
    
    override public func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard let point = touches.first?.location(in: self) else { return }
        self.interactionUpdate(at: point)
    }

    override public func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        self.context.interactionStretchTarget = .zero
        self.interactionEnded()
    }

    override public func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        self.context.interactionStretchTarget = .zero
        self.interactionEnded()
    }
    
    public func setStyle(_ style: LegacyGlassStyle) {
        self.context.style = style
    }
    
    public func updateStyle(_ block: (inout LegacyGlassStyle) -> ()) {
        var style = self.context.style
        block(&style)
        self.setStyle(style)
    }
    
    public func updateQualityProfile(_ block: (inout LegacyGlassQualityProfile) -> ()) {
        var qualityProfile = self.context.qualityProfile
        block(&qualityProfile)
        self.context.qualityProfile = qualityProfile
    }

    public func setCaptureHostView(_ captureHostView: UIView) {
        self.captureHostViewOverride = captureHostView
        self.rendererView.setCaptureHostView(captureHostView)
        self.updateNestedHostScrollObservers()
    }

    public func setCaptureMode(_ captureMode: LegacyGlassCaptureMode) {
        self.rendererView.setCaptureMode(captureMode)
    }

    public func requestUpdate() {
        self.rendererView.requestUpdate()
    }
    
    public func setBlurFilterSigma(value: Float) {
        self.rendererView.blurFilterSigma = value
    }
    
    public func setAdditionalFrontImage(_ cgImage: CGImage?, atOrigin origin: CGPoint) {
        let paddedOrigin = CGPoint(x: origin.x + horizontalPadding, y: origin.y + verticalPadding)
        self.rendererView.setAdditionalFrontImage(cgImage, atPaddedOrigin: paddedOrigin)
    }
    
    public func updateAdditionalFrontImageOrigin(at origin: CGPoint) {
        let paddedOrigin = CGPoint(x: origin.x + horizontalPadding, y: origin.y + verticalPadding)
        self.rendererView.updateAdditionalFrontImageOrigin(at: paddedOrigin)
    }
    
    public func interactionBegan(at point: CGPoint) {
        self.isPressActive = true
        if self.context.style.isIdleImageEnabled {
            self.rendererView.setIsPaused(false)
            self.rendererView.isHidden = false
            self.rendererView.setNeedsDisplay()
            self.setNeedsLayout()
        }
        self.context.interactionScaleTarget = self.interactionScaleMax
        self.context.interactionActivationTarget = 1.0
        self.updateInteractionGlowCenter(with: point)
        
        let currentScale = self.context.interactionScale
        let scaleSegment = LegacyGlassAnimationSegment(
            from: currentScale,
            to: self.interactionScaleMax,
            duration: self.interactionScaleUpDuration,
            easing: .easeOut,
            elapsed: 0.0
        )
        self.scaleAnimator.enqueueAnimationSegments([scaleSegment])
        
        if self.isActivationEnabled {
            let currentActivation = self.context.interactionActivationProgress
            let duration = self.interactionActivationUpDuration
            let activationSegment = LegacyGlassAnimationSegment(
                from: currentActivation,
                to: 1.0,
                duration: self.interactionActivationUpDuration,
                easing: .easeOut,
                elapsed: 0.0,
                onBegin: { [weak self] in
                    self?.willActivate?(duration)
                }
            )
            self.activationAnimator.enqueueAnimationSegments([activationSegment])
        } else {
            self.activationAnimator.reset(to: 0.0)
            self.context.interactionActivationProgress = 0.0
        }
        
        self.startInteractionDisplayLink()
    }
    
    public func interactionUpdate(at point: CGPoint) {
        self.updateInteractionGlowCenter(with: point)
        self.updateInteractionStretch(at: point)
        self.startInteractionDisplayLink()
    }

    public func interactionEnded(shouldCompleteToPeak: Bool = false) {
        self.isPressActive = false
        self.context.interactionStretchTarget = .zero
        self.context.interactionGlowTarget = 0.0
        self.context.interactionScaleTarget = 1.0
        self.context.interactionActivationTarget = 0.0
        
        let currentScale = self.context.interactionScale
        let peak = self.interactionScaleMax
        let remainingRatio = (peak - currentScale) / max(peak - 1.0, 0.0001)
        let remainingUpDuration = max(0.04, self.interactionScaleUpDuration * max(0.0, min(1.0, remainingRatio)))
        let returnDuration: CGFloat = self.interactionScaleDownDuration
        
        if shouldCompleteToPeak && self.isScalingEnabled {
            let upSegment = LegacyGlassAnimationSegment(
                from: currentScale,
                to: peak,
                duration: remainingUpDuration,
                easing: .easeOut,
                elapsed: 0.0,
                onBegin: { [weak self] in
                    self?.willActivate?(remainingUpDuration)
                }
            )
            let downSegment = LegacyGlassAnimationSegment(
                from: peak,
                to: 1.0,
                duration: returnDuration,
                easing: .easeInOut,
                elapsed: 0.0,
                onBegin: { [weak self] in
                    self?.willDeactivate?(returnDuration)
                }
            )
            self.scaleAnimator.enqueueAnimationSegments([upSegment, downSegment])
        } else {
            let downSegment = LegacyGlassAnimationSegment(
                from: currentScale,
                to: 1.0,
                duration: returnDuration,
                easing: .easeInOut,
                elapsed: 0.0,
                onBegin: { [weak self] in
                    self?.willDeactivate?(returnDuration)
                }
            )
            self.scaleAnimator.enqueueAnimationSegments([downSegment])
        }
        
        if self.isActivationEnabled {
            let currentActivation = self.context.interactionActivationProgress
            if shouldCompleteToPeak {
                let durationUp = max(0.04, self.interactionActivationUpDuration * max(0.0, min(1.0, remainingRatio)))
                let durationDown = self.interactionActivationDownDuration
                let activationUp = LegacyGlassAnimationSegment(
                    from: currentActivation,
                    to: 1.0,
                    duration: durationUp,
                    easing: .easeOut,
                    elapsed: 0.0,
                    onBegin: { [weak self] in
                        self?.willActivate?(remainingUpDuration)
                    }
                )
                let activationDown = LegacyGlassAnimationSegment(
                    from: 1.0,
                    to: 0.0,
                    duration: durationDown,
                    easing: .easeInOut,
                    elapsed: 0.0,
                    onBegin: { [weak self] in
                        self?.willDeactivate?(durationDown)
                    }
                )
                self.activationAnimator.enqueueAnimationSegments([activationUp, activationDown])
            } else {
                let duration = self.interactionActivationDownDuration
                let activationDown = LegacyGlassAnimationSegment(
                    from: currentActivation,
                    to: 0.0,
                    duration: duration,
                    easing: .easeInOut,
                    elapsed: 0.0,
                    onBegin: { [weak self] in
                        self?.willDeactivate?(duration)
                    }
                )
                self.activationAnimator.enqueueAnimationSegments([activationDown])
            }
        } else {
            self.activationAnimator.reset(to: 0.0)
            self.context.interactionActivationProgress = 0.0
        }
        
        self.startInteractionDisplayLink()
    }

    private func updateInteractionGlowCenter(with point: CGPoint) {
        guard self.isGlowEnabled else { return }
        
        let uv = CGPoint(
            x: (point.x + self.context.horizontalPadding) / self.rendererView.bounds.width,
            y: (point.y + self.context.verticalPadding) / self.rendererView.bounds.height
        )
        self.context.interactionGlowCenter = CGPoint(x: max(0.0, min(1.0, uv.x)), y: max(0.0, min(1.0, uv.y)))
        self.context.interactionGlowTarget = 1.0
    }
    
    private func updateInteractionStretch(at point: CGPoint) {
        guard self.isStretchEnabled else { return }
        
        let center = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
        let radiusX = self.bounds.width * 0.5
        let radiusY = self.bounds.height * 0.5

        let deltaX = point.x - center.x
        let deltaY = point.y - center.y

        let normalizedX = deltaX / radiusX
        let normalizedY = deltaY / radiusY
        let normalizedDistance = sqrt(normalizedX * normalizedX + normalizedY * normalizedY)

        if normalizedDistance > 1.0 {
            let length = sqrt(normalizedX * normalizedX + normalizedY * normalizedY)
            let direction = CGPoint(x: normalizedX / length, y: normalizedY / length)
            
            let overflowNormalized = normalizedDistance - 1.0
            let easedOverflow = overflowNormalized / (1.0 + overflowNormalized * self.context.interactionStretchEaseFactor)
            let minRadius = min(radiusX, radiusY)
            let overflow = easedOverflow * minRadius
            
            let rawTarget = CGPoint(
                x: direction.x * overflow * self.context.interactionStretchGain,
                y: direction.y * overflow * self.context.interactionStretchGain
            )
            
            let stretchMax = self.context.interactionStretchMax
            self.context.interactionStretchTarget = CGPoint(
                x: min(max(rawTarget.x, -stretchMax), stretchMax),
                y: min(max(rawTarget.y, -stretchMax), stretchMax)
            )
        }
    }

    private func startInteractionDisplayLink() {
        if self.interactionDisplayLink == nil {
            self.interactionDisplayLink = SharedDisplayLinkDriver.shared.add(framesPerSecond: .max) { [weak self] delta in
                self?.displayLinkTick(deltaTime: CGFloat(delta))
            }
        }
        self.interactionDisplayLink?.isPaused = false
    }

    private func displayLinkTick(deltaTime: CGFloat) {
        guard self.hasActiveInteraction() else {
            if self.context.style.isIdleImageEnabled {
                self.updateIdleRenderingPolicy()
            }
            self.interactionDisplayLink?.isPaused = true
            return
        }

        let minDelta: CGFloat = 1.0 / 120.0
        let maxDelta: CGFloat = 1.0 / 20.0
        let clampedDelta = min(max(deltaTime, minDelta), maxDelta)

        self.tickActivation(dt: clampedDelta)
        self.tickScale(dt: clampedDelta)
        self.tickJelly(dt: clampedDelta)
        self.tickStretch(dt: clampedDelta)
        self.tickGlow(dt: clampedDelta)
        self.updateIdleRenderingPolicy()
    }
    
    private func hasActiveInteraction() -> Bool {
        let threshold: CGFloat = 0.0005

        let jellyDisplacement = abs(self.context.interactionJelly - self.context.interactionJellyTarget)
        let isJellyVelocityActive = abs(self.context.interactionJellyVelocity) > threshold
        let isJellyOngoing = jellyDisplacement > threshold || isJellyVelocityActive

        let stretchDisplacement = hypot(self.context.interactionStretch.x - self.context.interactionStretchTarget.x, self.context.interactionStretch.y - self.context.interactionStretchTarget.y)
        let isStretchVelocityActive = hypot(self.context.interactionStretchVelocity.x, self.context.interactionStretchVelocity.y) > threshold
        let isStretchOngoing = stretchDisplacement > threshold || isStretchVelocityActive

        let glowDisplacement = abs(self.context.interactionGlow - self.context.interactionGlowTarget)
        let isGlowVelocityActive = abs(self.context.interactionGlowVelocity) > threshold
        let isGlowOngoing = glowDisplacement > threshold || isGlowVelocityActive
        
        let isScalingOngoing = self.isScalingEnabled && self.scaleAnimator.isRunning
        let isActivationOngoing = self.isActivationEnabled && self.activationAnimator.isRunning

        let isJellyPermitted = self.isJellyEnabled && isJellyOngoing
        let isStretchPermitted = self.isStretchEnabled && isStretchOngoing
        let isGlowPermitted = self.isGlowEnabled && isGlowOngoing

        return isScalingOngoing || isActivationOngoing || isJellyPermitted || isStretchPermitted || isGlowPermitted || self.isPressActive
    }
    
    private func tickActivation(dt: CGFloat) {
        guard self.isActivationEnabled else {
            self.context.interactionActivationProgress = 0.0
            self.context.interactionActivationTarget = 0.0
            self.activationAnimator.reset(to: 0.0)
            return
        }
        
        self.activationAnimator.tick(delta: dt)
        self.context.interactionActivationProgress = self.activationAnimator.currentValue
    }

    private func tickScale(dt: CGFloat) {
        guard self.isScalingEnabled else {
            self.context.interactionScale = 1.0
            self.context.interactionScaleTarget = 1.0
            self.scaleAnimator.reset(to: 1.0)
            return
        }
        
        self.scaleAnimator.tick(delta: dt)
        self.context.interactionScale = self.scaleAnimator.currentValue
    }

    private func tickJelly(dt: CGFloat) {
        guard self.isJellyEnabled else {
            self.context.interactionJelly = 0.0
            self.context.interactionJellyVelocity = 0.0
            self.context.interactionJellyTarget = 0.0
            return
        }

        let jellyStiffness: CGFloat = 300.0
        let jellyDamping = self.context.interactionJellyDamping
        let jellyDisplacement = self.context.interactionJelly - self.context.interactionJellyTarget
        let jellyAcceleration = -jellyStiffness * jellyDisplacement - jellyDamping * self.context.interactionJellyVelocity
        self.context.interactionJellyVelocity += jellyAcceleration * dt
        self.context.interactionJelly += self.context.interactionJellyVelocity * dt

        let jellyThreshold: CGFloat = 0.0005
        if abs(jellyDisplacement) < jellyThreshold && abs(self.context.interactionJellyVelocity) < jellyThreshold {
            self.context.interactionJelly = self.context.interactionJellyTarget
            self.context.interactionJellyVelocity = 0.0
        }
    }

    private func tickStretch(dt: CGFloat) {
        guard self.isStretchEnabled else {
            self.context.interactionStretch = .zero
            self.context.interactionStretchVelocity = .zero
            self.context.interactionStretchTarget = .zero
            return
        }

        let stiffness: CGFloat = 180.0
        let damping = self.context.interactionStretchDamping
        let displacement = CGPoint(
            x: self.context.interactionStretch.x - self.context.interactionStretchTarget.x,
            y: self.context.interactionStretch.y - self.context.interactionStretchTarget.y
        )
        let acceleration = CGPoint(
            x: -stiffness * displacement.x - damping * self.context.interactionStretchVelocity.x,
            y: -stiffness * displacement.y - damping * self.context.interactionStretchVelocity.y
        )
        self.context.interactionStretchVelocity.x += acceleration.x * dt
        self.context.interactionStretchVelocity.y += acceleration.y * dt
        self.context.interactionStretch.x += self.context.interactionStretchVelocity.x * dt
        self.context.interactionStretch.y += self.context.interactionStretchVelocity.y * dt

        let threshold: CGFloat = 0.0005
        if hypot(displacement.x, displacement.y) < threshold &&
            hypot(self.context.interactionStretchVelocity.x, self.context.interactionStretchVelocity.y) < threshold {
            self.context.interactionStretch = self.context.interactionStretchTarget
            self.context.interactionStretchVelocity = .zero
        }
    }
    
    private func tickGlow(dt: CGFloat) {
        guard self.isGlowEnabled else {
            self.context.interactionGlowTarget = 0.0
            return
        }

        let smoothing = max(self.context.interactionGlowSmoothing, 1e-3)
        let factor = 1.0 - exp(-dt * smoothing)
        let previous = self.context.interactionGlow
        self.context.interactionGlow += (self.context.interactionGlowTarget - self.context.interactionGlow) * factor
        self.context.interactionGlowVelocity = (self.context.interactionGlow - previous) / max(dt, 1e-4)

        let threshold: CGFloat = 0.0005
        if abs(self.context.interactionGlow - self.context.interactionGlowTarget) < threshold && abs(self.context.interactionGlowVelocity) < threshold {
            self.context.interactionGlow = self.context.interactionGlowTarget
            self.context.interactionGlowVelocity = 0.0
        }
    }
    
    private func updateIdleImageView() {
        guard let idleImageView = self.idleImageView else { return }
        guard self.context.style.isIdleImageEnabled else {
            idleImageView.alpha = 0.0
            return
        }
        
        let isIdle = !self.hasActiveInteraction()
        if isIdle, let image = self.idleImage {
            idleImageView.image = image
            idleImageView.isHidden = false
            self.animateIdleImageAlpha(value: 1.0)

            idleImageView.layer.setNeedsDisplay()
            
            if idleImageView.frame.isEmpty && !self.bounds.isEmpty {
                let padding = self.idleImagePadding
                idleImageView.frame = self.bounds.insetBy(dx: -padding, dy: -padding)
            }
        } else {
            self.animateIdleImageAlpha(value: 0.0)
        }
    }

    private func updateOverlayLayout() {
        if let hostWindow = self.window {
            self.rendererView.setCaptureHostView(self.captureHostViewOverride ?? hostWindow)
        }
    }
    
    private func updateNestedHostScrollObservers() {
        guard
            self.autoUpdatesOnScroll,
            let hostView = self.captureHostViewOverride ?? self.window
        else {
            self.nestedHostScrollObservations.removeAll()
            self.nestedHostScrollView = nil
            return
        }

        guard let scrollView = self.findScrollView(in: hostView, upward: false) else {
            self.nestedHostScrollObservations.removeAll()
            self.nestedHostScrollView = nil
            return
        }

        if self.nestedHostScrollView === scrollView {
            return
        }

        self.nestedHostScrollObservations.removeAll()
        self.nestedHostScrollView = scrollView
        
        let contentOffsetObs = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            self?.nestedHostScrollViewDidUpdate()
        }
        let boundsObs = scrollView.observe(\.bounds, options: [.new]) { [weak self] _, _ in
            self?.nestedHostScrollViewDidUpdate()
        }
        self.nestedHostScrollObservations.append(contentsOf: [contentOffsetObs, boundsObs])
    }
    
    private func findScrollView(in view: UIView, upward: Bool = true) -> UIScrollView? {
        if upward {
            var current: UIView? = view
            while let currentView = current {
                if let scrollView = currentView as? UIScrollView {
                    return scrollView
                }
                current = currentView.superview
            }
        } else {
            if let scrollView = view as? UIScrollView {
                return scrollView
            }
            
            for subview in view.subviews {
                if let scrollView = self.findScrollView(in: subview, upward: false) {
                    return scrollView
                }
            }
        }
        return nil
    }

    private func updateIdleRenderingPolicy() {
        guard
            let _ = self.idleImageView,
            self.context.style.isIdleImageEnabled
        else {
            self.idleImageView?.isHidden = true
            self.rendererView.isHidden = false
            return
        }

        let isIdle = !self.hasActiveInteraction()
        if isIdle {
            self.updateIdleImageView()
            self.rendererView.enableSetNeedsDisplay = false
            self.rendererView.setIsPaused(true)
            self.rendererView.isHidden = false
        } else {
            self.rendererView.enableSetNeedsDisplay = false
            self.rendererView.setIsPaused(false)
            self.rendererView.isHidden = false
            
            let activationProgressThreshold: CGFloat = 0.15
            if self.context.interactionActivationProgress >= activationProgressThreshold {
                self.animateIdleImageAlpha(value: 0.0)
            } else {
                self.animateIdleImageAlpha(value: 1.0)
            }
        }
    }
    
    private func prerenderFirstMetalFrame() {
        guard self.context.style.isIdleImageEnabled,
              self.window != nil,
              !self.bounds.isEmpty else {
            return
        }
        
        let wasEnableSetNeedsDisplay = self.rendererView.enableSetNeedsDisplay
        
        self.rendererView.setIsPaused(false)
        self.rendererView.isHidden = false
        self.rendererView.enableSetNeedsDisplay = true
        self.rendererView.setNeedsDisplay()

        DispatchQueue.main.async { [weak self] in
            guard let strongSelf = self else { return }
            DispatchQueue.main.async {
                if strongSelf.context.interactionActivationProgress <= 0.0005 {
                    strongSelf.rendererView.setIsPaused(true)
                    strongSelf.rendererView.enableSetNeedsDisplay = wasEnableSetNeedsDisplay
                }
            }
        }
    }
    
    public func ensureFastCaptureWithDebounce(to debounceCaptureMode: LegacyGlassCaptureMode, duration: TimeInterval? = nil) {
        self.rendererView.ensureFastCaptureWithDebounce(to: debounceCaptureMode)
    }
    
    private func nestedHostScrollViewDidUpdate() {
        self.ensureFastCaptureWithDebounce(to: .dynamicBackground(.slow))
    }
    
    private func animateIdleImageAlpha(value: CGFloat, duration: TimeInterval = 0.1) {
        UIView.animate(withDuration: duration, delay: 0.0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            self.idleImageView?.alpha = value
        }
    }
}

extension LegacyGlassView: LegacyGlassRendererDelegate {
    var lensSize: CGSize {
        self.bounds.size
    }
    
    var glassView: UIView? {
        return self
    }
    
    func updateContentViewTransform(scale: CGPoint, translation: CGPoint) {
        let threshold: CGFloat = 0.0001
        if abs(scale.x - 1.0) > threshold || abs(scale.y - 1.0) > threshold {
            var transform = CATransform3DIdentity
            transform = CATransform3DScale(transform, scale.x, scale.y, 1.0)
            transform = CATransform3DTranslate(transform, translation.x, translation.y, 0.0)
            self.contentView.layer.sublayerTransform = transform
        } else {
            self.contentView.layer.sublayerTransform = CATransform3DIdentity
        }
    }
}

private func clampBoundsSize(_ size: CGSize) -> CGSize {
    let maxDimension: CGFloat = 4096.0
    guard size.width > 0 && size.height > 0 else {
        return .zero
    }
    guard !size.width.isInfinite && !size.width.isNaN && !size.height.isInfinite && !size.height.isNaN else {
        return .zero
    }
    guard size.width <= maxDimension && size.height <= maxDimension else {
        let scale = min(maxDimension / size.width, maxDimension / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
    return size
}
