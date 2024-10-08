import Foundation
import UIKit
import Display
import ComponentFlow
import HierarchyTrackingLayer

private let shadowImage: UIImage? = {
    UIImage(named: "Stories/PanelGradient")
}()

final class VideoChatVideoLoadingEffectView: UIView {
    private let duration: Double
    private let hasCustomBorder: Bool
    private let playOnce: Bool
    
    private let hierarchyTrackingLayer: HierarchyTrackingLayer
    
    private let gradientWidth: CGFloat
    
    let portalSource: PortalSourceView
    
    private let backgroundView: UIImageView
    
    private let borderGradientView: UIImageView
    private let borderContainerView: UIView
    let borderMaskLayer: SimpleShapeLayer
    
    private var didPlayOnce = false
    
    init(effectAlpha: CGFloat, borderAlpha: CGFloat, gradientWidth: CGFloat = 200.0, duration: Double, hasCustomBorder: Bool, playOnce: Bool) {
        self.portalSource = PortalSourceView()
        
        self.hierarchyTrackingLayer = HierarchyTrackingLayer()
        
        self.duration = duration
        self.hasCustomBorder = hasCustomBorder
        self.playOnce = playOnce
        
        self.gradientWidth = gradientWidth
        self.backgroundView = UIImageView()
        
        self.borderGradientView = UIImageView()
        self.borderContainerView = UIView()
        self.borderMaskLayer = SimpleShapeLayer()
        
        super.init(frame: .zero)
        
        self.portalSource.backgroundColor = .red
        
        self.portalSource.layer.addSublayer(self.hierarchyTrackingLayer)
        self.hierarchyTrackingLayer.didEnterHierarchy = { [weak self] in
            guard let self, self.bounds.width != 0.0 else {
                return
            }
            self.updateAnimations(size: self.bounds.size)
        }
        
        let generateGradient: (CGFloat) -> UIImage? = { baseAlpha in
            return generateImage(CGSize(width: self.gradientWidth, height: 16.0), opaque: false, scale: 1.0, rotatedContext: { size, context in
                context.clear(CGRect(origin: CGPoint(), size: size))
                
                let foregroundColor = UIColor(white: 1.0, alpha: min(1.0, baseAlpha * 4.0))
                
                if let shadowImage {
                    UIGraphicsPushContext(context)
                    
                    for i in 0 ..< 2 {
                        let shadowFrame = CGRect(origin: CGPoint(x: CGFloat(i) * (size.width * 0.5), y: 0.0), size: CGSize(width: size.width * 0.5, height: size.height))
                        
                        context.saveGState()
                        context.translateBy(x: shadowFrame.midX, y: shadowFrame.midY)
                        context.rotate(by: CGFloat(i == 0 ? 1.0 : -1.0) * CGFloat.pi * 0.5)
                        let adjustedRect = CGRect(origin: CGPoint(x: -shadowFrame.height * 0.5, y: -shadowFrame.width * 0.5), size: CGSize(width: shadowFrame.height, height: shadowFrame.width))
                        
                        context.clip(to: adjustedRect, mask: shadowImage.cgImage!)
                        context.setFillColor(foregroundColor.cgColor)
                        context.fill(adjustedRect)
                        
                        context.restoreGState()
                    }
                    
                    UIGraphicsPopContext()
                }
            })
        }
        self.backgroundView.image = generateGradient(effectAlpha)
        self.portalSource.addSubview(self.backgroundView)
        
        self.borderGradientView.image = generateGradient(borderAlpha)
        self.borderContainerView.addSubview(self.borderGradientView)
        self.portalSource.addSubview(self.borderContainerView)
        self.borderContainerView.layer.mask = self.borderMaskLayer
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func updateAnimations(size: CGSize) {
        if self.backgroundView.layer.animation(forKey: "shimmer") != nil || (self.playOnce && self.didPlayOnce) {
            return
        }

        let animation = self.backgroundView.layer.makeAnimation(from: 0.0 as NSNumber, to: (size.width + self.gradientWidth + size.width * 0.2) as NSNumber, keyPath: "position.x", timingFunction: CAMediaTimingFunctionName.easeOut.rawValue, duration: self.duration, delay: 0.0, mediaTimingFunction: nil, removeOnCompletion: true, additive: true)
        animation.repeatCount = self.playOnce ? 1 : Float.infinity
        self.backgroundView.layer.add(animation, forKey: "shimmer")
        self.borderGradientView.layer.add(animation, forKey: "shimmer")
        
        self.didPlayOnce = true
    }
    
    func update(size: CGSize, transition: ComponentTransition) {
        if self.backgroundView.bounds.size != size {
            self.backgroundView.layer.removeAllAnimations()
            
            if !self.hasCustomBorder {
                self.borderMaskLayer.fillColor = nil
                self.borderMaskLayer.strokeColor = UIColor.white.cgColor
                let lineWidth: CGFloat = 3.0
                self.borderMaskLayer.lineWidth = lineWidth
                self.borderMaskLayer.path = UIBezierPath(roundedRect: CGRect(origin: CGPoint(), size: size).insetBy(dx: lineWidth * 0.5, dy: lineWidth * 0.5), cornerRadius: 12.0).cgPath
            }
        }
        
        transition.setFrame(view: self.backgroundView, frame: CGRect(origin: CGPoint(x: -self.gradientWidth, y: 0.0), size: CGSize(width: self.gradientWidth, height: size.height)))
        
        transition.setFrame(view: self.borderContainerView, frame: CGRect(origin: CGPoint(), size: size))
        transition.setFrame(view: self.borderGradientView, frame: CGRect(origin: CGPoint(x: -self.gradientWidth, y: 0.0), size: CGSize(width: self.gradientWidth, height: size.height)))
        
        self.updateAnimations(size: size)
    }
}
