//
//  CallAvatarNode.swift
//  _idx_TelegramCallsUI_491AF1CC_ios_min11.0
//
//  Created by Ivan Ghiba on 26.02.2023.
//

import UIKit
import Display
import AsyncDisplayKit
import AvatarNode
import AudioBlob
import SwiftSignalKit
import AccountContext
import TelegramCore
import TelegramPresentationData
import Postbox

private let nodeHeight: CGFloat = 172
private let avatarRect = CGRect(x: 18.0, y: 18.0, width: 136.0, height: 136.0)

public class CallAvatarNode: ASDisplayNode {

    private let avatarNode: AvatarNode
    private var audioLevelView: VoiceBlobView?
    
    private var validLayout: (CGFloat, CGFloat)?

    private let myAudioLevelPipe = ValuePipe<Float>()
    public var myAudioLevel: Signal<Float, NoError> {
        return self.myAudioLevelPipe.signal()
    }
    private let callStatusPromise = Promise<PresentationCallState>()
    public var callStatus: Signal<PresentationCallState, NoError> {
        return self.callStatusPromise.get()
    }

    private let audioLevelDisposable = MetaDisposable()
    private let callStatusDisposable = MetaDisposable()
    
    private let call: PresentationCall
    
    private lazy var timer: SwiftSignalKit.Timer = SwiftSignalKit.Timer(timeout: 10.0, repeat: false, completion: {
        self.disableAvatarWaves()
    }, queue: Queue.mainQueue())

    init(call: PresentationCall) {
        self.call = call
        self.avatarNode = AvatarNode(font: avatarPlaceholderFont(size: 26.0))
        
        super.init()
        
        self.frame = CGRect(x: 0, y: 0, width: nodeHeight, height: nodeHeight)
        self.avatarNode.frame = avatarRect
        self.avatarNode.imageNode.layer.cornerRadius = self.avatarNode.frame.width / 2
        self.avatarNode.view.layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        
        self.addSubnode(avatarNode)
        
        self.updateAudioLevelDisposable()
        self.initiatingAnimation()
        
        if let peer = call.peer {
            self.updatePeer(peer)
        }
        
        if UIDevice.current.isProximityMonitoringEnabled {
            NotificationCenter.default.addObserver(forName: UIDevice.proximityStateDidChangeNotification, object: nil, queue: OperationQueue.main) { [weak self] notification in
                
                if let device = notification.object as? UIDevice {
                    if device.proximityState {
                        self?.disableAvatarWaves()
                    }
                }
            }
        }
    }
    
    deinit {
        self.timer.invalidate()
    }
    
    public func updatePeer(_ peer: Peer) {
        let theme = makeDefaultPresentationTheme(reference: .dayClassic, serviceBackgroundColor: nil)
        self.avatarNode.setPeer(context: call.context, account: call.context.account, theme: theme, peer: EnginePeer(peer))
    }
    
    public func updateLayout(constrainedWidth: CGFloat, topInset: CGFloat, transition: ContainedViewLayoutTransition) -> CGFloat {
        self.validLayout = (constrainedWidth, topInset)
        return self.updateAvatarLayout(width: constrainedWidth, topInset: topInset)
    }
    
    private func updateAvatarLayout(width: CGFloat, topInset: CGFloat) -> CGFloat {
        return nodeHeight
    }
    
    private func updateAudioLevelDisposable() {
        self.audioLevelDisposable.set((call.audioLevel
        |> deliverOnMainQueue).start(next: { [weak self] value in
            guard let strongSelf = self else {
                return
            }
            if strongSelf.audioLevelView == nil {
                let blobFrame = CGRect(origin: strongSelf.avatarNode.frame.origin.offsetBy(dx: -18, dy: -18), size: CGSize(width: 172.0, height: 172.0))
                
                let audioLevelView = VoiceBlobView(
                    frame: blobFrame,
                    maxLevel: 0.8,
                    smallBlobRange: (0, 0),
                    mediumBlobRange: (0.75, 0.85),
                    bigBlobRange: (0.9, 1.0)
                )
                
                let maskRect = CGRect(origin: .zero, size: blobFrame.size)
                let playbackMaskLayer = CAShapeLayer()
                playbackMaskLayer.frame = maskRect
                playbackMaskLayer.fillRule = .evenOdd
                let maskPath = UIBezierPath()
                maskPath.append(UIBezierPath(roundedRect: maskRect.insetBy(dx: 26, dy: 26), cornerRadius: strongSelf.avatarNode.frame.width / 2 ))
                maskPath.append(UIBezierPath(rect: maskRect))
                playbackMaskLayer.path = maskPath.cgPath

                audioLevelView.setColor(UIColor(rgb: 0xffffff))
                strongSelf.audioLevelView = audioLevelView
                
                strongSelf.view.insertSubview(audioLevelView, at: 0)
            }
            
            strongSelf.audioLevelView?.updateLevel(CGFloat(value) * 2.0)
            if value > 0.0 {
                strongSelf.audioLevelView?.startAnimating()
            } else {
                strongSelf.audioLevelView?.stopAnimating(duration: 0.5)
            }
        }))
    }
    
    func initiatingAnimation() {
        self.callStatusDisposable.set((call.state
        |> deliverOnMainQueue).start(next: { [weak self] state in
            guard let strongSelf = self else {
                return
            }

            switch state.state {
            case  .ringing:
                let animationDuration: TimeInterval = 3.0
                let animationScale: CGFloat = 1.1

                let animationGroup = CAAnimationGroup()
                animationGroup.duration = animationDuration
                animationGroup.repeatCount = .infinity

                let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
                scaleAnimation.fromValue = 1.0
                scaleAnimation.toValue = animationScale
                scaleAnimation.autoreverses = true

                strongSelf.avatarNode.layer.add(scaleAnimation, forKey: "wavesAnimation")
                
            case .active(_, _, _):
                strongSelf.avatarNode.layer.animateScale(from: 1.0, to: 1.05, duration: 0.75, delay: 0.1, timingFunction: kCAMediaTimingFunctionSpring, completion: { _ in
                    strongSelf.avatarNode.layer.animateScale(from: 1.1, to: 1.05, duration: 0.25, delay: 0.1, timingFunction: kCAMediaTimingFunctionSpring)
                    strongSelf.callStatusDisposable.dispose()
                })
                strongSelf.timer.start()
                
            default:
                break
            }
        }))
    }
    
    public func animateIn() {
        let duration: CGFloat = 0.1
        
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: duration, removeOnCompletion: false)
        self.layer.animateScale(from: 0.3, to: 1.0, duration: duration, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false)
    }
    
    public func animateOut() {
        let duration: CGFloat = 0.1
        
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: duration, removeOnCompletion: false)
        self.layer.animateScale(from: 1.0, to: 0.3, duration: duration, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false)
    }
    
    private func disableAvatarWaves() {
        self.audioLevelDisposable.dispose()
        self.view.subviews.forEach { view in
            if let voiceBlobView = view as? VoiceBlobView {
                voiceBlobView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.3, completion: { _ in
                    voiceBlobView.isHidden = true
                })
            }
        }
    }
 
}
    
