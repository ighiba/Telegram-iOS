import Foundation
import UIKit
import Display
import ComponentFlow
import TelegramPresentationData
import ItemListUI
import AnimationUI

public final class ChatListArchiveFlowComponent: Component {
    
    public let presentationData: PresentationData
    public let safeInsets: UIEdgeInsets
    public let progressHandler: (Bool) -> Void
    
    public init(presentationData: PresentationData, safeInsets: UIEdgeInsets, progressHandler: @escaping (Bool) -> Void) {
        self.presentationData = presentationData
        self.safeInsets = safeInsets
        self.progressHandler = progressHandler
    }

    public final class View: UIView {
        
        private var component: ChatListArchiveFlowComponent?
        
        private var lastProgress: CGFloat = 0
        
        private let targetHeight: CGFloat = 80
        private let insets = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        private let arrowIconWidth: CGFloat = 20
        private var avatarWidth: CGFloat {
            let baseDisplaySize: CGFloat = self.component?.presentationData.listsFontSize.baseDisplaySize ?? 60
            return min(60.0, floor(baseDisplaySize * 60.0 / 17.0))
        }
        private var arrowLineX: CGFloat {
            let leftSafeInset: CGFloat = self.component?.safeInsets.left ?? 0
            return leftSafeInset + self.insets.left + self.avatarWidth / 2 - self.arrowIconWidth / 2
        }
        
        private let labelsContainer = UIView()
        private let swipeDownLabel = UILabel()
        private let releaseLabel = UILabel()
        private let arrowIcon = UIImageView()
        private let arrowLine = UIView()
        private let arrowArchiveAnimationNode = AnimationNode(animation: "anim_arrow_archive", colors: [:], scale: 1.0)
        
        private let swipeDownGradient = CAGradientLayer()
        private let releaseForArchiveGradient = CAGradientLayer()

        private let swipeDownGradientColors = PresentationThemeGradientColors(topColor: UIColor(rgb: 0xD9D9DD), bottomColor: UIColor(rgb: 0xB5BAC1))
        private let releaseForArchiveGradientColors = PresentationThemeGradientColors(topColor: UIColor(rgb: 0x81C4FF), bottomColor: UIColor(rgb: 0x2D83F2))
        
        private var isAnimatingOut: Bool = false
        private var isNeedToReset: Bool = false

