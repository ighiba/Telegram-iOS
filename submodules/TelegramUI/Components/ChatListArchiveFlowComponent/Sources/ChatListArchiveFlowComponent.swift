import Foundation
import UIKit
import Display
import ComponentFlow
import TelegramPresentationData
import ItemListUI
import AnimationUI

public final class ChatListArchiveFlowComponent: Component {
    
    public let presentationData: PresentationData
    
    public init(presentationData: PresentationData) {
        self.presentationData = presentationData
    }

    public final class View: UIView {
        
        private var component: ChatListArchiveFlowComponent?
        
        private var lastProgress: CGFloat = 0
        
        private let targetHeight: CGFloat = 80
        private let insets = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        private let arrowIconWidth: CGFloat = 20
        
        private let labelsContainer = UIView()
        private let swipeDownLabel = UILabel()
        private let releaseLabel = UILabel()
        private let arrowIcon = UIImageView()
        private let arrowLine = UIView()
        private let arrowArchiveAnimationNode = AnimationNode(animation: "anim_arrow_archive", colors: [:], scale: 1.0)
        
        private let swipeDownGradient = CAGradientLayer()
        private let releaseForArchiveGradient = CAGradientLayer()
        
        private let swipeDownColor = UIColor(rgb: 0xB1B1B1)
        private let releaseForArchiveColor = UIColor(rgb: 0x3A83F6)
        private let swipeDownGradientColors: [CGColor] = [UIColor(rgb: 0xB1B1B1).cgColor, UIColor(rgb: 0xD9D9D9).cgColor]
        private let releaseForArchiveGradientColors: [CGColor] = [UIColor(rgb: 0x3A83F6).cgColor, UIColor(rgb: 0x89C3F8).cgColor]
        
        public override init(frame: CGRect) {
            super.init(frame: frame)
            
            self.layer.masksToBounds = true

            self.configureGradients()
            self.configureArrowLine()
            self.configureArrowIcon()
            self.configureLabels()
            self.configureArrowArchiveAnimationNode()
            
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
            self.swipeDownGradient.colors = self.swipeDownGradientColors
            
            let maskLayer = CAShapeLayer()
            maskLayer.path = UIBezierPath(roundedRect: CGRect(x: 0, y: 0,width: self.arrowIconWidth, height: self.arrowIconWidth), cornerRadius: 25).cgPath
            self.releaseForArchiveGradient.mask = maskLayer
            self.releaseForArchiveGradient.mask?.transform = CATransform3DMakeScale(1, 1, 0)
            self.releaseForArchiveGradient.startPoint = startPoint
            self.releaseForArchiveGradient.endPoint = endPoint
            self.releaseForArchiveGradient.colors = self.releaseForArchiveGradientColors
        }
        
        private func configureArrowLine() {
            self.arrowLine.alpha = 0.35
            self.arrowLine.frame = CGRect(x: self.insets.left, y: 0, width: self.arrowIconWidth, height: self.arrowIconWidth)
            self.arrowLine.backgroundColor = UIColor.white
            self.arrowLine.layer.cornerRadius = self.arrowIconWidth / 2
        }
        
        private func configureArrowIcon() {
            self.arrowIcon.image = generateTintedImage(image: UIImage(bundleImageName: "Chat List/ArchiveFlow/ArchiveFlowArrow"), color: .white)
            self.arrowIcon.frame = self.arrowLine.frame
            self.arrowIcon.backgroundColor = self.swipeDownColor
            self.arrowIcon.layer.cornerRadius = self.arrowIconWidth / 2
            self.arrowIcon.transform = CGAffineTransform(rotationAngle: .pi)
        }
        
        private func configureLabels() {
            self.releaseLabel.alpha = 0
            self.labelsContainer.layer.masksToBounds = true
        }
        
        private func configureArrowArchiveAnimationNode() {
            self.arrowArchiveAnimationNode.view.isHidden = true
            self.arrowArchiveAnimationNode.setColors(colors: [
                "**.Stroke 1": releaseForArchiveColor,
                "**.Fill 1" : .white
            ])
        }

