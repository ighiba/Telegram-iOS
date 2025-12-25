import UIKit

private let defaultLineSize: CGFloat = 3
private let margin: CGFloat = 15
private let internalMargin: CGFloat = 10
private let defaultBackColor = UIColor(red: 0.914, green: 0.914, blue: 0.918, alpha: 1.0)
private let defaultTrackColor = UIColor.systemBlue

private let verticalPadding: CGFloat = 15.0
private let horizontalPadding: CGFloat = 20.0

public final class LegacySliderView: UIControl {
    
    public var interactionBegan: (() -> Void)?
    public var interactionEnded: (() -> Void)?
    public var reset: (() -> Void)?
    
    public var interfaceOrientation: UIInterfaceOrientation = .portrait
    public private(set) var knobStartedDragging: Bool = false
    public var limitValueChangedToLatestState: Bool = false
    private var knobTouchStart: CGFloat = 0
    private var knobTouchCenterStart: CGFloat = 0
    var knobDragCenter: CGFloat = 0
    var startHidden: Bool = false
    
    public var startValue: CGFloat = 0.0 {
        didSet {
            if abs(self.startValue - self.minimumValue) < .ulpOfOne {
                self.startHidden = true
            }
            self.setNeedsLayout()
            self.trackView.setNeedsDisplay()
        }
    }
    
    public var value: CGFloat = 0.0 {
        didSet { self.setNeedsLayout() }
    }
    
    public var lowerBoundValue: CGFloat = 0.0 {
        didSet { self.trackView.setNeedsDisplay() }
    }
    
    public var lowerBoundTrackColor: UIColor? {
        didSet { self.trackView.setNeedsDisplay() }
    }
    
    public var minimumValue: CGFloat = 0.0 {
        didSet { self.setNeedsLayout() }
    }
    
    public var maximumValue: CGFloat = 1.0 {
        didSet { self.setNeedsLayout() }
    }
    
    public var minimumUndottedValue: Int = -1 {
        didSet { self.trackView.setNeedsDisplay() }
    }
    
    public var markValue: CGFloat = 0.0 {
        didSet { self.trackView.setNeedsDisplay() }
    }
    
    public var displayEdges: Bool = false {
        didSet { self.trackView.setNeedsDisplay() }
    }
    
    public var useLinesForPositions: Bool = false {
        didSet { self.trackView.setNeedsDisplay() }
    }
    
    public var markPositions: Bool = true {
        didSet { self.trackView.setNeedsDisplay() }
    }
    
    public var knobPadding: CGFloat = internalMargin {
        didSet { self.setNeedsLayout() }
    }
    
    public var lineSize: CGFloat = defaultLineSize {
        didSet { self.setNeedsLayout() }
    }
    
    public override var backgroundColor: UIColor? {
        get { self.captureContainerView.backgroundColor }
        set { self.captureContainerView.backgroundColor = newValue }
    }
    
    public var backColor: UIColor = defaultBackColor {
        didSet { self.trackView.setNeedsDisplay() }
    }
    
    public var trackColor: UIColor = defaultTrackColor {
        didSet { self.trackView.setNeedsDisplay() }
    }
    
    public var startColor: UIColor = defaultTrackColor {
        didSet { self.trackView.setNeedsDisplay() }
    }
    
    public var trackCornerRadius: CGFloat = 0.0 {
        didSet { self.trackView.setNeedsDisplay() }
    }
    
    public var bordered: Bool = false {
        didSet { self.trackView.setNeedsDisplay() }
    }
    
    public var disableSnapToPositions: Bool = false {
        didSet { self.updateTapAvailability() }
    }
    
    public var positionsCount: Int = 0 {
        didSet { self.updateTapAvailability() }
    }
    
    public var knobSize: CGSize = CGSize(width: 37.0, height: 24.0) {
        didSet { self.setNeedsLayout() }
    }
    
    public var dotSize: CGFloat = 10.5 {
        didSet { self.trackView.setNeedsDisplay() }
    }
    
    public var enablePanHandling: Bool = false {
        didSet { self.panGestureRecognizer.isEnabled = self.enablePanHandling }
    }
    
    public var enableEdgeTap: Bool = false {
        didSet { self.edgeTapGestureRecognizer.isEnabled = self.enableEdgeTap }
    }
    
