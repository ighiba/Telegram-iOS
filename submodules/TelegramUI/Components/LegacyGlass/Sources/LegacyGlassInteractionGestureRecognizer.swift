import Foundation
import UIKit
import UIKit.UIGestureRecognizerSubclass

public final class LegacyGlassInteractionGestureRecognizer: UIGestureRecognizer {
    public var onBegan: ((CGPoint) -> Void)?
    public var onMoved: ((CGPoint) -> Void)?
    public var onEnded: (() -> Void)?
    public var onCancelled: (() -> Void)?
    
    override public func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if touches.count == 1, let touch = touches.first {
            self.state = .began
            let point = touch.location(in: self.view)
            self.onBegan?(point)
        } else {
            self.state = .failed
        }
    }
    
    override public func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        if touches.count == 1, let touch = touches.first, self.state == .began || self.state == .changed {
            self.state = .changed
            let point = touch.location(in: self.view)
            self.onMoved?(point)
        } else if touches.count > 1 {
            self.state = .cancelled
            self.onCancelled?()
        }
    }
    
    override public func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        if self.state == .began || self.state == .changed {
            self.state = .ended
            self.onEnded?()
        }
    }
    
    override public func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        if self.state == .began || self.state == .changed {
            self.state = .cancelled
            self.onCancelled?()
        }
    }
    
    override public func reset() {
        super.reset()
    }
}
