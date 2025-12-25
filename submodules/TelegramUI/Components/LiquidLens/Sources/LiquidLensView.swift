import Foundation
import UIKit
import Display
import ComponentFlow
import GlassBackgroundComponent
import LegacyGlass

private final class RestingBackgroundView: UIVisualEffectView {
    var isDark: Bool?

    static func colorMatrix(isDark: Bool) -> [Float32] {
        if isDark {
            return [1.082, -0.113, -0.011, 0.0, 0.135, -0.034, 1.003, -0.011, 0.0, 0.135, -0.034, -0.113, 1.105, 0.0, 0.135, 0.0, 0.0, 0.0, 1.0, 0.0]
        } else {
            return [1.185, -0.05, -0.005, 0.0, -0.2, -0.015, 1.15, -0.005, 0.0, -0.2, -0.015, -0.05, 1.195, 0.0, -0.2, 0.0, 0.0, 0.0, 1.0, 0.0]
        }
    }

    init() {
        let effect = UIBlurEffect(style: .light)
        super.init(effect: effect)
        
        for subview in self.subviews {
            if subview.description.contains("VisualEffectSubview") {
                subview.isHidden = true
            }
        }
        
        self.clipsToBounds = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(isDark: Bool) {
        if self.isDark == isDark {
            return
        }
        self.isDark = isDark
        
        if let sublayer = self.layer.sublayers?[0], let _ = sublayer.filters {
            sublayer.backgroundColor = nil
            sublayer.isOpaque = false
            
            if let classValue = NSClassFromString("CAFilter") as AnyObject as? NSObjectProtocol {
                let makeSelector = NSSelectorFromString("filterWithName:")
                let filter = classValue.perform(makeSelector, with: "colorMatrix").takeUnretainedValue() as? NSObject
                
                if let filter {
                    var matrix: [Float32] = RestingBackgroundView.colorMatrix(isDark: isDark)
                    filter.setValue(NSValue(bytes: &matrix, objCType: "{CAColorMatrix=ffffffffffffffffffff}"), forKey: "inputColorMatrix")
                    sublayer.filters = [filter]
                    sublayer.setValue(1.0, forKey: "scale")
                }
            }
        }
    }
}

public final class LiquidLensView: UIView {
    private struct Params: Equatable {
        var size: CGSize
        var selectionX: CGFloat
        var selectionWidth: CGFloat
        var isDark: Bool
        var isLifted: Bool

        init(size: CGSize, selectionX: CGFloat, selectionWidth: CGFloat, isDark: Bool, isLifted: Bool) {
            self.size = size
            self.selectionX = selectionX
            self.selectionWidth = selectionWidth
            self.isLifted = isLifted
            self.isDark = isDark
        }
    }

    private struct LensParams: Equatable {
        var baseFrame: CGRect
        var isLifted: Bool

        init(baseFrame: CGRect, isLifted: Bool) {
            self.baseFrame = baseFrame
            self.isLifted = isLifted
        }
    }

    public let contentView: UIView
    private let containerView: UIView
    private let backgroundContainerContainer: UIView
    private let backgroundContainer: GlassBackgroundContainerView
    private let backgroundView: GlassBackgroundView
    
    private var lensView: UIView?
    private var legacyLensView: LegacyGlassView?
    
    private let liftedContainerView: UIView
    
    private let restingBackgroundView: RestingBackgroundView
    
    private var legacyLiftedContainerMaskView: UIView?
    private var legacySelectionView: GlassBackgroundView.ContentImageView?
    private var legacyLastCroppedRect: CGRect?
    private var legacyLastCroppedOriginInLens: CGPoint?

    public var selectedContentView: UIView {
        return self.liftedContainerView
    }
    
    private var isUpdatedForTheFirstTime: Bool = false

    private var params: Params?
    private var appliedLensParams: LensParams?
    private var isApplyingLensParams: Bool = false
    private var pendingLensParams: LensParams?
    private var lastUpdatedParams: Params?

    private var liftedDisplayLink: SharedDisplayLinkDriver.Link?
    private var lensXAnimator: DisplayLinkAnimator?