    private lazy var panGestureRecognizer: UIPanGestureRecognizer = {
        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        recognizer.isEnabled = false
        recognizer.delegate = self
        recognizer.delaysTouchesEnded = false
        recognizer.cancelsTouchesInView = false
        return recognizer
    }()

    private lazy var tapGestureRecognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        recognizer.isEnabled = false
        recognizer.delaysTouchesEnded = false
        recognizer.cancelsTouchesInView = false
        return recognizer
    }()

    private lazy var edgeTapGestureRecognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleEdgeTap(_:)))
        recognizer.isEnabled = false
        recognizer.delaysTouchesEnded = false
        recognizer.cancelsTouchesInView = false
        return recognizer
    }()

    private lazy var doubleTapGestureRecognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        recognizer.numberOfTapsRequired = 2
        recognizer.delaysTouchesEnded = false
        recognizer.cancelsTouchesInView = false
        return recognizer
    }()
    
    public var knobTouchPadding: CGFloat = 8.0

    private var isKnobTouched: Bool = false
    
    private var _isKnobTracking: Bool = false
    public override var isTracking: Bool {
        self._isKnobTracking
    }
    
    private let captureContainerMaskView = UIView()
    private let captureContainerView = UIView()
    private let containerView = UIView()
    private let trackView: TrackView
    public let knobView: LegacyGlassKnobView

    private let feedbackGenerator = UISelectionFeedbackGenerator()

    public override init(frame: CGRect) {
        self.trackView = TrackView()
        self.knobView = LegacyGlassKnobView(style: .sliderKnob, qualityProfile: .automatic, size: self.knobSize)
        
        super.init(frame: frame)
        
        self.minimumValue = 0
        self.maximumValue = 1
        self.startValue = 0
        self.value = self.startValue
        self.markPositions = true
        self.lineSize = defaultLineSize
        self.knobPadding = internalMargin
        self.backColor = defaultBackColor
        self.trackColor = defaultTrackColor
        self.startColor = defaultTrackColor
        
        self.captureContainerMaskView.isUserInteractionEnabled = false
        self.captureContainerView.isUserInteractionEnabled = false
        self.containerView.isUserInteractionEnabled = false
        self.trackView.isUserInteractionEnabled = false
        self.knobView.isUserInteractionEnabled = false
        
        self.backgroundColor = .white
        
        self.trackView.slider = self
        self.trackView.backgroundColor = .clear
        self.trackView.isOpaque = false
        
        self.captureContainerMaskView.clipsToBounds = true
        self.captureContainerMaskView.backgroundColor = .white
        
        self.knobView.legacyGlassView.fillColor = .white
        self.knobView.legacyGlassView.isActivationEnabled = true
        self.knobView.legacyGlassView.isScalingEnabled = true
        self.knobView.legacyGlassView.isJellyEnabled = true
        self.knobView.legacyGlassView.interactionJellyDirection = .horizontal
        self.knobView.legacyGlassView.cornerRadius = self.knobSize.height * 0.5
        self.knobView.legacyGlassView.interactionScaleMax = 1.54
        self.knobView.legacyGlassView.interactionJellyDamping = 9.0
        self.knobView.legacyGlassView.verticalPadding = verticalPadding
        self.knobView.legacyGlassView.horizontalPadding = horizontalPadding
        self.knobView.legacyGlassView.interactionScaleUpDuration = 0.25
        self.knobView.legacyGlassView.interactionScaleDownDuration = 0.3
        self.knobView.legacyGlassView.interactionActivationUpDuration = 0.25
        self.knobView.legacyGlassView.interactionActivationDownDuration = 0.3
        self.knobView.legacyGlassView.setCaptureHostView(self.captureContainerView)

        self.containerView.addSubview(self.trackView)
        self.captureContainerView.addSubview(self.containerView)
        self.captureContainerMaskView.addSubview(self.captureContainerView)
        self.addSubview(self.captureContainerMaskView)
        self.addSubview(self.knobView)
        
        self.addGestureRecognizer(self.panGestureRecognizer)
        self.addGestureRecognizer(self.tapGestureRecognizer)
        self.addGestureRecognizer(self.edgeTapGestureRecognizer)
        self.addGestureRecognizer(self.doubleTapGestureRecognizer)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        
        if self.bounds.isEmpty {
            return
        }
        
        self.captureContainerMaskView.frame = self.bounds
        self.captureContainerView.frame = self.captureContainerMaskView.bounds.insetBy(dx: -15, dy: -5)
        self.containerView.frame = self.captureContainerView.bounds.insetBy(dx: 15, dy: 5)
        self.trackView.frame = self.containerView.bounds
        
        let margin = internalMargin
        var totalLength = self.bounds.width - margin * 2
        var sideLength = self.bounds.height
        var vertical = false
        
        if self.bounds.width < self.bounds.height {
            totalLength = self.bounds.height - margin * 2
            sideLength = self.bounds.width
            vertical = true
        }
        
        var knobPosition = self.knobPadding
        if self.isTracking && self.positionsCount < 2 {
            knobPosition += self.knobDragCenter
        } else {
            knobPosition += self.centerPosition(
                for: self.value,
                totalLength: totalLength,
                knobWidth: self.knobSize.width,
                vertical: vertical
            )
        }
        knobPosition = max(self.knobPadding, min(knobPosition, self.knobPadding + totalLength))
        
        let knobFrame = CGRect(
            x: knobPosition - (self.knobSize.width / 2),
            y: (sideLength - self.knobSize.height) / 2,
            width: self.knobSize.width,
            height: self.knobSize.height
        )
        
        if self.bounds.width > self.bounds.height {
            self.knobView.frame = knobFrame
        } else {
            self.knobView.frame = CGRect(
                x: knobFrame.origin.y,
                y: knobFrame.origin.x,
                width: knobFrame.width,
                height: knobFrame.height
            )
        }
        
        self.trackView.setNeedsDisplay()
    }

    public func setValue(_ value: CGFloat, animated: Bool) {
        if self.lowerBoundValue > .ulpOfOne {
            self.value = min(max(self.lowerBoundValue, max(value, self.minimumValue)), self.maximumValue)
        } else {
            self.value = min(max(value, self.minimumValue), self.maximumValue)
        }
        self.setNeedsLayout()
    }

    public func increase() {
        self.value = min(self.maximumValue, self.value + 1)
        self.sendActions(for: .valueChanged)
        self.setNeedsLayout()
    }

    public func increaseBy(_ delta: CGFloat) {
        self.value = min(self.maximumValue, self.value + delta)
        self.sendActions(for: .valueChanged)
        self.setNeedsLayout()
    }

    public func decrease() {
        self.value = max(self.minimumValue, self.value - 1)
        self.sendActions(for: .valueChanged)
        self.setNeedsLayout()
    }

    public func decreaseBy(_ delta: CGFloat) {
        self.value = max(self.minimumValue, self.value - delta)
        self.sendActions(for: .valueChanged)
        self.setNeedsLayout()
    }

    func centerPosition(for value: CGFloat, totalLength: CGFloat, knobWidth: CGFloat, vertical: Bool) -> CGFloat {
        if self.minimumValue < 0 {
            if abs(self.minimumValue) > 1, Int(value) == 0 {
                return totalLength / 2
            } else if abs(value) < 0.01 {
                return totalLength / 2
            } else {
                let edgeValue = value > 0 ? self.maximumValue : self.minimumValue
                if (value < 0 && vertical) || (value > 0 && !vertical) {
                    return ((totalLength + knobWidth) / 2) + ((totalLength - knobWidth) / 2) * abs(value / edgeValue)
                } else {
                    return ((totalLength - knobWidth) / 2) * abs((edgeValue - self.value) / edgeValue)
                }
            }
        }
        var position = totalLength / (self.maximumValue - self.minimumValue) * (abs(self.minimumValue) + value)
        if vertical {
            position = totalLength - position
        }
        return position
    }

    private func value(for position: CGFloat, totalLength: CGFloat, knobSize: CGFloat, vertical: Bool) -> CGFloat {
        var result: CGFloat = 0
        if self.minimumValue < 0 {
            let knob = knobSize
            if position < (totalLength - knob) / 2 {
                var edgeValue = self.minimumValue
                if vertical {
                    edgeValue = self.maximumValue
                    result = 0
                }
                var pos = position
                if vertical {
                    pos *= -1
                }
                result = edgeValue + pos / ((totalLength - knob) / 2) * abs(edgeValue)
            } else if position >= (totalLength - knob) / 2 && position <= (totalLength + knob) / 2 {
                result = 0
            } else {
                let edgeValue: CGFloat = vertical ? self.minimumValue : self.maximumValue
                result = (position - ((totalLength + knob) / 2)) / ((totalLength - knob) / 2) * edgeValue
            }
        } else {
            result = self.minimumValue + (!vertical ? position : (totalLength - position)) / totalLength * (self.maximumValue - self.minimumValue)
        }
        return min(max(result, self.minimumValue), self.maximumValue)
    }
    
    private func updateTapAvailability() {
        self.tapGestureRecognizer.isEnabled = !self.disableSnapToPositions && self.positionsCount > 1
        self.doubleTapGestureRecognizer.isEnabled = !self.tapGestureRecognizer.isEnabled
    }
    
}

