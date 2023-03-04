import Foundation
import UIKit
import TelegramCore
import TelegramUIPreferences
import Display
import AsyncDisplayKit
import SwiftSignalKit
import LegacyComponents
import AnimatedStickerNode
import TelegramAnimatedStickerNode
import MediaResources
import Postbox
import AccountContext


private let emojiFont = Font.regular(36.0)
private let textFont = Font.regular(15.0)
private let emojiSize = CGSize(width: 48.0, height: 48.0)
private let emojiSpacing = 6.0

final class CallControllerKeyPreviewNode: ASDisplayNode {
    private let keyTextNode: ASTextNode
    private let keyEmojisNode: ASDisplayNode
    private let infoTitleNode: ASTextNode
    private let infoTextNode: ASTextNode
    private let containerNode: ASDisplayNode
    private let okButton: UIButton

    var context: AccountContext
    private var animatedEmojiNodes: [DefaultAnimatedStickerNodeImpl]
    
    public var hasVideo: Bool = false

    private let dismiss: () -> Void
    
    init(context: AccountContext, keyText: String, titleText: String, infoText: String, hasVideo: Bool, dismiss: @escaping () -> Void) {
        self.context = context
        self.keyTextNode = ASTextNode()
        self.keyTextNode.displaysAsynchronously = false
        self.keyEmojisNode = ASDisplayNode()
        self.keyEmojisNode.displaysAsynchronously = false
        self.animatedEmojiNodes = []
        self.infoTitleNode = ASTextNode()
        self.infoTitleNode.displaysAsynchronously = false
        self.infoTextNode = ASTextNode()
        self.infoTextNode.displaysAsynchronously = false
        self.containerNode = ASDisplayNode()
        self.okButton = UIButton()
        self.hasVideo = hasVideo
        self.dismiss = dismiss

        super.init()
 
        self.keyTextNode.attributedText = NSAttributedString(string: keyText, attributes: [NSAttributedString.Key.font: emojiFont, NSAttributedString.Key.kern: 11.0 as NSNumber])
        self.infoTitleNode.attributedText = NSMutableAttributedString(string: titleText, font: Font.semibold(16.0), textColor: UIColor.white, paragraphAlignment: .center)
        self.infoTextNode.attributedText = NSMutableAttributedString(string: infoText, font: Font.semibold(16.0), textColor: UIColor.white, paragraphAlignment: .center)
        
        self.okButton.setTitle("OK", for: .normal)

        self.addSubnode(self.containerNode)
        self.addSubnode(self.keyEmojisNode)
        self.containerNode.view.addSubview(self.infoTitleNode.view)
        self.containerNode.view.addSubview(self.infoTextNode.view)
        self.containerNode.view.addSubview(self.okButton)
        
        self.animatedEmojiNodes = self.obtainEmojiNodes(keyText: keyText, for: context, size: emojiSize)
        self.animatedEmojiNodes.forEach({
            self.keyEmojisNode.addSubnode($0)
            $0.displaysAsynchronously = true
        })
        
        self.updateColors()
    }
    
