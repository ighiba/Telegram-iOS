import Foundation
import UIKit
import Display
import AsyncDisplayKit
import TelegramPresentationData
import LegacyComponents
import ComponentFlow
import LegacyGlass

public protocol SliderViewProtocol: UIControl {
    var interactionBegan: (() -> Void)? { get set }
    var interactionEnded: (() -> Void)? { get set }
    
    var bordered: Bool { get set }
    var value: CGFloat { get set }
    var minimumValue: CGFloat { get set }
    var maximumValue: CGFloat { get set }
    var lowerBoundValue: CGFloat { get set }
    var lowerBoundTrackColor: UIColor? { get set }

    func setValue(_ value: CGFloat, animated: Bool)
}

extension LegacySliderView: SliderViewProtocol {
    
}

public final class SliderComponent: Component {
    public final class Discrete: Equatable {
        public let valueCount: Int
        public let value: Int
        public let minValue: Int?
        public let markPositions: Bool
        public let valueUpdated: (Int) -> Void
        
        public init(valueCount: Int, value: Int, minValue: Int? = nil, markPositions: Bool, valueUpdated: @escaping (Int) -> Void) {
            self.valueCount = valueCount
            self.value = value
            self.minValue = minValue
            self.markPositions = markPositions
            self.valueUpdated = valueUpdated
        }
        
        public static func ==(lhs: Discrete, rhs: Discrete) -> Bool {
            if lhs.valueCount != rhs.valueCount {
                return false
            }
            if lhs.value != rhs.value {
                return false
            }
            if lhs.minValue != rhs.minValue {
                return false
            }
            if lhs.markPositions != rhs.markPositions {
                return false
            }
            return true
        }
    }
    
    public final class Continuous: Equatable {
        public let value: CGFloat
        public let minValue: CGFloat?
        public let valueUpdated: (CGFloat) -> Void
        
        public init(value: CGFloat, minValue: CGFloat? = nil, valueUpdated: @escaping (CGFloat) -> Void) {
            self.value = value
            self.minValue = minValue
            self.valueUpdated = valueUpdated
        }
        
        public static func ==(lhs: Continuous, rhs: Continuous) -> Bool {
            if lhs.value != rhs.value {
                return false
            }
            if lhs.minValue != rhs.minValue {
                return false
            }
            return true
        }
    }
    
    public enum Content: Equatable {
        case discrete(Discrete)
        case continuous(Continuous)
    }
    
    public let content: Content
    public let useNative: Bool
    public let backgroundColor: UIColor
    public let trackBackgroundColor: UIColor
    public let trackForegroundColor: UIColor
    public let minTrackForegroundColor: UIColor?
    public let knobSize: CGFloat?
    public let knobColor: UIColor?
    public let isTrackingUpdated: ((Bool) -> Void)?
    
    public init(
        content: Content,
        useNative: Bool = false,
        backgroundColor: UIColor,
        trackBackgroundColor: UIColor,
        trackForegroundColor: UIColor,
        minTrackForegroundColor: UIColor? = nil,
        knobSize: CGFloat? = nil,
        knobColor: UIColor? = nil,
        isTrackingUpdated: ((Bool) -> Void)? = nil
    ) {
        self.content = content
        self.useNative = useNative
        self.backgroundColor = backgroundColor
        self.trackBackgroundColor = trackBackgroundColor
        self.trackForegroundColor = trackForegroundColor
        self.minTrackForegroundColor = minTrackForegroundColor
        self.knobSize = knobSize
        self.knobColor = knobColor
        self.isTrackingUpdated = isTrackingUpdated
    }
    
    public static func ==(lhs: SliderComponent, rhs: SliderComponent) -> Bool {
        if lhs.content != rhs.content {
            return false
        }
        if lhs.trackBackgroundColor != rhs.trackBackgroundColor {
            return false
        }
        if lhs.trackForegroundColor != rhs.trackForegroundColor {
            return false
        }
        if lhs.minTrackForegroundColor != rhs.minTrackForegroundColor {
            return false
        }
        if lhs.knobSize != rhs.knobSize {
            return false
        }
        if lhs.knobColor != rhs.knobColor {
            return false
        }
        return true
    }
    
    final class SliderView: UISlider {
        
    }
    
    public final class View: UIView {
        private var nativeSliderView: SliderView?
        private var sliderView: SliderViewProtocol?
        
        private var component: SliderComponent?
        private weak var state: EmptyComponentState?
        
        public var hitTestTarget: UIView? {
            return self.sliderView
        }
        
        override public init(frame: CGRect) {
            super.init(frame: frame)
        }
        
        required public init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
                
        public func cancelGestures() {
            if let sliderView = self.sliderView, let gestureRecognizers = sliderView.gestureRecognizers {
                for gestureRecognizer in gestureRecognizers {
                    if gestureRecognizer.isEnabled {
                        gestureRecognizer.isEnabled = false
                        gestureRecognizer.isEnabled = true
                    }
                }
            }
        }
        