// MARK: - Gestures

extension LegacySliderView: UIGestureRecognizerDelegate {
    public override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === self.panGestureRecognizer {
            let velocity = self.panGestureRecognizer.velocity(in: self.panGestureRecognizer.view)
            return abs(velocity.x) > abs(velocity.y)
        }
        return true
    }
    
    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        
        self.isKnobTouched = false
        
        if self.isTouchLocationInKnob(location) {
            self.isKnobTouched = true
            self.knobView.interactionBegan(at: location)
        }

        if !self._isKnobTracking {
            self.handleBeginTracking(location)
        }
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        self.knobView.interactionEnded(shouldCompleteToPeak: self.isKnobTouched)
        self.isKnobTouched = false
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        self.knobView.interactionEnded()
        self.isKnobTouched = false
    }

    public override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        if !self.enablePanHandling {
            self.handleBeginTracking(touch.location(in: self))
        }
        return true
    }
    
    public override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        if !self.enablePanHandling {
            _ = self.handleContinueTracking(touch.location(in: self))
        }
        return true
    }

    public override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        if !self.enablePanHandling {
            self.handleEndTracking()
        }
    }

    public override func cancelTracking(with event: UIEvent?) {
        if !self.enablePanHandling {
            self.handleCancelTracking()
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            if !self._isKnobTracking {
                self.handleBeginTracking(gesture.location(in: self))
            }
        case .changed:
            _ = self.handleContinueTracking(gesture.location(in: self))
        case .ended:
            self.handleEndTracking()
        case .cancelled:
            self.handleCancelTracking()
        default:
            break
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let touchLocation = gesture.location(in: self)
        var totalLength = self.bounds.width
        var location = touchLocation.x
        
        if self.bounds.width < self.bounds.height {
            totalLength = self.bounds.height
            location = touchLocation.y
        }
        
        let position = (location / totalLength) * CGFloat(self.positionsCount - 1)
        let previousPosition = max(0, floor(position))
        let nextPosition = min(CGFloat(self.positionsCount - 1), ceil(position))
        
        var changed = false
        if abs(position - previousPosition) < 0.3 {
            self.setValue(previousPosition, animated: false)
            changed = true
        } else if abs(position - nextPosition) < 0.3 {
            self.setValue(nextPosition, animated: false)
            changed = true
        }
        
        if changed {
            self.interactionBegan?()
            self.setNeedsLayout()
            self.sendActions(for: .valueChanged)
            self.interactionEnded?()
            self.feedbackGenerator.selectionChanged()
            self.feedbackGenerator.prepare()
        }
    }

    @objc private func handleEdgeTap(_ gesture: UITapGestureRecognizer) {
        var changed = false
        if gesture.state == .ended {
            let touchLocation = gesture.location(in: self)
            let edgeWidth: CGFloat = 16
            if touchLocation.x < edgeWidth || touchLocation.x > bounds.width - edgeWidth {
                let knobRect = self.knobView.frame.insetBy(dx: -8, dy: -8)
                if !knobRect.contains(touchLocation) {
                    if touchLocation.x < edgeWidth {
                        self.setValue(minimumValue, animated: false)
                    } else {
                        self.setValue(maximumValue, animated: false)
                    }
                    changed = true
                }
            }
        }
        if changed {
            self.interactionBegan?()
            self.setNeedsLayout()
            self.sendActions(for: .valueChanged)
            self.interactionEnded?()
            self.feedbackGenerator.selectionChanged()
            self.feedbackGenerator.prepare()
        }
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        self.reset?()
    }

    private func handleBeginTracking(_ location: CGPoint) {
        if !isTouchLocationInKnob(location) {
            self._isKnobTracking = false
            return
        }
        
        self._isKnobTracking = true
        if self.bounds.width > self.bounds.height {
            self.knobTouchCenterStart = self.knobView.center.x
            self.knobTouchStart = location.x
            self.knobDragCenter = location.x
        } else {
            self.knobTouchCenterStart = self.knobView.center.y
            self.knobTouchStart = location.y
            self.knobDragCenter = location.y
        }
        self.knobStartedDragging = false
        self.feedbackGenerator.prepare()
        self.maybeCancelParentViewScrolling(self.superview, depth: 0)
    }

    @discardableResult
    private func handleContinueTracking(_ location: CGPoint) -> Bool {
        guard isTracking else { return false }
        
        if abs(location.x - self.knobTouchStart) > 1, !self.knobStartedDragging {
            self.knobStartedDragging = true
            self.interactionBegan?()
        }
        
        self.knobDragCenter = self.knobTouchCenterStart - self.knobTouchStart - self.knobPadding

        var totalLength = bounds.width
        var vertical = false
        
        if self.bounds.width > self.bounds.height {
            self.knobDragCenter += location.x
        } else {
            vertical = true
            totalLength = self.bounds.height
            self.knobDragCenter += location.y
        }
        
        totalLength -= self.knobPadding * 2
        let previousValue = self.value
        
        if self.positionsCount > 1 && !self.disableSnapToPositions {
            var position = Int(round((self.knobDragCenter / totalLength) * CGFloat(self.positionsCount - 1)))
            if self.lowerBoundValue > 0 {
                position = max(position, Int(self.lowerBoundValue))
            }
            self.knobDragCenter = CGFloat(position) * totalLength / CGFloat(self.positionsCount - 1)
        } else if self.lowerBoundValue > 0 {
            self.knobDragCenter = max(self.knobDragCenter, self.lowerBoundValue * totalLength)
        }
        
        self.setValue(value(for: self.knobDragCenter, totalLength: totalLength, knobSize: self.knobSize.width, vertical: vertical), animated: false)
        
        if previousValue != self.value && !self.disableSnapToPositions && (self.positionsCount > 1 || self.value == self.minimumValue || self.value == self.maximumValue || (self.minimumValue != self.startValue && self.value == self.startValue)) {
            self.feedbackGenerator.selectionChanged()
            self.feedbackGenerator.prepare()
        }
        
        self.setNeedsLayout()
        
        if !self.limitValueChangedToLatestState {
            self.sendActions(for: .valueChanged)
        }
        
        return true
    }

    private func handleEndTracking() {
        self._isKnobTracking = false
        self.knobStartedDragging = false
        self.sendActions(for: .valueChanged)
        self.setNeedsLayout()
        self.interactionEnded?()
    }

    private func handleCancelTracking() {
        self._isKnobTracking = false
        self.knobStartedDragging = false
        self.setNeedsLayout()
        self.interactionEnded?()
    }

    private func maybeCancelParentViewScrolling(_ parent: UIView?, depth: Int) {
        guard depth <= 5, let parent else { return }
        if let scrollView = parent as? UIScrollView {
            scrollView.isScrollEnabled = false
            scrollView.isScrollEnabled = true
        } else if let superview = parent.superview {
            self.maybeCancelParentViewScrolling(superview, depth: depth + 1)
        }
    }
    
    private func isTouchLocationInKnob(_ location: CGPoint) -> Bool {
        let hitFrame = self.knobView.frame.insetBy(dx: -self.knobTouchPadding, dy: -self.knobTouchPadding)
        return hitFrame.contains(location)
    }
}

