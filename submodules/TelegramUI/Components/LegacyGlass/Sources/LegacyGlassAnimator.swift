import Foundation

enum LegacyGlassEasing {
    case linear
    case easeIn
    case easeOut
    case easeInOut
    
    func value(at t: CGFloat) -> CGFloat {
        switch self {
        case .linear:
            return t
        case .easeIn:
            return t * t * t
        case .easeOut:
            let p = t - 1.0
            return p * p * p + 1.0
        case .easeInOut:
            if t < 0.5 {
                return 4.0 * t * t * t
            } else {
                let p = -2.0 * t + 2.0
                return 1.0 - (p * p * p) / 2.0
            }
        }
    }
}

struct LegacyGlassAnimationSegment {
    
    let from: CGFloat
    let to: CGFloat
    let duration: CGFloat
    let easing: LegacyGlassEasing
    var elapsed: CGFloat = 0.0
    let onBegin: (() -> Void)?
    let onComplete: (() -> Void)?
    
    fileprivate var hasStarted: Bool = false
    
    init(from: CGFloat, to: CGFloat, duration: CGFloat, easing: LegacyGlassEasing, elapsed: CGFloat, onBegin: (() -> Void)? = nil, onComplete: (() -> Void)? = nil) {
        self.from = from
        self.to = to
        self.duration = duration
        self.easing = easing
        self.elapsed = elapsed
        self.onBegin = onBegin
        self.onComplete = onComplete
    }
    
    func value(at time: CGFloat) -> CGFloat {
        let clampedT = max(0.0, min(1.0, time / max(duration, 0.0001)))
        let eased = easing.value(at: clampedT)
        return from * (1.0 - eased) + to * eased
    }
    
    var isFinished: Bool {
        self.elapsed >= self.duration
    }
}

final class LegacyGlassAnimator {
    var isRunning: Bool {
        !self.segments.isEmpty
    }
    
    private var segments: [LegacyGlassAnimationSegment] = []
    private(set) var currentValue: CGFloat = 0.0
    
    func reset(to value: CGFloat) {
        self.segments.removeAll()
        self.currentValue = value
    }
    
    func enqueue(from: CGFloat, to: CGFloat, duration: CGFloat, easing: LegacyGlassEasing, onBegin: (() -> Void)?, onComplete: (() -> Void)? = nil) {
        self.segments = [
            LegacyGlassAnimationSegment(from: from, to: to, duration: duration, easing: easing, elapsed: 0.0, onBegin: onBegin, onComplete: onComplete)
        ]
    }
    
    func enqueueAnimationSegments(_ segments: [LegacyGlassAnimationSegment]) {
        self.segments = segments
    }
    
    func tick(delta: CGFloat) {
        guard !self.segments.isEmpty else { return }
        
        var head = self.segments.removeFirst()
        if !head.hasStarted {
            head.hasStarted = true
            head.onBegin?()
        }
        
        head.elapsed += delta
        self.currentValue = head.value(at: head.elapsed)
        
        if head.isFinished {
            self.currentValue = head.to
            head.onComplete?()
        } else {
            self.segments.insert(head, at: 0)
        }
    }
}