        func update(component: SliderComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
            self.component = component
            self.state = state
            
            let size = CGSize(width: availableSize.width, height: 44.0)
            
            if #available(iOS 26.0, *), component.useNative {
                let sliderView: SliderView
                if let current = self.nativeSliderView {
                    sliderView = current
                } else {
                    sliderView = SliderView()
                    sliderView.disablesInteractiveTransitionGestureRecognizer = true
                    sliderView.addTarget(self, action: #selector(self.sliderValueChanged), for: .valueChanged)
                    sliderView.layer.allowsGroupOpacity = true
                    
                    self.addSubview(sliderView)
                    self.nativeSliderView = sliderView
                    
                    switch component.content {
                    case let .continuous(continuous):
                        sliderView.minimumValue = Float(continuous.minValue ?? 0.0)
                        sliderView.maximumValue = 1.0
                    case let .discrete(discrete):
                        sliderView.minimumValue = 0.0
                        sliderView.maximumValue = Float(discrete.valueCount - 1)
                        sliderView.trackConfiguration = .init(numberOfTicks: discrete.valueCount)
                    }
                }
                switch component.content {
                case let .continuous(continuous):
                    sliderView.value = Float(continuous.value)
                case let .discrete(discrete):
                    sliderView.value = Float(discrete.value)
                }
                sliderView.minimumTrackTintColor = component.trackForegroundColor
                sliderView.maximumTrackTintColor = component.trackBackgroundColor
                
                transition.setFrame(view: sliderView, frame: CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: CGSize(width: availableSize.width, height: 44.0)))
            } else {
                var internalIsTrackingUpdated: ((Bool) -> Void)?
                if let isTrackingUpdated = component.isTrackingUpdated {
                    internalIsTrackingUpdated = { [weak self] isTracking in
                        if let self {
                            if !"".isEmpty {
                                if isTracking {
                                    self.sliderView?.bordered = true
                                } else {
                                    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.1, execute: { [weak self] in
                                        self?.sliderView?.bordered = false
                                    })
                                }
                            }
                        }
                        isTrackingUpdated(isTracking)
                    }
                }
                
                let sliderView: SliderViewProtocol
                if let current = self.sliderView {
                    sliderView = current
                } else {
                    let legacySliderView = LegacySliderView()
                    legacySliderView.enablePanHandling = true
                    if let knobSize = component.knobSize {
                        legacySliderView.lineSize = knobSize + 4.0
                    } else {
                        legacySliderView.lineSize = 4.0
                    }
                    legacySliderView.trackCornerRadius = legacySliderView.lineSize * 0.5
                    legacySliderView.dotSize = 5.0
                    legacySliderView.minimumValue = 0.0
                    legacySliderView.startValue = 0.0
                    legacySliderView.disablesInteractiveTransitionGestureRecognizer = true
                    
                    switch component.content {
                    case let .discrete(discrete):
                        legacySliderView.maximumValue = CGFloat(discrete.valueCount - 1)
                        legacySliderView.positionsCount = discrete.valueCount
                        legacySliderView.useLinesForPositions = false
                        legacySliderView.markPositions = discrete.markPositions
                    case .continuous:
                        legacySliderView.maximumValue = 1.0
                    }
                    
                    legacySliderView.isOpaque = false
                    legacySliderView.backgroundColor = component.backgroundColor
                    legacySliderView.backColor = component.trackBackgroundColor
                    legacySliderView.startColor = component.trackBackgroundColor
                    legacySliderView.trackColor = component.trackForegroundColor
                    
                    legacySliderView.frame = CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: size)
                    legacySliderView.hitTestEdgeInsets = UIEdgeInsets(top: -legacySliderView.frame.minX, left: 0.0, bottom: 0.0, right: -legacySliderView.frame.minX)
                    
                    legacySliderView.disablesInteractiveTransitionGestureRecognizer = true
                    legacySliderView.addTarget(self, action: #selector(self.sliderValueChanged), for: .valueChanged)
                    legacySliderView.layer.allowsGroupOpacity = true
                    sliderView = legacySliderView
                    self.addSubview(legacySliderView)
                }
                
                self.sliderView = sliderView
                
                sliderView.lowerBoundTrackColor = component.minTrackForegroundColor
                switch component.content {
                case let .discrete(discrete):
                    sliderView.value = CGFloat(discrete.value)
                    if let minValue = discrete.minValue {
                        sliderView.lowerBoundValue = CGFloat(minValue)
                    } else {
                        sliderView.lowerBoundValue = 0.0
                    }
                case let .continuous(continuous):
                    sliderView.value = continuous.value
                    if let minValue = continuous.minValue {
                        sliderView.lowerBoundValue = minValue
                    } else {
                        sliderView.lowerBoundValue = 0.0
                    }
                }
                sliderView.interactionBegan = {
                    internalIsTrackingUpdated?(true)
                }
                sliderView.interactionEnded = {
                    internalIsTrackingUpdated?(false)
                }
                
                var sliderFrame =  CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: CGSize(width: availableSize.width, height: 44.0))
                if let _ = sliderView as? LegacySliderView {
                    sliderFrame = sliderFrame.insetBy(dx: 7, dy: 0)
                }
                
                transition.setFrame(view: sliderView, frame: sliderFrame)
                sliderView.hitTestEdgeInsets = UIEdgeInsets(top: 0.0, left: 0.0, bottom: 0.0, right: 0.0)
            }
            
            return size
        }
        
        @objc private func sliderValueChanged() {
            guard let component = self.component else {
                return
            }
            let floatValue: CGFloat
            if let sliderView = self.sliderView {
                floatValue = sliderView.value
            } else if let nativeSliderView = self.nativeSliderView {
                floatValue = CGFloat(nativeSliderView.value)
            } else {
                return
            }
            switch component.content {
            case let .discrete(discrete):
                discrete.valueUpdated(Int(floatValue))
            case let .continuous(continuous):
                continuous.valueUpdated(floatValue)
            }
        }
    }

    public func makeView() -> View {
        return View(frame: CGRect())
    }
    
    public func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}