private final class TrackView: UIView {
    weak var slider: LegacySliderView?
    
    override func draw(_ rect: CGRect) {
        guard let slider = self.slider, let context = UIGraphicsGetCurrentContext(), !rect.isEmpty else { return }
        
        let margin = internalMargin
        let visualMargin: CGFloat = slider.positionsCount > 1 ? margin : 2
        var totalLength = slider.bounds.width - margin * 2
        var visualTotalLength = slider.bounds.width - 2 * (slider.positionsCount > 1 ? margin : visualMargin)
        var sideLength = slider.bounds.height
        var vertical = false
        
        if slider.bounds.width < slider.bounds.height {
            totalLength = slider.bounds.height - margin * 2
            visualTotalLength = slider.bounds.height - 2 * (slider.positionsCount > 1 ? margin : visualMargin)
            sideLength = slider.bounds.width
            vertical = true
        }
        
        var knobPosition = slider.knobPadding
        if slider.isTracking {
            knobPosition += slider.knobDragCenter
        } else {
            knobPosition += slider.centerPosition(for: slider.value, totalLength: totalLength, knobWidth: slider.knobSize.width, vertical: vertical)
        }
        knobPosition = max(slider.knobPadding, min(knobPosition, slider.knobPadding + totalLength))

        let lowerBoundPosition = slider.knobPadding + slider.centerPosition(for: slider.lowerBoundValue, totalLength: totalLength, knobWidth: slider.knobSize.width, vertical: vertical)

        var startPosition = visualMargin + visualTotalLength / (slider.maximumValue - slider.minimumValue) * (abs(slider.minimumValue) + slider.startValue)
        if vertical {
            startPosition = 2 * visualMargin + visualTotalLength - startPosition
        }
        
        var endPosition = visualMargin + visualTotalLength / (slider.maximumValue - slider.minimumValue) * (abs(slider.minimumValue) + slider.maximumValue)
        if vertical {
            endPosition = 2 * visualMargin + visualTotalLength - endPosition
        }
        
        var origin = startPosition
        var track = knobPosition - startPosition
        
        if track < 0 {
            track = abs(track)
            origin -= track
        }
        
        var backFrame = CGRect(
            x: visualMargin,
            y: (sideLength - slider.lineSize) / 2,
            width: visualTotalLength,
            height: slider.lineSize
        )
        var trackFrame = CGRect(
            x: origin,
            y: (sideLength - slider.lineSize) / 2,
            width: track,
            height: slider.lineSize
        )
        var startFrame = CGRect(
            x: startPosition - 2,
            y: (sideLength - 12) / 2,
            width: 4,
            height: 12
        )
        var endFrame = CGRect(
            x: endPosition - 2,
            y: (sideLength - 12) / 2,
            width: 4,
            height: 12
        )
        var knobFrame = CGRect(
            x: knobPosition - slider.knobSize.width / 2,
            y: (sideLength - slider.knobSize.height) / 2,
            width: slider.knobSize.width,
            height: slider.knobSize.height
        )
        
        let rotatedFrame: ((CGRect) -> CGRect) = { rect in
            return CGRect(x: rect.origin.y, y: rect.origin.x, width: rect.size.height, height: rect.size.width)
        }

        if vertical {
            backFrame = rotatedFrame(backFrame)
            trackFrame = rotatedFrame(trackFrame)
            startFrame = rotatedFrame(startFrame)
            endFrame =  rotatedFrame(endFrame)
            knobFrame = rotatedFrame(knobFrame)
        }
        
        if slider.markValue > .ulpOfOne {
            context.setFillColor(slider.backColor.cgColor)
            drawRectangle(backFrame, cornerRadius: 0, in: context)
        }
        
        if slider.bordered {
            context.setFillColor(UIColor(white: 0, alpha: 0.6).cgColor)
            drawRectangle(backFrame.insetBy(dx: -1, dy: -1), cornerRadius: slider.trackCornerRadius * 2, in: context)
            if !slider.startHidden {
                drawRectangle(startFrame.insetBy(dx: -1, dy: -1), cornerRadius: slider.trackCornerRadius * 2, in: context)
            }
            context.setBlendMode(.copy)
        }
        
        for passIndex in 0..<2 {
            context.saveGState()
            context.resetClip()
            let passBackColor = slider.backColor
            var passTrackColor = slider.trackColor
            
            if passIndex == 0 {
                if slider.lowerBoundValue > 0, let lowerColor = slider.lowerBoundTrackColor {
                    context.beginPath()
                    context.addRect(CGRect(x: 0, y: 0, width: lowerBoundPosition, height: rect.height))
                    context.clip()
                    passTrackColor = lowerColor
                }
            } else {
                if slider.lowerBoundValue > 0, slider.lowerBoundTrackColor != nil, lowerBoundPosition < rect.width {
                    context.beginPath()
                    context.addRect(CGRect(
                        x: lowerBoundPosition,
                        y: 0,
                        width: rect.width - lowerBoundPosition,
                        height: rect.height
                    ))
                    context.clip()
                } else {
                    context.restoreGState()
                    break
                }
            }
            
            context.setFillColor(passBackColor.cgColor)
            drawRectangle(backFrame, cornerRadius: slider.trackCornerRadius, in: context)
            context.setBlendMode(.normal)
            context.setFillColor(passTrackColor.cgColor)
            drawRectangle(trackFrame, cornerRadius: slider.trackCornerRadius, in: context)
            
            if !slider.startHidden || slider.displayEdges {
                var highlighted = startFrame.midX < trackFrame.maxX
                if vertical {
                    highlighted = startFrame.midY > trackFrame.minY
                }
                highlighted = highlighted && slider.displayEdges
                context.setFillColor((highlighted ? passTrackColor : slider.startColor).cgColor)
                drawRectangle(startFrame, cornerRadius: slider.trackCornerRadius, in: context)
            }
            
            if slider.displayEdges {
                context.setFillColor(passBackColor.cgColor)
                drawRectangle(endFrame, cornerRadius: slider.trackCornerRadius, in: context)
            }
            
            if slider.bordered {
                context.setFillColor(UIColor(white: 0, alpha: 0.6).cgColor)
                context.fillEllipse(in: knobFrame.insetBy(dx: 1, dy: 1))
            }
            
            if slider.positionsCount > 1 {
                for i in 0..<slider.positionsCount {
                    if !slider.markPositions && i != 0 && i != slider.positionsCount - 1 {
                        continue
                    }
                    
                    if slider.useLinesForPositions {
                        let lineSize = CGSize(width: 4, height: 12)
                        var lineRect = CGRect(
                            x: margin - lineSize.width / 2 + totalLength / CGFloat(slider.positionsCount - 1) * CGFloat(i),
                            y: (sideLength - lineSize.height) / 2,
                            width: lineSize.width,
                            height: lineSize.height
                        )
                        if vertical {
                            lineRect = CGRect(
                                x: lineRect.origin.y,
                                y: lineRect.origin.x,
                                width: lineRect.height,
                                height: lineRect.width
                            )
                        }
                        
                        var highlighted = lineRect.midX < trackFrame.maxX
                        if vertical {
                            highlighted = lineRect.midY > trackFrame.minY
                        }
                        
                        context.setFillColor((highlighted ? passTrackColor : passBackColor).cgColor)
                        drawRectangle(lineRect, cornerRadius: slider.trackCornerRadius, in: context)
                    } else {
                        if slider.backgroundColor == .clear {
                            context.setBlendMode(.clear)
                            context.setFillColor(UIColor.clear.cgColor)
                        } else {
                            context.setFillColor((slider.backgroundColor ?? UIColor.clear).cgColor)
                        }
                        
                        let inset: CGFloat = 1.5
                        let outerSize = slider.dotSize + inset * 2
                        var dotRect = CGRect(
                            x: margin - outerSize / 2 + (totalLength / CGFloat(slider.positionsCount - 1)) * CGFloat(i),
                            y: (sideLength - outerSize) / 2,
                            width: outerSize,
                            height: outerSize
                        )

                        if vertical {
                            dotRect = CGRect(
                                x: dotRect.origin.y,
                                y: dotRect.origin.x,
                                width: dotRect.height,
                                height: dotRect.width
                            )
                        }
                        
                        context.fillEllipse(in: dotRect)
                        dotRect = dotRect.insetBy(dx: inset, dy: inset)
                        context.setBlendMode(.normal)
                        
                        var highlighted = dotRect.midX < trackFrame.maxX
                        if vertical {
                            highlighted = dotRect.midY > trackFrame.minY
                        }
                        
                        context.setFillColor((highlighted ? passTrackColor : passBackColor).cgColor)
                        context.fillEllipse(in: dotRect)
                    }
                }
            }
            context.restoreGState()
        }
    }
}

private func drawRectangle(_ rect: CGRect, cornerRadius: CGFloat, in context: CGContext) {
    if cornerRadius > .ulpOfOne {
        context.addPath(UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).cgPath)
        context.closePath()
        context.fillPath()
    } else {
        context.fill(rect)
    }
}
