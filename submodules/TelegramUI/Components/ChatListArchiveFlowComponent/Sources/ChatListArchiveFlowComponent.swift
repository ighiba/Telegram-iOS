import Foundation
import UIKit
import Display
import ComponentFlow
import TelegramPresentationData
import ItemListUI

public final class ChatListArchiveFlowComponent: Component {
    
    public let presentationData: PresentationData
    
    public init(presentationData: PresentationData) {
        self.presentationData = presentationData
    }

    public final class View: UIView {
        
        private var component: ChatListArchiveFlowComponent?
        
        private var lastProgress: CGFloat = 0
        
        private let targetHeight: CGFloat = 80
        private let insets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        
        private let swipeDownColor = UIColor(rgb: 0xB2B6BD)
        private let releaseForArchiveColor = UIColor(rgb: 0x3B82EA)
        
        private let swipeDownLabel = UILabel()
        private let releaseLabel = UILabel()
        
        public override init(frame: CGRect) {
            super.init(frame: frame)
            
            self.layer.masksToBounds = true
            self.backgroundColor = self.swipeDownColor
            self.releaseLabel.alpha = 0

            self.addSubview(swipeDownLabel)
            self.addSubview(releaseLabel)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        public func applyScroll(offset: CGFloat, navBarHeight: CGFloat, layout: ContainerViewLayout, transition: Transition) {
            let progress: CGFloat = offset < 0 ? abs(offset) / self.targetHeight : 0

            self.frame.origin.y = navBarHeight - UIScreenPixel
            self.frame.size.width = layout.size.width
            
            self.swipeDownLabel.frame.origin.y = self.bounds.height - self.insets.bottom - self.swipeDownLabel.bounds.height
            self.releaseLabel.frame.origin.y = self.bounds.height - self.insets.bottom - self.releaseLabel.bounds.height
            
            self.frame.origin.y = navBarHeight
            if offset < 0 {
                self.frame.size.height = abs(offset)
                self.animateProgress(progress)
            } else {
                self.frame.size.height = 0
            }
            
            self.lastProgress = progress
        }
        
        private func animateProgress(_ progress: CGFloat) {
            let enterInRelease = progress >= 1 && self.lastProgress < 1
            let enterInSwipeDown = progress < 1 && self.lastProgress >= 1
            let leftOffset: CGFloat = -self.bounds.width / 3
            let rightOffset: CGFloat = self.bounds.width / 3
            
            let duration: CGFloat = 0.45
            let springDamping: CGFloat = 0.7
            
            if enterInRelease {
                self.backgroundColor = self.releaseForArchiveColor
                
                UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: springDamping, initialSpringVelocity: 0, options: [.beginFromCurrentState]) { [weak self] in
                    self?.releaseLabel.alpha = 1
                    self?.swipeDownLabel.alpha = 0
                    self?.releaseLabel.transform = .identity
                    self?.swipeDownLabel.transform = CGAffineTransform(translationX: rightOffset, y: 0)
                }
            } else if enterInSwipeDown {
                self.backgroundColor = self.swipeDownColor
                
                UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: springDamping, initialSpringVelocity: 0, options: [.beginFromCurrentState]) { [weak self] in
                    self?.releaseLabel.alpha = 0
                    self?.swipeDownLabel.alpha = 1
                    self?.releaseLabel.transform = CGAffineTransform(translationX: leftOffset, y: 0)
                    self?.swipeDownLabel.transform = .identity
                }
            }
        }
        
        public func update(component: ChatListArchiveFlowComponent, availableSize: CGSize, transition: Transition) -> CGSize {
            self.component = component
            let fontSize: CGFloat = component.presentationData.chatFontSize.itemListBaseFontSize
            self.updateLabel(swipeDownLabel, withText: NSLocalizedString("Swipe down for archive", comment: ""), fontSize: fontSize, availableSize: availableSize)
            self.updateLabel(releaseLabel, withText: NSLocalizedString("Release for archive", comment: ""), fontSize: fontSize, availableSize: availableSize)
            self.releaseLabel.transform = CGAffineTransform(translationX: -availableSize.width, y: 0)
            
            return .zero
        }
        
        private func updateLabel(_ label: UILabel, withText text: String, fontSize: CGFloat, availableSize: CGSize) {
            label.text = text
            label.textColor = .white
            label.font = Font.semibold(floor(fontSize * 17 / 18))
            label.sizeToFit()
            label.frame.origin.x = (availableSize.width - label.bounds.width) / 2
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