        public override init(frame: CGRect) {
            super.init(frame: frame)

            self.configureGradients()
            self.configureArrowLine()
            self.configureArrowIcon()
            self.configureLabels()
            self.configureArrowArchiveAnimationNode()
            
            self.layer.masksToBounds = true
            self.layer.addSublayer(self.swipeDownGradient)
            self.layer.addSublayer(self.releaseForArchiveGradient)
            self.labelsContainer.addSubview(swipeDownLabel)
            self.labelsContainer.addSubview(releaseLabel)
            self.addSubview(labelsContainer)
            self.addSubview(arrowLine)
            self.addSubview(arrowIcon)
            self.addSubview(arrowArchiveAnimationNode.view)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        private func configureGradients() {
            let (startPoint, endPoint) = (CGPoint(x: 0.1, y: 0.5), CGPoint(x: 1, y: 0.25))
            
            self.swipeDownGradient.startPoint = startPoint
            self.swipeDownGradient.endPoint = endPoint
            
            let maskLayer = CAShapeLayer()
            maskLayer.path = UIBezierPath(roundedRect: CGRect(x: 0, y: 0,width: self.arrowIconWidth, height: self.arrowIconWidth), cornerRadius: 25).cgPath
            self.releaseForArchiveGradient.mask = maskLayer
            self.releaseForArchiveGradient.mask?.transform = CATransform3DMakeScale(1, 1, 0)
            self.releaseForArchiveGradient.startPoint = startPoint
            self.releaseForArchiveGradient.endPoint = endPoint
        }
        
        private func configureArrowLine() {
            self.arrowLine.alpha = 0.35
            self.arrowLine.frame = CGRect(x: self.arrowLineX, y: 0, width: self.arrowIconWidth, height: self.arrowIconWidth)
            self.arrowLine.backgroundColor = UIColor.white
            self.arrowLine.layer.cornerRadius = self.arrowIconWidth / 2
        }
        
        private func configureArrowIcon() {
            self.arrowIcon.image = generateTintedImage(image: UIImage(bundleImageName: "Chat List/ArchiveFlow/ArchiveFlowArrow"), color: .white)
            self.arrowIcon.frame = CGRect(x: self.arrowLineX, y: 0, width: self.arrowIconWidth, height: self.arrowIconWidth)
            self.arrowIcon.backgroundColor = self.swipeDownGradientColors.bottomColor
            self.arrowIcon.layer.cornerRadius = self.arrowIconWidth / 2
            self.arrowIcon.transform = CGAffineTransform(rotationAngle: .pi)
        }
        
        private func configureLabels() {
            self.releaseLabel.alpha = 0
            self.labelsContainer.layer.masksToBounds = true
        }
        
        private func configureArrowArchiveAnimationNode() {
            self.arrowArchiveAnimationNode.view.isHidden = true
            let strokeColor = self.releaseForArchiveGradientColors.bottomColor
            self.arrowArchiveAnimationNode.setColors(colors: [
                "**.Stroke 1": strokeColor,
                "**.Fill 1" : .white
            ])
        }

        public func applyScroll(offset: CGFloat, navBarHeight: CGFloat, layout: ContainerViewLayout, transition: Transition) {
            if self.isAnimatingOut || self.bounds.height == 0 && offset > 0 {
                self.isHidden = true
                return
            }
            
            self.isHidden = false
            
            if self.isNeedToReset {
                self.resetProgress()
                self.isNeedToReset = false
            }
            
            let progress: CGFloat = offset < 0 ? abs(offset) / self.targetHeight : 0
            guard progress != self.lastProgress else { return }

            var componentFrame = CGRect(x: self.frame.origin.x, y: navBarHeight, width: layout.size.width, height: self.frame.height)
            
            if offset < 0 {
                componentFrame.size.height = abs(offset)
                self.animateProgress(progress)
            } else {
                componentFrame.size.height = 0
            }
            transition.setFrame(view: self, frame: componentFrame)
            transition.setFrame(layer: self.swipeDownGradient, frame: self.bounds)
            transition.setFrame(layer: self.releaseForArchiveGradient, frame: self.bounds)
            
            var arrowLineFrame = self.arrowLine.frame
            var arrorIconFrame = self.arrowIcon.frame
            var arrowArchiveAnimationFrame = self.arrowArchiveAnimationNode.view.frame
            
            let minimalComponentHeightForLine = self.arrowIconWidth + self.insets.top + self.insets.bottom
            if self.bounds.height < minimalComponentHeightForLine {
                arrowLineFrame.size.height = self.arrowIconWidth
                arrowLineFrame.origin.y = self.bounds.height - self.insets.bottom - arrowLineFrame.height
                arrorIconFrame.origin = arrowLineFrame.origin
                arrowArchiveAnimationFrame.origin = arrorIconFrame.origin
                arrowArchiveAnimationFrame.origin.x -= arrorIconFrame.width - 1
            } else {
                arrowLineFrame.size.height = self.bounds.height - self.insets.top - self.insets.bottom
                arrowLineFrame.origin.y = insets.top
                arrorIconFrame.origin.y = self.insets.top + arrowLineFrame.height - arrorIconFrame.height
                arrowArchiveAnimationFrame.origin.y = arrorIconFrame.origin.y - self.arrowArchiveAnimationNode.bounds.height / 2 + arrorIconFrame.height / 2 - 3.75
            }
            
            transition.setFrame(view: self.arrowLine, frame: arrowLineFrame)
            transition.setFrame(view: self.arrowIcon, frame: arrorIconFrame)
            transition.setFrame(view: self.arrowArchiveAnimationNode.view, frame: arrowArchiveAnimationFrame)
            if let mask = self.releaseForArchiveGradient.mask {
                transition.setFrame(layer: mask, frame: arrorIconFrame)
            }
            
            self.swipeDownLabel.frame.origin.y = self.bounds.height - self.insets.bottom - self.swipeDownLabel.bounds.height
            self.releaseLabel.frame.origin.y = self.bounds.height - self.insets.bottom - self.releaseLabel.bounds.height
            self.labelsContainer.frame.size.height = self.bounds.height
            
            self.lastProgress = progress
            self.component?.progressHandler(progress >= 1.0)
        }
        
        private func animateProgress(_ progress: CGFloat) {
            let enterInRelease = progress >= 1 && self.lastProgress < 1
            let enterInSwipeDown = progress < 1 && self.lastProgress >= 1

            let labelCenterOffset = max(self.releaseLabel.bounds.width / 2, self.swipeDownLabel.bounds.width / 2)
            let releaseLabelOffsetX: CGFloat = -self.bounds.width / 2 - labelCenterOffset
            let swipeDownLabelOffsetX: CGFloat = self.bounds.width / 2 + labelCenterOffset
            
            let duration: CGFloat = 0.55
            let springDamping: CGFloat = 0.7

            if enterInRelease {
                let maskScale: CGFloat = (self.bounds.width / self.arrowIconWidth) * 3
                self.releaseForArchiveGradient.mask?.transform = CATransform3DMakeScale(maskScale, maskScale, 0)
                self.swipeDownLabel.transform = .identity
                UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: springDamping, initialSpringVelocity: 0, options: [.beginFromCurrentState]) { [weak self] in
                    self?.releaseLabel.alpha = 1
                    self?.swipeDownLabel.alpha = 0
                    self?.releaseLabel.transform = .identity
                    self?.swipeDownLabel.transform = CGAffineTransform(translationX: swipeDownLabelOffsetX, y: 0)
                    self?.arrowIcon.transform = CGAffineTransform(rotationAngle: .pi - 3.14159)
                    self?.arrowIcon.backgroundColor = self?.releaseForArchiveGradientColors.bottomColor
                }
            } else if enterInSwipeDown {
                self.releaseForArchiveGradient.mask?.transform = CATransform3DMakeScale(1, 1, 0)
                self.releaseLabel.transform = .identity
                UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: springDamping, initialSpringVelocity: 0, options: [.beginFromCurrentState]) { [weak self] in
                    self?.releaseLabel.alpha = 0
                    self?.swipeDownLabel.alpha = 1
                    self?.releaseLabel.transform = CGAffineTransform(translationX: releaseLabelOffsetX, y: 0)
                    self?.swipeDownLabel.transform = .identity
                    self?.arrowIcon.transform = CGAffineTransform(rotationAngle: .pi)
                    self?.arrowIcon.backgroundColor = self?.swipeDownGradientColors.bottomColor
                }
            }
        }
        
