//
//  CallBackgroundNode.swift
//  _idx_TelegramCallsUI_5DE3EDBD_ios_min11.0
//
//  Created by Ivan Ghiba on 24.02.2023.
//

import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import GradientBackground

private struct CallBackgroundNodeTransition {
    let colors: [UIColor]
}

public class CallBackgroundNode: ASDisplayNode {
    enum CallStatus {
        case initiating
        case established
    }
    
    final class CallStatusTheme {
        public let weakSignalColors = [UIColor(rgb: 0xb84498),
                                       UIColor(rgb: 0xf4992e),
                                       UIColor(rgb: 0xc94986),
                                       UIColor(rgb: 0xff7e46)]
        
        var callStatus: CallStatus
        
        init(status: CallStatus) {
            self.callStatus = status
        }

        public func obtainCurrentColors() -> [UIColor] {
            return obtainColors(by: self.callStatus)
        }
        
        public func obtainColors(by status: CallStatus) -> [UIColor] {
            switch status {
            case .initiating:
                return [UIColor(rgb: 0x5295d6),
                        UIColor(rgb: 0x616ad5),
                        UIColor(rgb: 0xfc65d4),
                        UIColor(rgb: 0x7261da)]
            case .established:
                return [UIColor(rgb: 0x53a6de),
                        UIColor(rgb: 0x398d6f),
                        UIColor(rgb: 0xbac05d),
                        UIColor(rgb: 0x3c9c8f)]
            }
        }
    }
    
    private var callStatusTheme = CallStatusTheme(status: .initiating)
    
    private let animatedTransition = ContainedViewLayoutTransition.animated(duration: 1.0, curve: .linear)
    
    private var gradientColors: [UIColor] = []
    private var backgroundGradientNode: GradientBackgroundNode
    private var weakSignalBackgroundGradientNode: GradientBackgroundNode

