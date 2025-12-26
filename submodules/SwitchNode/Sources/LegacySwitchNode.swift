import Foundation
import UIKit
import Display
import AsyncDisplayKit
import LegacyGlass

open class LegacySwitchNode: ASDisplayNode, SwitchNodeProtocol {
    public var valueUpdated: ((Bool) -> Void)?
    
    override public var backgroundColor: UIColor? {
        didSet {
            if self.isNodeLoaded {
                if oldValue != self.backgroundColor {
                    (self.view as! LegacySwitchView).backgroundColor = self.backgroundColor
                }
            }
        }
    }
    
    public var frameColor = UIColor(red: 0.92, green: 0.92, blue: 0.96, alpha: 0.3) {
        didSet {
            if self.isNodeLoaded {
                if oldValue != self.frameColor {
                    (self.view as! LegacySwitchView).tintColor = self.frameColor
                }
            }
        }
    }
    public var handleColor = UIColor(rgb: 0xffffff) {
        didSet {
            if self.isNodeLoaded {
                //(self.view as! UISwitch).thumbTintColor = self.handleColor
            }
        }
    }
    public var contentColor = UIColor(red: 0.4, green: 0.81, blue: 0.4, alpha: 1.0) {
        didSet {
            if self.isNodeLoaded {
                if oldValue != self.contentColor {
                    (self.view as! LegacySwitchView).onTintColor = self.contentColor
                }
            }
        }
    }
    
    private var _isOn: Bool = false
    public var isOn: Bool {
        get {
            return self._isOn
        } set(value) {
            if (value != self._isOn) {
                self._isOn = value
                if self.isNodeLoaded {
                    (self.view as! LegacySwitchView).setOn(value, animated: false, shouldSendAction: false)
                }
            }
        }
    }
    
    override public init() {
        super.init()
        
        self.setViewBlock({
            return LegacySwitchView()
        })
    }
    
    override open func didLoad() {
        super.didLoad()
        
        self.view.isAccessibilityElement = false

        (self.view as! LegacySwitchView).tintColor = self.frameColor
        (self.view as! LegacySwitchView).onTintColor = self.contentColor
        
        (self.view as! LegacySwitchView).setOn(self._isOn, animated: false)
        
        (self.view as! LegacySwitchView).addTarget(self, action: #selector(switchValueChanged(_:)), for: .valueChanged)
    }
    
    public func setOn(_ value: Bool, animated: Bool) {
        self._isOn = value
        if self.isNodeLoaded {
            (self.view as! LegacySwitchView).setOn(value, animated: animated, shouldSendAction: false)
        }
    }
    
    override open func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        return CGSize(width: 63.0, height: 28.0)
    }
    
    @objc func switchValueChanged(_ view: LegacySwitchView) {
        self._isOn = view.isOn
        self.valueUpdated?(self._isOn)
    }
}