        public func applyScroll(offset: CGFloat, navBarHeight: CGFloat, layout: ContainerViewLayout, transition: Transition) {
            if self.bounds.height == 0 && offset > 0 {
                return
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
                
                UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: springDamping, initialSpringVelocity: 0, options: [.beginFromCurrentState]) { [weak self] in
                    self?.releaseLabel.alpha = 1
                    self?.swipeDownLabel.alpha = 0
                    self?.releaseLabel.transform = .identity
                    self?.swipeDownLabel.transform = CGAffineTransform(translationX: swipeDownLabelOffsetX, y: 0)
                    self?.arrowIcon.transform = CGAffineTransform(rotationAngle: .pi - 3.14159)
                    self?.arrowIcon.backgroundColor = self?.releaseForArchiveColor
                }
            } else if enterInSwipeDown {
                self.releaseForArchiveGradient.mask?.transform = CATransform3DMakeScale(1, 1, 0)

                UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: springDamping, initialSpringVelocity: 0, options: [.beginFromCurrentState]) { [weak self] in
                    self?.releaseLabel.alpha = 0
                    self?.swipeDownLabel.alpha = 1
                    self?.releaseLabel.transform = CGAffineTransform(translationX: releaseLabelOffsetX, y: 0)
                    self?.swipeDownLabel.transform = .identity
                    self?.arrowIcon.transform = CGAffineTransform(rotationAngle: .pi)
                    self?.arrowIcon.backgroundColor = self?.swipeDownColor
                }
            }
        }
        
        public func update(component: ChatListArchiveFlowComponent, availableSize: CGSize, transition: Transition) -> CGSize {
            self.component = component
            let avatarWidth = min(60.0, floor(component.presentationData.listsFontSize.baseDisplaySize * 60.0 / 17.0))
            let arrowLineX = self.insets.left + avatarWidth / 2 - self.arrowIconWidth / 2
            self.arrowLine.frame.origin.x = arrowLineX
            self.arrowIcon.frame.origin.x = arrowLineX

            let fontSize: CGFloat = component.presentationData.chatFontSize.itemListBaseFontSize
            let labelsContainerOffset = arrowLineX + self.arrowIconWidth / 2
            let labelsContainerFrame = CGRect(x: labelsContainerOffset, y: 0, width: availableSize.width - labelsContainerOffset, height: self.bounds.height)
            transition.setFrame(view: self.labelsContainer, frame: labelsContainerFrame)
            
            self.updateLabel(swipeDownLabel, withText: NSLocalizedString("Swipe down for archive", comment: ""), fontSize: fontSize, availableSize: availableSize, containerOffsetX: labelsContainerOffset)
            self.updateLabel(releaseLabel, withText: NSLocalizedString("Release for archive", comment: ""), fontSize: fontSize, availableSize: availableSize, containerOffsetX: labelsContainerOffset)
            self.releaseLabel.transform = CGAffineTransform(translationX: -availableSize.width, y: 0)
            
            let animationViewWidth: CGFloat = 58
            let arrowArchiveAnimationNodeFrame = CGRect(x: 0, y: 0, width: animationViewWidth, height: animationViewWidth + 7.6)
            transition.setFrame(view: self.arrowArchiveAnimationNode.view, frame: arrowArchiveAnimationNodeFrame)

            return availableSize
        }
        
        private func updateLabel(_ label: UILabel, withText text: String, fontSize: CGFloat, availableSize: CGSize, containerOffsetX: CGFloat) {
            label.text = text
            label.textColor = .white
            label.font = Font.semibold(floor(fontSize * 17 / 18))
            label.sizeToFit()
            label.frame.origin.x = (availableSize.width - label.bounds.width) / 2 - containerOffsetX
        }
    }

    static public func == (lhs: ChatListArchiveFlowComponent, rhs: ChatListArchiveFlowComponent) -> Bool {
        return lhs.presentationData == rhs.presentationData
    }

    public func makeView() -> View {
        return View(frame: .zero)
    }
    
    public func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: Transition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, transition: transition)
    }
}