    public var selectionX: CGFloat? {
        return self.params?.selectionX
    }

    public var selectionWidth: CGFloat? {
        return self.params?.selectionWidth
    }

    override public init(frame: CGRect) {
        self.containerView = UIView()
        
        self.backgroundContainerContainer = UIView()
        self.backgroundContainer = GlassBackgroundContainerView()
        
        self.backgroundView = GlassBackgroundView()
        
        self.contentView = UIView()
        self.liftedContainerView = UIView()

        self.restingBackgroundView = RestingBackgroundView()

        super.init(frame: frame)
        
        self.backgroundContainerContainer.addSubview(self.backgroundContainer)
        self.addSubview(self.backgroundContainerContainer)
        
        self.backgroundContainer.contentView.addSubview(self.backgroundView)
        self.backgroundView.contentView.addSubview(self.containerView)
        self.containerView.isUserInteractionEnabled = false
        
        if #available(iOS 26.0, *) {
            if let viewClass = NSClassFromString("_UILiquidLensView") as AnyObject as? NSObjectProtocol {
                let allocSelector = NSSelectorFromString("alloc")
                let initSelector = NSSelectorFromString("initWithRestingBackground:")
                let objcAlloc = viewClass.perform(allocSelector).takeUnretainedValue()
                let instance = objcAlloc.perform(initSelector, with: UIView()).takeUnretainedValue()
                self.lensView = instance as? UIView
            }
        }
        