        public func animateOut(_ itemView: UIView, itemHeight: CGFloat, transitionDuration: CGFloat, completion: (() -> Void)? = nil) {
            guard !self.isAnimatingOut else {
                return
            }
            self.isAnimatingOut = true
            self.component?.progressHandler(false)
            let superLayer = self.layer.superlayer
            let initialLayerPosition = self.layer.frame.origin
            self.arrowIcon.isHidden = true
            self.arrowLine.isHidden = false
            self.swipeDownGradient.isHidden = true
            self.arrowArchiveAnimationNode.isHidden = false
            self.arrowArchiveAnimationNode.reset()
            self.arrowArchiveAnimationNode.playOnce()
            
            self.arrowArchiveAnimationNode.speed = transitionDuration * 2.2

            let sourceView = itemView.subviews.first
            let itemViewSnapshot = itemView.snapshotContentTree()
            if let itemViewSnapshot {
                itemView.addSubview(itemViewSnapshot)
            }
            
            self.layer.frame.origin = .zero
            itemView.layer.addSublayer(self.layer)
            sourceView?.isHidden = true

            let duration: CGFloat = transitionDuration * 0.6
            let springDuration: CGFloat = transitionDuration * 1.05
            
            let avatarPosition = CGPoint(x: self.arrowLine.frame.origin.x, y: (itemHeight - self.arrowLine.frame.width) / 2)
            let arrowLineTargetPosition = CGPoint(x: avatarPosition.x, y: self.bounds.height * 0.6)
            let arrowLineTargetFrame = CGRect(origin: arrowLineTargetPosition, size: CGSize(width: self.arrowLine.frame.width, height: 0))
            self.arrowLine.layer.animateFrame(from: self.arrowLine.frame, to: arrowLineTargetFrame, duration: duration * 0.3, removeOnCompletion: false) { [weak self] _ in
                self?.arrowLine.isHidden = true
            }
            
            let arrowArchiveAnimationPositionEnd = avatarPosition.offsetBy(dx: self.arrowLine.frame.width / 2, dy: self.arrowLine.frame.width / 2)
            self.arrowArchiveAnimationNode.layer.animateSpringPosition(from: self.arrowArchiveAnimationNode.frame.center, to: arrowArchiveAnimationPositionEnd, duration: springDuration, damping: 300.0, removeOnCompletion: false)
            self.arrowArchiveAnimationNode.layer.animateSpringScale(from: 1.0, to: 1.07, duration: springDuration, delay: springDuration * 0.5, damping: 120.0, removeOnCompletion: false)

            let avatarWidth = self.avatarWidth
            if let mask = self.releaseForArchiveGradient.mask {
                let startScale = (self.bounds.width / self.arrowIconWidth) * 3
                let endScale = avatarWidth / self.arrowIconWidth
                let offsetXY = self.arrowIconWidth / 2
                mask.animateSpringPosition(from: mask.frame.center, to: avatarPosition.offsetBy(dx: offsetXY, dy: offsetXY), duration: springDuration, damping: 120.0, removeOnCompletion: false)
                mask.animateSpringScale(from: startScale, to: endScale, duration: springDuration, damping: 120.0, removeOnCompletion: false)
            }

            self.labelsContainer.layer.animateAlpha(from: 1.0, to: 0.0, duration: duration * 0.05, delay: duration * 0.5, removeOnCompletion: false)
            self.labelsContainer.layer.animateSpringPosition(from: self.labelsContainer.center, to: self.labelsContainer.center.offsetBy(dx: 0, dy: itemHeight - self.bounds.height), duration: springDuration, initialVelocity: 0.2, damping: 300.0, removeOnCompletion: false)

            let gradientX: CGFloat = 0.5
            let gradientYStart: CGFloat = avatarWidth * 0.8 / self.bounds.height
            let gradientYEnd: CGFloat = avatarWidth * -0.1 / self.bounds.height
            UIView.animate(withDuration: duration * 0.6, delay: duration * 0.3) { [weak self] in
                self?.releaseForArchiveGradient.startPoint = CGPoint(x: gradientX, y: gradientYStart)
                self?.releaseForArchiveGradient.endPoint = CGPoint(x: gradientX, y: gradientYEnd)
            }
            
            let didComplete: () -> Void = { [weak self] in
                guard let strongSelf = self else {
                    completion?()
                    return
                }
                
                if let archiveFolderSnapshot = strongSelf.arrowArchiveAnimationNode.view.snapshotView(afterScreenUpdates: true) {
                    let scale: CGFloat =  1.02
                    archiveFolderSnapshot.layer.transform = CATransform3DMakeScale(scale, scale, 0)
                    archiveFolderSnapshot.layer.frame = strongSelf.arrowArchiveAnimationNode.frame
                    
                    let gradientLayer = CAGradientLayer()
                    gradientLayer.frame = CGRect(x: 0, y: 0, width: avatarWidth, height: avatarWidth)
                    gradientLayer.cornerRadius = avatarWidth / 2
                    gradientLayer.colors = strongSelf.gradientColors(strongSelf.releaseForArchiveGradientColors)
                    gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.7)
                    gradientLayer.endPoint = CGPoint(x: 0.5, y: -0.3)
                    
                    if let avatarView = sourceView?.subviews.last(where: { $0.frame.width == $0.frame.height && $0.frame.width == avatarWidth }) {
                        gradientLayer.frame.origin = .zero
                        archiveFolderSnapshot.layer.frame.origin = CGPoint(
                            x: (avatarView.bounds.width - archiveFolderSnapshot.layer.bounds.width * scale) / 2,
                            y: (avatarView.bounds.height - archiveFolderSnapshot.layer.bounds.height * scale) / 2
                        )
                        avatarView.layer.addSublayer(gradientLayer)
                        avatarView.layer.addSublayer(archiveFolderSnapshot.layer)
                    } else {
                        gradientLayer.frame.origin = CGPoint(x: strongSelf.insets.left, y: (itemHeight - avatarWidth) / 2)
                        archiveFolderSnapshot.layer.frame.origin = arrowArchiveAnimationPositionEnd.offsetBy(
                            dx: -strongSelf.arrowArchiveAnimationNode.frame.width * scale / 2,
                            dy: -strongSelf.arrowArchiveAnimationNode.frame.height * scale / 2
                        )
                        sourceView?.layer.addSublayer(gradientLayer)
                        sourceView?.layer.addSublayer(archiveFolderSnapshot.layer)
                    }
                }
                
                strongSelf.arrowIcon.isHidden = false
                strongSelf.arrowLine.isHidden = false
                strongSelf.swipeDownGradient.isHidden = false
                strongSelf.arrowArchiveAnimationNode.isHidden = true
                strongSelf.arrowArchiveAnimationNode.reset()
                strongSelf.layer.frame = CGRect(origin: initialLayerPosition, size: CGSize(width: strongSelf.bounds.width, height: 0))
                superLayer?.addSublayer(strongSelf.layer)
                
                strongSelf.resetProgress()
                
                sourceView?.isHidden = false
                itemViewSnapshot?.removeFromSuperview()
                
                strongSelf.isAnimatingOut = false
                completion?()
            }
            