    private var enqueuedTransitions: [CallBackgroundNodeTransition] = [] {
        didSet {
            if self.enqueuedTransitions.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
                    self?.isAnimating = false
                }
            }
        }
    }
    private var enqueuedReservedTransitions: [CallBackgroundNodeTransition] = []
    
    private var isAnimating: Bool = false
    public var canStartAnimating: Bool = false

    var isWeakSignal: Bool = false {
        didSet {
            guard isWeakSignal != oldValue else {
                return
            }
            if isWeakSignal {
                self.weakSignalBackgroundAnimateIn()
            } else {
                self.weakSignalBackgroundAnimateOut(completion: {})
            }
        }
    }
    
    private lazy var timer: SwiftSignalKit.Timer = SwiftSignalKit.Timer(timeout: 10.0, repeat: false, completion: {
        self.fireTimer()
    }, queue: Queue.mainQueue())

    public override init() {
        let defaultColors = callStatusTheme.obtainColors(by: .initiating)
        let weakSignalColors = callStatusTheme.weakSignalColors
        
        self.gradientColors = defaultColors
        
        self.backgroundGradientNode = createGradientBackgroundNode(colors: self.gradientColors, useSharedAnimationPhase: true)
        self.weakSignalBackgroundGradientNode = createGradientBackgroundNode(colors: weakSignalColors, useSharedAnimationPhase: true)
        
        super.init()
        
        let frame = CGRect(origin: CGPoint(), size: UIScreen.main.bounds.size)
        self.frame = frame

        let backgroundGradientNodeFrame = CGRect(x: 0, y: 0, width: self.frame.width, height: self.frame.height)
        self.backgroundGradientNode.frame = backgroundGradientNodeFrame
        self.backgroundGradientNode.backgroundColor = .black
        self.addSubnode(backgroundGradientNode)
        self.weakSignalBackgroundGradientNode.frame = backgroundGradientNodeFrame
        self.weakSignalBackgroundGradientNode.alpha = 0
        self.backgroundGradientNode.addSubnode(weakSignalBackgroundGradientNode)
        
        self.displaysAsynchronously = true
    }
    
    deinit {
        self.timer.invalidate()
    }

    public override func nodeDidLoad() {
        super.nodeDidLoad()
        self.backgroundColor = .black
        self.gradientColors = self.obtainCurrentColors()
    }
    
    public func getAnimationState() -> Bool {
        return self.isAnimating
    }
    
    public func obtainCurrentColors() -> [UIColor] {
        return self.callStatusTheme.obtainCurrentColors()
    }
    
    private func enqueueTransition(_ transition: CallBackgroundNodeTransition, queue: inout [CallBackgroundNodeTransition]) {
        queue.append(transition)
    }
    
    private func dequeueGeneralTransition() {
        if let transition = self.enqueuedTransitions.first {
            self.enqueuedTransitions.remove(at: 0)
            print(self.enqueuedTransitions.count)
            self.isAnimating = true
            self.backgroundGradientNode.setColorsForTransition(newColors: transition.colors)
            self.backgroundGradientNode.animateGradientRotation(transition: animatedTransition, extendAnimation: false, backwards: false, completion: { [weak self] in
                self?.dequeueGeneralTransition() })
        }
    }
    
    private func dequeueReservedTransition() {
        if let transition = self.enqueuedReservedTransitions.first {
            self.enqueuedReservedTransitions.remove(at: 0)
            print(self.enqueuedReservedTransitions.count)
            self.isAnimating = true
            self.weakSignalBackgroundGradientNode.setColorsForTransition(newColors: transition.colors)
            self.weakSignalBackgroundGradientNode.animateGradientRotation(transition: animatedTransition, extendAnimation: false, backwards: false, completion: { [weak self] in
                self?.dequeueReservedTransition()
            })
        }
    }
    
    private func queueAppendTransitions(transition: CallBackgroundNodeTransition, count: Int, queue: inout [CallBackgroundNodeTransition]) {
        guard count > 1, count < 100 else {
            return
        }
        
        for _ in 0 ..< count {
            queue.append(transition)
        }
    }
    
    private func queueChangeTransitions(transition: CallBackgroundNodeTransition, count: Int, queue: inout [CallBackgroundNodeTransition]) {
        guard count > 1, count < 100 else {
            return
        }
        
        var transitions: [CallBackgroundNodeTransition] = []
        for _ in 0 ..< count {
            transitions.append(transition)
        }
        queue = transitions
    }
    
    private func startAnimation() {
        if !self.isAnimating {
            self.dequeueGeneralTransition()
        }
    }
    
    private func stopAnimation() {
        self.enqueuedTransitions = []
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            self?.isAnimating = false
        }
    }
    
    private func stopReservedAnimation() {
        self.enqueuedReservedTransitions = []
    }
    
    private func weakSignalBackgroundAnimateIn() {
        let duration = 0.675
        let weakSignalColors = self.callStatusTheme.weakSignalColors
        let weakSignalTransition = CallBackgroundNodeTransition(colors: weakSignalColors)
        
        self.queueAppendTransitions(transition: weakSignalTransition, count: 9, queue: &enqueuedReservedTransitions)
        
        self.weakSignalBackgroundGradientNode.setColorsForTransition(newColors: weakSignalColors)
        
        UIView.animate(withDuration: duration, delay: 0.0, options: [.beginFromCurrentState], animations: { [weak self] in
            self?.weakSignalBackgroundGradientNode.alpha = 1.0
        }, completion: { _ in
            self.stopAnimation()
            self.dequeueReservedTransition()
        })

    }
    
    private func weakSignalBackgroundAnimateOut(completion: @escaping () -> Void) {
        let duration = 0.675
        let mainTransition = CallBackgroundNodeTransition(colors: self.gradientColors)
        
        UIView.animate(withDuration: duration, delay: 0.0, options: [.beginFromCurrentState], animations: { [weak self] in
            self?.weakSignalBackgroundGradientNode.alpha = 0.0
        })
        
        self.queueChangeTransitions(transition: mainTransition, count: 10, queue: &enqueuedTransitions)
        self.stopReservedAnimation()
        self.startAnimation()
    }
    
    public func beginAnimating() {
        self.timer.start()
        self.callStatusTheme.callStatus = .initiating
        let initiatingColors = self.callStatusTheme.obtainColors(by: .initiating)
        
        self.queueChangeTransitions(transition: CallBackgroundNodeTransition(colors: initiatingColors), count: 20, queue: &enqueuedTransitions)
        
        self.startAnimation()
        self.resetAnimationTimer()
    }
    
    public func changeBackgroundThemeInitiating() {
        guard callStatusTheme.callStatus != .initiating else {
            return
        }
        self.callStatusTheme.callStatus = .initiating
        let initiatingColors = self.callStatusTheme.obtainColors(by: .initiating)
        self.gradientColors = initiatingColors
        self.queueChangeTransitions(transition: CallBackgroundNodeTransition(colors: initiatingColors), count: 20, queue: &enqueuedTransitions)
        guard self.canStartAnimating else {
            return
        }
        self.startAnimation()
    }
    
    public func changeBackgroundThemeEstablished() {
        guard callStatusTheme.callStatus != .established else {
            return
        }
        self.callStatusTheme.callStatus = .established
        let establishedColors = self.callStatusTheme.obtainColors(by: .established)
        self.gradientColors = establishedColors
        self.queueChangeTransitions(transition: CallBackgroundNodeTransition(colors: establishedColors), count: 20, queue: &enqueuedTransitions)
        guard self.canStartAnimating else {
            return
        }
        self.startAnimation()
    }
    
    public func changeBackgroundThemeWeakSignal(weakSignal: Bool) {
        self.isWeakSignal = weakSignal
    }

    public func resetAnimationTimer() {
        self.timer.start()
        self.queueChangeTransitions(transition: CallBackgroundNodeTransition(colors: self.gradientColors), count: 20, queue: &enqueuedTransitions)
        guard self.canStartAnimating else {
            return
        }
        self.startAnimation()
    }
    
    @objc func fireTimer() {
        self.stopAnimation()
    }
    
    public func updateLayout(size: CGSize) {
        guard !isAnimating else {
            return
        }
        self.backgroundGradientNode.updateLayout(size: size, transition: .immediate, extendAnimation: false, backwards: false, completion: {})
        self.weakSignalBackgroundGradientNode.updateLayout(size: size, transition: .immediate, extendAnimation: false, backwards: false, completion: {})
        self.canStartAnimating = true
    }

}