        if let lensView = self.lensView {
            self.backgroundContainer.layer.zPosition = 1
            lensView.layer.zPosition = 10.0
            
            self.liftedContainerView.addSubview(self.restingBackgroundView)
            
            self.containerView.addSubview(self.liftedContainerView)
            self.containerView.addSubview(lensView)
            self.containerView.addSubview(self.contentView)
            
            lensView.perform(NSSelectorFromString("setLiftedContainerView:"), with: self.backgroundContainer.contentView)
            lensView.perform(NSSelectorFromString("setLiftedContentView:"), with: self.liftedContainerView)
            lensView.perform(NSSelectorFromString("setOverridePunchoutView:"), with: self.contentView)
            
            do {
                let selector = NSSelectorFromString("setLiftedContentMode:")
                if let method = lensView.method(for: selector) {
                    typealias ObjCMethod = @convention(c) (AnyObject, Selector, Int32) -> Void
                    let function = unsafeBitCast(method, to: ObjCMethod.self)
                    function(lensView, selector, 1)
                }
            }
            
            do {
                let selector = NSSelectorFromString("setStyle:")
                if let method = lensView.method(for: selector) {
                    typealias ObjCMethod = @convention(c) (AnyObject, Selector, Int32) -> Void
                    let function = unsafeBitCast(method, to: ObjCMethod.self)
                    function(lensView, selector, 1)
                }
            }
            
            do {
                let selector = NSSelectorFromString("setWarpsContentBelow:")
                if let method = lensView.method(for: selector) {
                    typealias ObjCMethod = @convention(c) (AnyObject, Selector, Bool) -> Void
                    let function = unsafeBitCast(method, to: ObjCMethod.self)
                    function(lensView, selector, true)
                }
            }
            
            lensView.setValue(UIColor(white: 0.0, alpha: 0.1), forKey: "restingBackgroundColor")
        } else {
            let legacyLensView = LegacyGlassView(style: .lens, qualityProfile: .automatic, allowsGroupSnapshotting: true)
            legacyLensView.alpha = 0.0
            legacyLensView.isUserInteractionEnabled = false
            legacyLensView.fillColor = .clear
            legacyLensView.autoUpdatesOnScroll = true
            legacyLensView.isSafeBoundsCaptureEnabled = false
            legacyLensView.isActivationEnabled = true
            legacyLensView.isScalingEnabled = true
            legacyLensView.isJellyEnabled = true
            legacyLensView.horizontalPadding = 30
            legacyLensView.verticalPadding = 30
            legacyLensView.interactionScaleMax = 1.35
            legacyLensView.interactionJellyDirection = .vertical
            legacyLensView.interactionScaleUpDuration = 0.2
            legacyLensView.interactionScaleDownDuration = 0.2
            legacyLensView.interactionActivationUpDuration = 0.2
            legacyLensView.interactionActivationDownDuration = 0.2
            self.legacyLensView = legacyLensView

            if let backgroundLegacyGlassView = self.backgroundView.legacyGlassView {
                backgroundLegacyGlassView.isScalingEnabled = true
                backgroundLegacyGlassView.isGlowEnabled = true
                backgroundLegacyGlassView.horizontalPadding = 10
                backgroundLegacyGlassView.verticalPadding = 10
                backgroundLegacyGlassView.interactionScaleMax = 1.03
                backgroundLegacyGlassView.interactionScaleUpDuration = 0.4
                backgroundLegacyGlassView.interactionScaleDownDuration = 0.4
                backgroundLegacyGlassView.setStyle(.largeBackground)
                
                backgroundLegacyGlassView.updateQualityProfile { qualityProfile in
                    qualityProfile.captureScaleBlurred = legacyLensView.qualityProfile.captureScale
                }
                
                backgroundLegacyGlassView.setBlurFilterSigma(value: 4.5)
            }

            let legacyLiftedContainerMaskView = UIView()
            legacyLiftedContainerMaskView.clipsToBounds = true
            self.legacyLiftedContainerMaskView = legacyLiftedContainerMaskView

            let legacySelectionView = GlassBackgroundView.ContentImageView()
            self.legacySelectionView = legacySelectionView

            legacyLiftedContainerMaskView.addSubview(legacySelectionView)
            legacyLiftedContainerMaskView.addSubview(self.liftedContainerView)
            self.containerView.addSubview(self.contentView)
            self.containerView.addSubview(legacyLiftedContainerMaskView)
            self.containerView.addSubview(legacyLensView)
            
            legacyLensView.willActivate = { [weak legacyLensView] duration in
                UIView.animate(withDuration: 0.1, delay: 0, options: [.beginFromCurrentState]) {
                    legacyLensView?.alpha = 1.0
                }
            }
            legacyLensView.willDeactivate = { [weak legacyLensView] duration in
                let targetDuration = 0.1
                let delay = min(duration, max(0.0, duration - targetDuration))
                UIView.animate(withDuration: targetDuration, delay: delay, options: [.beginFromCurrentState]) {
                    legacyLensView?.alpha = 0.0
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("TabBarControllerASDisplayViewChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let captureView = notification.object as? UIView, let strongSelf = self {
                strongSelf.setCaptureHostView(captureView)
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        self.lensXAnimator?.invalidate()
    }
    
    override public func didMoveToWindow() {
        super.didMoveToWindow()
        
        if self.window == nil {
            self.legacyLensView?.setAdditionalFrontImage(nil, atOrigin: .zero)
        } else if let croppedRect = self.legacyLastCroppedRect, let croppedOriginInLens = self.legacyLastCroppedOriginInLens {
            DispatchQueue.main.async {
                self.updateLegacyLensFrontImage(inRect: croppedRect, croppedOriginInLens: croppedOriginInLens)
            }
        }
    }
    
    public func interactionBegan(at point: CGPoint) {
        self.backgroundView.interactionBegan(at: point)
    }
    
    public func interactionUpdate(at point: CGPoint) {
        self.backgroundView.interactionUpdate(at: point)
    }

    public func interactionEnded(shouldCompleteToPeak: Bool = false) {
        self.backgroundView.interactionEnded(shouldCompleteToPeak: shouldCompleteToPeak)
    }

    public func setCaptureHostView(_ view: UIView) {
        self.legacyLensView?.setCaptureHostView(view)
        self.backgroundView.setCaptureHostView(view)
    }

    public func update(size: CGSize, selectionX: CGFloat, selectionWidth: CGFloat, isDark: Bool, isLifted: Bool, transition: ComponentTransition) {
        let params = Params(size: size, selectionX: selectionX, selectionWidth: selectionWidth, isDark: isDark, isLifted: isLifted)
        if self.params == params {
            return
        }
        self.update(params: params, transition: transition)
    }

    private func update(transition: ComponentTransition) {
        guard let params = self.params else {
            return
        }
        self.update(params: params, transition: transition)
    }

    private func updateLens(params: LensParams, animated: Bool) {
        guard let lensView = self.lensView else {
            return
        }

        if self.isApplyingLensParams {
            self.pendingLensParams = params
            return
        }
        self.isApplyingLensParams = true
        let previousParams = self.appliedLensParams

        let transition: ComponentTransition = animated ? .easeInOut(duration: 0.3) : .immediate

        if previousParams?.isLifted != params.isLifted {
            let selector = NSSelectorFromString("setLifted:animated:alongsideAnimations:completion:")
            var shouldScheduleUpdate = false
            var didProcessUpdate = false
            self.pendingLensParams = params
            if let lensView = self.lensView, let method = lensView.method(for: selector) {
                typealias ObjCMethod = @convention(c) (AnyObject, Selector, Bool, Bool, @escaping () -> Void, AnyObject?) -> Void
                let function = unsafeBitCast(method, to: ObjCMethod.self)
                function(lensView, selector, params.isLifted, !transition.animation.isImmediate, { [weak self] in
                    guard let self else {
                        return
                    }
                    let liftedInset: CGFloat = params.isLifted ? 4.0 : -4.0
                    lensView.bounds = CGRect(origin: CGPoint(), size: CGSize(width: params.baseFrame.width + liftedInset * 2.0, height: params.baseFrame.height + liftedInset * 2.0))
                    didProcessUpdate = true
                    if shouldScheduleUpdate {
                        DispatchQueue.main.async { [weak self] in
                            guard let self, let pendingLensParams = self.pendingLensParams else {
                                return
                            }
                            self.isApplyingLensParams = false
                            self.pendingLensParams = nil
                            self.updateLens(params: pendingLensParams, animated: !transition.animation.isImmediate)
                        }
                    }
                }, nil)
            }
            if didProcessUpdate {
                transition.animateView {
                    lensView.center = CGPoint(x: params.baseFrame.midX, y: params.baseFrame.midY)
                }
                self.pendingLensParams = nil
                self.isApplyingLensParams = false
            } else {
                shouldScheduleUpdate = true
            }
        } else {
            transition.animateView {
                let liftedInset: CGFloat = params.isLifted ? 4.0 : -4.0
                lensView.bounds = CGRect(origin: CGPoint(), size: CGSize(width: params.baseFrame.width + liftedInset * 2.0, height: params.baseFrame.height + liftedInset * 2.0))
                lensView.center = CGPoint(x: params.baseFrame.midX, y: params.baseFrame.midY)
            }
            self.isApplyingLensParams = false
        }
    }

    private func updateLiftedLensPosition() {
        // Without this, the lens won't update its bouncing animations unless it's being moved
        if self.isApplyingLensParams {
            return
        }
        guard let lensView = self.lensView else {
            return
        }
        guard let params = self.appliedLensParams else {
            return
        }
        lensView.center = CGPoint(x: params.baseFrame.midX, y: params.baseFrame.midY)
    }

    private func update(params: Params, transition: ComponentTransition) {
        let isFirstTime = self.params == nil
        let transition: ComponentTransition = isFirstTime ? .immediate : transition

        self.lastUpdatedParams = self.params
        self.params = params

        transition.setFrame(view: self.containerView, frame: CGRect(origin: CGPoint(), size: params.size))
        transition.setFrame(view: self.backgroundContainerContainer, frame: CGRect(origin: CGPoint(), size: params.size))

        transition.setFrame(view: self.backgroundContainer, frame: CGRect(origin: CGPoint(), size: params.size))
        self.backgroundContainer.update(size: params.size, isDark: params.isDark, transition: transition)
        
        transition.setFrame(view: self.backgroundView, frame: CGRect(origin: CGPoint(), size: params.size))
        self.backgroundView.update(size: params.size, cornerRadius: params.size.height * 0.5, isDark: params.isDark, tintColor: GlassBackgroundView.TintColor.init(kind: .panel, color: UIColor(white: params.isDark ? 0.0 : 1.0, alpha: 0.6)), isInteractive: true, transition: transition)
        
        transition.setFrame(view: self.contentView, frame: CGRect(origin: CGPoint(), size: params.size))
        
        let baseLensFrame = CGRect(origin: CGPoint(x: max(0.0, min(params.selectionX, params.size.width - params.selectionWidth)), y: 0.0), size: CGSize(width: params.selectionWidth, height: params.size.height))
        self.updateLens(params: LensParams(baseFrame: baseLensFrame, isLifted: params.isLifted), animated: !transition.animation.isImmediate)
        
        if let _ = self.lensView {
            transition.setFrame(view: self.liftedContainerView, frame: CGRect(origin: CGPoint(), size: params.size))
        }
        
        if let legacyLiftedContainerMaskView = self.legacyLiftedContainerMaskView,  let legacySelectionView = self.legacySelectionView {
            let maskFrame = baseLensFrame
            let containerSize = CGSize(width: params.size.width, height: params.size.height)
            let containerFrame = CGRect(origin: CGPoint(x: -baseLensFrame.origin.x, y: -baseLensFrame.origin.y), size: containerSize)

            let lensInset: CGFloat = 4.0
            let lensFrame = baseLensFrame.insetBy(dx: lensInset, dy: lensInset)
            let lensFrameInMask = CGRect(x: lensInset, y: lensInset, width: maskFrame.width - lensInset * 2.0, height: maskFrame.height - lensInset * 2.0)
            let selectionFrame = lensFrameInMask.insetBy(dx: params.isLifted ? -2.0 : 0.0, dy: params.isLifted ? -2.0 : 0.0)
            
            if legacySelectionView.image?.size.height != lensFrame.height {
                legacySelectionView.image = generateStretchableFilledCircleImage(diameter: lensFrame.height, color: .white)?.withRenderingMode(.alwaysTemplate)
            }
            legacySelectionView.tintColor = UIColor(white: params.isDark ? 1.0 : 0.0, alpha: params.isDark ? 0.1 : 0.075)
            
            legacyLiftedContainerMaskView.layer.cornerRadius = maskFrame.height * 0.5
            
            if let legacyLensView = self.legacyLensView {
                if transition.animation.isImmediate {
                    if self.lensXAnimator != nil {
                        self.lensXAnimator?.invalidate()
                        self.lensXAnimator = nil
                    }
                    
                    transition.setFrame(view: legacyLensView, frame: lensFrame)
                    
                    transition.setFrame(view: legacyLiftedContainerMaskView, frame: maskFrame)
                    transition.setFrame(view: self.liftedContainerView, frame: containerFrame)
                    transition.setFrame(view: legacySelectionView, frame: selectionFrame)
                    
                } else if self.lensXAnimator == nil {
                    self.lensXAnimator?.invalidate()
                    
                    let currentX = legacyLensView.frame.origin.x
                    let targetX = lensFrame.origin.x
                    let currentY = legacyLensView.frame.origin.y
                    let currentWidth = legacyLensView.frame.width
                    let currentHeight = legacyLensView.frame.height
                    let deltaX = targetX - currentX
                    
                    let currentMaskFrame = legacyLiftedContainerMaskView.frame
                    let currentMaskX = currentMaskFrame.origin.x
                    let targetMaskX = maskFrame.origin.x
                    let maskDeltaX = targetMaskX - currentMaskX
                    
                    let currentContainerFrame = self.liftedContainerView.frame
                    let currentContainerX = currentContainerFrame.origin.x
                    let targetContainerX = containerFrame.origin.x
                    let containerDeltaX = targetContainerX - currentContainerX
                    
                    let isLifted = params.isLifted
                    
                    let bounds = self.liftedContainerView.bounds
                    let horizontalInset: CGFloat = 10.0
                    let verticalInset: CGFloat = 5.0
                    let croppedRect = CGRect(
                        x: horizontalInset,
                        y: verticalInset,
                        width: bounds.width - horizontalInset * 2.0,
                        height: bounds.height - verticalInset * 2.0
                    )
                    let croppedOriginInLiftedContainer = CGPoint(x: croppedRect.origin.x, y: croppedRect.origin.y)
                    let hasAdditionalFrontImage = legacyLensView.hasAdditionalFrontImage

                    self.lensXAnimator = DisplayLinkAnimator(
                        duration: 0.4,
                        from: currentX,
                        to: targetX,
                        update: { [weak self] x in
                            guard let strongSelf = self else { return }
                            guard
                                let legacyLensView = strongSelf.legacyLensView,
                                let legacyLiftedContainerMaskView = strongSelf.legacyLiftedContainerMaskView,
                                let legacySelectionView = strongSelf.legacySelectionView
                            else {
                                return
                            }
                            
                            let progress = abs(deltaX) > 0.0001 ? (x - currentX) / deltaX : 0.0
                            let clampedProgress = min(max(progress, 0.0), 1.0)
                            let easedProgress = 1.0 - pow(1.0 - clampedProgress, 3.0)
                            
                            let easedX = currentX + deltaX * easedProgress
                            legacyLensView.frame = CGRect(
                                origin: CGPoint(x: easedX, y: currentY),
                                size: CGSize(width: currentWidth, height: currentHeight)
                            )
                            
                            let easedMaskX = currentMaskX + maskDeltaX * easedProgress
                            legacyLiftedContainerMaskView.frame = CGRect(
                                origin: CGPoint(x: easedMaskX, y: currentMaskFrame.origin.y),
                                size: maskFrame.size
                            )
                            
                            let easedContainerX = currentContainerX + containerDeltaX * easedProgress
                            strongSelf.liftedContainerView.frame = CGRect(
                                origin: CGPoint(x: easedContainerX, y: currentContainerFrame.origin.y),
                                size: containerFrame.size
                            )
                            
                            let lensFrameInMaskEased = legacyLiftedContainerMaskView.bounds.insetBy(dx: 4.0, dy: 4.0)
                            let selectionFrameEased = lensFrameInMaskEased.insetBy(dx: isLifted ? -2.0 : 0.0, dy: isLifted ? -2.0 : 0.0)
                            legacySelectionView.frame = selectionFrameEased
                            
                            if hasAdditionalFrontImage {
                                let croppedOriginInLens = strongSelf.liftedContainerView.convert(croppedOriginInLiftedContainer, to: legacyLensView)
                                legacyLensView.updateAdditionalFrontImageOrigin(at: croppedOriginInLens)
                            }
                        },
                        completion: { [weak self] in
                            guard let strongSelf = self else { return }
                            guard
                                let legacyLensView = strongSelf.legacyLensView,
                                let legacyLiftedContainerMaskView = strongSelf.legacyLiftedContainerMaskView,
                                let legacySelectionView = strongSelf.legacySelectionView
                            else {
                                return
                            }
                            
                            legacyLensView.frame = CGRect(
                                origin: CGPoint(x: targetX, y: currentY),
                                size: CGSize(width: currentWidth, height: currentHeight)
                            )
                            
                            legacyLiftedContainerMaskView.frame = maskFrame
                            strongSelf.liftedContainerView.frame = containerFrame
                            legacySelectionView.frame = selectionFrame
                            
                            if hasAdditionalFrontImage {
                                let croppedOriginInLens = strongSelf.liftedContainerView.convert(croppedOriginInLiftedContainer, to: legacyLensView)
                                legacyLensView.updateAdditionalFrontImageOrigin(at: croppedOriginInLens)
                            }
                            
                            strongSelf.lensXAnimator = nil
                        }
                    )
                }

                legacyLensView.cornerRadius = lensFrame.height * 0.5
                
                let bounds = self.liftedContainerView.bounds
                guard !bounds.isEmpty else {
                    return
                }

                let horizontalInset: CGFloat = 10.0
                let verticalInset: CGFloat = 5.0
                let croppedRect = CGRect(
                    x: horizontalInset,
                    y: verticalInset,
                    width: bounds.width - horizontalInset * 2.0,
                    height: bounds.height - verticalInset * 2.0
                )

                let croppedOriginInLiftedContainer = CGPoint(x: croppedRect.origin.x, y: croppedRect.origin.y)
                let croppedOriginInLens = self.liftedContainerView.convert(croppedOriginInLiftedContainer, to: legacyLensView)

                var isFrontImageValid: Bool = legacyLensView.hasAdditionalFrontImage
                if let lastUpdatedParams = self.lastUpdatedParams {
                    let isSizeSame = lastUpdatedParams.size == params.size
                    let isThemeSame = lastUpdatedParams.isDark == params.isDark
                    isFrontImageValid = isSizeSame && isThemeSame && legacyLensView.hasAdditionalFrontImage
                }
                
                legacyLensView.additionalFrontImageBackgroundColor = params.isDark ? UIColor(red: 0.435, green: 0.435, blue: 0.435, alpha: 1.0) : .white

                self.legacyLastCroppedRect = croppedRect
                self.legacyLastCroppedOriginInLens = croppedOriginInLens
                
                if isFrontImageValid {
                    legacyLensView.updateAdditionalFrontImageOrigin(at: croppedOriginInLens)
                } else {
                    DispatchQueue.main.async {
                        self.updateLegacyLensFrontImage(inRect: croppedRect, croppedOriginInLens: croppedOriginInLens)
                    }
                }
            }
            
            self.isUpdatedForTheFirstTime = true
        }
        
        transition.setFrame(view: self.restingBackgroundView, frame: CGRect(origin: CGPoint(), size: params.size))
        self.restingBackgroundView.update(isDark: params.isDark)
        transition.setAlpha(view: self.restingBackgroundView, alpha: params.isLifted ? 0.0 : 1.0)
        
        if let legacyLensView = self.legacyLensView, let lastUpdatedParams = self.lastUpdatedParams, lastUpdatedParams.isLifted != params.isLifted {
            if params.isLifted {
                legacyLensView.interactionBegan(at: .zero)
                legacyLensView.ensureFastCaptureWithDebounce(to: .dynamicBackground(.slow))
            } else {
                legacyLensView.interactionEnded(shouldCompleteToPeak: true)
            }
        }

        if params.isLifted {
            if self.liftedDisplayLink == nil {
                self.liftedDisplayLink = SharedDisplayLinkDriver.shared.add(framesPerSecond: .max, { [weak self] _ in
                    guard let self else {
                        return
                    }
                    self.updateLiftedLensPosition()
                })
            }
            self.legacyLensView?.ensureFastCaptureWithDebounce(to: .dynamicBackground(.slow))
        } else if let liftedDisplayLink = self.liftedDisplayLink {
            self.liftedDisplayLink = nil
            liftedDisplayLink.invalidate()
        }
    }
    
    private func updateLegacyLensFrontImage(inRect rect: CGRect, croppedOriginInLens: CGPoint) {
        guard let legacyLensView = self.legacyLensView else {
            return
        }
        
        let bounds = self.liftedContainerView.bounds
        guard !bounds.isEmpty else {
            return
        }
        
        guard self.liftedContainerView.window != nil else {
            return
        }
        
        self.liftedContainerView.backgroundColor = .clear
        
        legacyLensView.useAdditionalFrontImage = true
        let format = UIGraphicsImageRendererFormat()
        format.scale = legacyLensView.captureScale
        format.opaque = false
        format.preferredRange = .standard

        let imageRenderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
        let fullImage = imageRenderer.image { context in
            self.liftedContainerView.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
        
        guard let fullCGImage = fullImage.cgImage, fullCGImage.width > 0, fullCGImage.height > 0 else {
            return
        }
        
        let scale = format.scale
        let pixelRect = CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.size.width * scale,
            height: rect.size.height * scale
        )
        
        guard
            pixelRect.width > 0, pixelRect.height > 0,
            pixelRect.maxX <= CGFloat(fullCGImage.width),
            pixelRect.maxY <= CGFloat(fullCGImage.height),
            let cgImage = fullCGImage.cropping(to: pixelRect)
        else {
            return
        }
        
        legacyLensView.setAdditionalFrontImage(cgImage, atOrigin: croppedOriginInLens)
    }
}