    override func didLoad() {
        super.didLoad()
        
        self.okButton.addTarget(self, action: #selector(self.buttonPressed(_:)), for: .touchDown)
        self.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.tapGesture(_:))))
    }
    
    private func updateEmojiLayout() {
        for i in 0 ..< 4 {
            let emojiNode = self.animatedEmojiNodes[i]
            let emojiPoint = CGPoint(x: CGFloat(i) * emojiSpacing + CGFloat(i) * emojiSize.width, y: 0.0)

            emojiNode.frame = CGRect(origin: emojiPoint, size: emojiSize)
            emojiNode.visibility = true
            emojiNode.updateLayout(size: emojiSize)
            emojiNode.playLoop()
        }
    }
    
    func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) {
        self.containerNode.layer.cornerRadius = 22
        self.updateColors()
        
        let containerOffset = 132.0
        let topContainerSpacing = 20.0
        let textSpacing = 10.0
        
        let containerSize = self.containerNode.measure(CGSize(width: 304.0, height: 225.0))
        transition.updateFrame(node: self.containerNode, frame: CGRect(origin: CGPoint(x: floor((size.width - containerSize.width) / 2.0), y: containerOffset), size: containerSize))
        
        let keyTextSize = self.keyTextNode.measure(CGSize(width: 300.0, height: 48.0))
        let keyTextPoint = CGPoint(x: floor((size.width - keyTextSize.width) / 2), y: containerOffset + topContainerSpacing)
        transition.updateFrame(node: self.keyTextNode, frame: CGRect(origin: keyTextPoint, size: keyTextSize))
        
        let keyEmojisSize = self.keyEmojisNode.measure(CGSize(width: emojiSize.width * 4 + emojiSpacing * 3, height: emojiSize.height))
        let keyEmojisPoint = CGPoint(x: floor((size.width - keyEmojisSize.width) / 2), y: containerOffset + topContainerSpacing)
        transition.updateFrame(node: self.keyEmojisNode, frame: CGRect(origin: keyEmojisPoint, size: keyEmojisSize))

        let infoTitleSize = self.infoTitleNode.measure(CGSize(width: containerSize.width - 28.0, height: 19.0))
        let infoTitlePoint = CGPoint(x: floor((containerSize.width - infoTitleSize.width) / 2.0), y: topContainerSpacing + keyTextSize.height + textSpacing)
        transition.updateFrame(node: self.infoTitleNode, frame: CGRect(origin: infoTitlePoint, size: infoTitleSize))
        
        let infoTextSize = self.infoTextNode.measure(CGSize(width: containerSize.width - 32.0, height: CGFloat.greatestFiniteMagnitude))
        transition.updateFrame(node: self.infoTextNode, frame: CGRect(origin: CGPoint(x: floor((containerSize.width - infoTextSize.width) / 2.0), y: infoTitlePoint.y + infoTitleSize.height + textSpacing), size: infoTextSize))
        
        let buttonSize = CGSize(width: containerSize.width, height: 56.0)
        let buttonPoint = CGPoint(x: 0.0, y: containerSize.height - buttonSize.height)
        self.okButton.frame = CGRect(origin: buttonPoint, size: buttonSize)
        
        let mask = CAShapeLayer()

        mask.path = UIBezierPath(roundedRect: self.okButton.bounds, byRoundingCorners: [.bottomLeft , .bottomRight], cornerRadii: CGSize(width: 22.0, height: 22.0)).cgPath
        self.okButton.layer.mask = mask
        
        let lineShape = CAShapeLayer()
        let line = UIBezierPath()
        line.move(to: CGPoint(x: 0.0, y: 0.0))
        line.addLine(to: CGPoint(x: containerSize.width, y: line.currentPoint.y))
        lineShape.path = line.cgPath
        lineShape.strokeColor = UIColor.black.withAlphaComponent(0.4).cgColor
        lineShape.lineWidth = 0.3
        lineShape.name = "lineShape"
        
        self.okButton.layer.sublayers?.forEach({ layer in
            if layer.name == "lineShape" {
                layer.removeFromSuperlayer()
            }
        })
        self.okButton.layer.addSublayer(lineShape)
    }
    
    func animateIn(from rect: CGRect, fromNode: ASDisplayNode) {
        let duration = CGFloat(0.4)
        self.setAnchorPoint(anchorPoint: CGPoint(x: 1, y: 0), forNode: self.containerNode)
        self.updateEmojiLayout()
        self.animatedEmojiNodes.forEach({ $0.playLoop() })
        
        CATransaction.begin()
        let animation = CAKeyframeAnimation(keyPath: #keyPath(CALayer.position))
        let curve = UIBezierPath()
        curve.move(to: CGPoint(x: rect.midX, y: rect.midY))
        curve.addQuadCurve(to: self.keyEmojisNode.layer.position, controlPoint: CGPoint(x: rect.midX, y: rect.midY + 50))
        animation.path = curve.cgPath
        animation.repeatCount = 0
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        self.keyEmojisNode.layer.add(animation, forKey: nil)
        CATransaction.commit()
        
        self.keyEmojisNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.1, removeOnCompletion: false)
        self.keyEmojisNode.layer.animateScale(from: rect.size.height / (self.keyEmojisNode.frame.size.height), to: 1.0, duration: duration, timingFunction: CAMediaTimingFunctionName.easeIn.rawValue, removeOnCompletion: false)
        
        self.containerNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: duration, removeOnCompletion: false)
        self.containerNode.layer.animateScale(from: 0.1, to: 1.0, duration: duration, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false)
    }
    
    func animateOut(to rect: CGRect, toNode: ASDisplayNode, completion: @escaping () -> Void) {
        let duration = CGFloat(0.06)
        self.setAnchorPoint(anchorPoint: CGPoint(x: 1, y: 0), forNode: self.containerNode)
        self.updateEmojiLayout()
        self.animatedEmojiNodes.forEach({ $0.stop() })

        self.containerNode.layer.animateScale(from: 1.0, to: 0.1, duration: duration, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false)
        self.containerNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: duration, removeOnCompletion: false)

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            completion()
        }
    
        let animation = CAKeyframeAnimation(keyPath: #keyPath(CALayer.position))
        let curve = UIBezierPath()
        curve.move(to: self.keyEmojisNode.layer.position)
        curve.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.midY), controlPoint: CGPoint(x: rect.midX, y: rect.midY + 50))
        animation.path = curve.cgPath
        animation.duration = 0.3
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        self.keyEmojisNode.layer.position = CGPoint(x: rect.midX, y: rect.midY)
        self.keyEmojisNode.layer.add(animation, forKey: nil)
        self.keyEmojisNode.layer.animateScaleX(from: 1.0, to: rect.size.width / self.keyEmojisNode.frame.size.width, duration: 0.3, removeOnCompletion: false)
        self.keyEmojisNode.layer.animateScaleY(from: 1.0, to: rect.size.height / self.keyEmojisNode.frame.size.height, duration: 0.3, removeOnCompletion: false)
        CATransaction.commit()
    }
    
    private func setAnchorPoint(anchorPoint: CGPoint, forNode node: ASDisplayNode) {
        var newPoint = CGPoint(x: node.bounds.size.width * anchorPoint.x,
                               y: node.bounds.size.height * anchorPoint.y)
        
        
        var oldPoint = CGPoint(x: node.bounds.size.width * node.layer.anchorPoint.x,
                               y: node.bounds.size.height * node.layer.anchorPoint.y)
        
        newPoint = newPoint.applying(node.view.transform)
        oldPoint = oldPoint.applying(node.view.transform)
        
        var position = node.view.layer.position
        position.x -= oldPoint.x
        position.x += newPoint.x
        
        position.y -= oldPoint.y
        position.y += newPoint.y
        
        node.layer.position = position
        node.layer.anchorPoint = anchorPoint
    }
    
    func obtainEmojiNodes(keyText: String, for context: AccountContext, size: CGSize) -> [DefaultAnimatedStickerNodeImpl] {
        let emojis = keyText.emojis
        var emojiNodes: [DefaultAnimatedStickerNodeImpl] = []

        let hasStickersWithoutAnimation: Bool = {
            for emoji in emojis {
                if context.animatedEmojiStickers[emoji]?.first?.file == nil {
                    return true
                }
            }
            return false
        }()

        for emoji in emojis {
            
            let animationNode = DefaultAnimatedStickerNodeImpl()
            animationNode.displaysAsynchronously = true

            let emojiFile: TelegramMediaFile? = context.animatedEmojiStickers[emoji]?.first?.file

            if emojiFile != nil && !hasStickersWithoutAnimation {
                animationNode.setup(source: AnimatedStickerResourceSource(account: context.account, resource: emojiFile!.resource, fitzModifier: nil), width: Int(size.width), height: Int(size.height), playbackMode: .loop, mode: .direct(cachePathPrefix: nil))
                animationNode.frame = CGRect(origin: CGPoint(), size: size)
                emojiNodes.append(animationNode)
            } else {
                animationNode.frame = CGRect(origin: CGPoint(), size: size)
                let staticEmojiImageView = self.generateStaticEmojiImageView(emoji: emoji, size: size)
                animationNode.view.addSubview(staticEmojiImageView)
                emojiNodes.append(animationNode)
            }
        }
        return emojiNodes
    }
    
    private func generateStaticEmojiImageView(emoji: String, size: CGSize) -> UIImageView {
        let font = UIFont.systemFont(ofSize: size.width - 5)
        let attributes = [NSAttributedString.Key.font: font]
        let imageRect = CGRect(origin: CGPoint(), size: size)

        
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        UIColor.clear.set()
        UIRectFill(CGRect(origin: CGPoint(), size: size))
        emoji.draw(at: CGPoint.zero, withAttributes: attributes)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        let emojiImageView = UIImageView(frame: imageRect)
        emojiImageView.image = image

        return emojiImageView
    }
    
    private func updateColors() {
        let filter = CIFilter(name: "CIOverlayBlendMode")
        if self.hasVideo {
            self.containerNode.backgroundColor = UIColor.black
            self.containerNode.layer.backgroundColor = UIColor.black.withAlphaComponent(0.5).cgColor
            self.containerNode.layer.compositingFilter = filter

        } else {
            self.containerNode.backgroundColor = UIColor.white
            self.containerNode.layer.backgroundColor = UIColor.white.withAlphaComponent(0.25).cgColor
            self.containerNode.layer.compositingFilter = filter
        }
    }
    
    private func updateTextNodes(with color: UIColor) {
        if let infoString = self.infoTextNode.attributedText?.string {
            self.infoTextNode.attributedText = NSAttributedString(string: infoString, font: Font.semibold(16.0), textColor: color, paragraphAlignment: .center)
        }
        if let infoTitleString = self.infoTextNode.attributedText?.string {
            self.infoTitleNode.attributedText = NSAttributedString(string: infoTitleString, font: Font.semibold(16.0), textColor: color, paragraphAlignment: .center)
        }
    }
    
    @objc func buttonPressed(_ sender: UIButton) {
        self.dismiss()
    }
    
    @objc func tapGesture(_ recognizer: UITapGestureRecognizer) {
        if case .ended = recognizer.state {
            self.dismiss()
        }
    }
}

