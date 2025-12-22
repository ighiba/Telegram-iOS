import UIKit

public enum LegacyGlassQualityLevel {
    case high
    case medium
    case low
}

public enum LegacyGlassUpdateFrequency {
    case automatic
    case fps(capture: Double, render: Int)
    
    public var captureFrameRate: Double {
        switch self {
        case .automatic:
            return 60.0
        case .fps(let capture, _):
            return capture
        }
    }
    
    public var renderFrameRate: Int {
        switch self {
        case .automatic:
            return 60
        case .fps(_, let render):
            return render
        }
    }
}

public struct LegacyGlassQualityProfile {
    public var level: LegacyGlassQualityLevel
    public var captureScale: CGFloat
    public var captureScaleBlurred: CGFloat
    public var captureAutoUpdateSlowDebounce: TimeInterval
    public var dynamicFastFrequency: LegacyGlassUpdateFrequency
    public var dynamicSlowFrequency: LegacyGlassUpdateFrequency
    public var staticFrequency: LegacyGlassUpdateFrequency

    public static var automatic: LegacyGlassQualityProfile {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let scale = UIScreen.main.scale
        
        let level: LegacyGlassQualityLevel
        if lowPower {
            level = .low
        } else if scale <= 2.0 {
            level = .medium
        } else {
            level = .high
        }
        
        switch level {
        case .high:
            return .high
        case .medium:
            return .medium
        case .low:
            return .low
        }
    }
    
    public static let high = LegacyGlassQualityProfile(
        level: .high,
        captureScale: 0.75 * UIScreen.main.scale,
        captureScaleBlurred: 0.5,
        captureAutoUpdateSlowDebounce: 10.0,
        dynamicFastFrequency: .automatic,
        dynamicSlowFrequency: .fps(capture: 1, render: 60),
        staticFrequency: .fps(capture: 1, render: 60)
    )
    
    public static let medium = LegacyGlassQualityProfile(
        level: .medium,
        captureScale: 0.5 * UIScreen.main.scale,
        captureScaleBlurred: 0.4,
        captureAutoUpdateSlowDebounce: 5.0,
        dynamicFastFrequency: .automatic,
        dynamicSlowFrequency: .fps(capture: 1, render: 30),
        staticFrequency: .fps(capture: 1, render: 30)
    )
    
    public static let low = LegacyGlassQualityProfile(
        level: .low,
        captureScale: 0.5 * UIScreen.main.scale,
        captureScaleBlurred: 0.3,
        captureAutoUpdateSlowDebounce: 3.0,
        dynamicFastFrequency: .fps(capture: 45, render: 30),
        dynamicSlowFrequency: .fps(capture: 1, render: 24),
        staticFrequency: .fps(capture: 1, render: 24)
    )
}