            let heightDiff = self.lastProgress * self.targetHeight - itemHeight
            let itemViewPositionStart =  sourceView?.frame.center.offsetBy(dx: 0, dy: heightDiff) ?? .zero
            let itemViewPositionEnd = sourceView?.frame.center ?? .zero
            itemViewSnapshot?.layer.animateSpringPosition(from: itemViewPositionStart, to: itemViewPositionEnd, duration: springDuration, initialVelocity: 3.5, damping: 300, removeOnCompletion: false) { [weak self] _ in
                self?.isNeedToReset = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    didComplete()
                }
            }
        }
        
        public func resetProgress() {
            self.lastProgress = 0
            self.frame.size.height = 0
            
            self.arrowLine.layer.removeAllAnimations()
            self.arrowArchiveAnimationNode.layer.removeAllAnimations()
            self.releaseForArchiveGradient.mask?.removeAllAnimations()
            self.labelsContainer.layer.removeAllAnimations()
            
            let labelCenterOffset = max(self.releaseLabel.bounds.width / 2, self.swipeDownLabel.bounds.width / 2)
            let releaseLabelOffsetX: CGFloat = -self.bounds.width / 2 - labelCenterOffset
            self.releaseLabel.transform = CGAffineTransform(translationX: releaseLabelOffsetX, y: 0)
            self.swipeDownLabel.transform = .identity
            self.releaseLabel.alpha = 0
            self.swipeDownLabel.alpha = 1
            
            self.configureGradients()
            self.configureArrowIcon()
        }
        
        public func update(component: ChatListArchiveFlowComponent, availableSize: CGSize, transition: Transition) -> CGSize {
            self.component = component
            
            self.arrowIcon.frame.origin.x = self.arrowLineX
            self.arrowLine.frame.origin.x = self.arrowLineX

            let fontSize: CGFloat = component.presentationData.chatFontSize.itemListBaseFontSize
            let labelsContainerOffset = self.arrowLineX + self.arrowIconWidth / 2
            let labelsContainerFrame = CGRect(x: labelsContainerOffset, y: 0, width: availableSize.width - labelsContainerOffset, height: self.bounds.height)
            transition.setFrame(view: self.labelsContainer, frame: labelsContainerFrame)
            
            self.updateLabel(swipeDownLabel, withText: component.presentationData.strings.ChatList_ArchiveFlowSwipe, fontSize: fontSize, availableSize: availableSize, containerOffsetX: labelsContainerOffset)
            self.updateLabel(releaseLabel, withText: component.presentationData.strings.ChatList_ArchiveFlowRelease, fontSize: fontSize, availableSize: availableSize, containerOffsetX: labelsContainerOffset)
            let labelCenterOffset = max(self.releaseLabel.bounds.width / 2, self.swipeDownLabel.bounds.width / 2)
            let releaseLabelOffsetX: CGFloat = -availableSize.width / 2 - labelCenterOffset
            self.releaseLabel.transform = CGAffineTransform(translationX: releaseLabelOffsetX, y: 0)
            
            let animationViewWidth: CGFloat = 58
            let arrowArchiveAnimationNodeFrame = CGRect(x: 0, y: 0, width: animationViewWidth, height: animationViewWidth + 7.6)
            transition.setFrame(view: self.arrowArchiveAnimationNode.view, frame: arrowArchiveAnimationNodeFrame)
            
            self.updateColors()

            return availableSize
        }
        
        private func updateLabel(_ label: UILabel, withText text: String, fontSize: CGFloat, availableSize: CGSize, containerOffsetX: CGFloat) {
            label.text = text
            label.font = Font.semibold(floor(fontSize * 17 / 18))
            label.sizeToFit()
            label.transform = .identity
            label.frame.origin.x = (availableSize.width - label.bounds.width) / 2 - containerOffsetX
        }
        
        private func updateColors() {
            self.swipeDownGradient.colors = self.gradientColors(self.swipeDownGradientColors)
            self.releaseForArchiveGradient.colors = self.gradientColors(self.releaseForArchiveGradientColors)
            
            self.swipeDownLabel.textColor = .white
            self.releaseLabel.textColor = .white
            
            self.arrowArchiveAnimationNode.setColors(colors: [
                "**.Stroke 1": self.releaseForArchiveGradientColors.bottomColor,
                "**.Fill 1" : .white
            ])
        }
        
        private func gradientColors(_ themeGradientColors: PresentationThemeGradientColors) -> [CGColor] {
            return [themeGradientColors.bottomColor.cgColor, themeGradientColors.topColor.cgColor]
        }
    }

    static public func == (lhs: ChatListArchiveFlowComponent, rhs: ChatListArchiveFlowComponent) -> Bool {
        if lhs.presentationData != rhs.presentationData {
            return false
        }
        if lhs.safeInsets != rhs.safeInsets {
            return false
        }
        return true
    }

    public func makeView() -> View {
        return View(frame: .zero)
    }
    
    public func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: Transition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, transition: transition)
    }
}
