import Foundation

public struct LegacyGlassStyle {
    public static let clear = LegacyGlassStyle(
        refractionStrength: 1.61,
        refractionEdgeWidth: 0.60,
        refractionCenterStrength: 0.0,
        refractionEdgeStrength: -0.25,
        refractionXScale: 1.0,
        refractionYScale: 0.8,
        dimmingStrength: 0.3,
        rimHighlightWidth: 3.0,
        rimHighlightStrength: 1.0,
        chromaticAberrationStrength: 0.25,
        coreRadius: 0.36,
        idleOuterShadowWidth: 0.1,
        idleOuterShadowOpacity: 0.1,
        activeOuterShadowWidth: 0.1,
        activeOuterShadowOpacity: 0.1,
        isBlurEnabled: false
    )
    
    public static let regular = LegacyGlassStyle(
        refractionStrength: 1.81,
        refractionEdgeWidth: 0.75,
        refractionCenterStrength: 0.0,
        refractionEdgeStrength: -0.45,
        refractionXScale: 1.0,
        refractionYScale: 0.8,
        dimmingStrength: 0.5,
        rimHighlightWidth: 2.0,
        rimHighlightStrength: 1.0,
        chromaticAberrationStrength: 0.25,
        coreRadius: 0.6,
        idleOuterShadowWidth: 0.1,
        idleOuterShadowOpacity: 0.15,
        activeOuterShadowWidth: 0.1,
        activeOuterShadowOpacity: 0.15,
        isBlurEnabled: true
    )
    
    public var refractionStrength: Float
    public var refractionEdgeWidth: Float
    public var refractionCenterStrength: Float
    public var refractionEdgeStrength: Float
    public var refractionXScale: Float
    public var refractionYScale: Float
    public var dimmingStrength: Float
    public var rimHighlightWidth: Float
    public var rimHighlightStrength: Float
    public var chromaticAberrationStrength: Float
    public var coreRadius: Float
    public var idleOuterShadowWidth: Float
    public var idleOuterShadowOpacity: Float
    public var activeOuterShadowWidth: Float
    public var activeOuterShadowOpacity: Float
    public var isBlurEnabled: Bool
    public var isIdleImageEnabled: Bool
    public var isIdleImageShadowEnabled: Bool
    public var idleImageShadowOffset: Float
    public var idleImageShadowBlur: Float
    public var idleImageShadowOpacity: Float
    
    public init(
        refractionStrength: Float,
        refractionEdgeWidth: Float,
        refractionCenterStrength: Float,
        refractionEdgeStrength: Float,
        refractionXScale: Float,
        refractionYScale: Float,
        dimmingStrength: Float,
        rimHighlightWidth: Float,
        rimHighlightStrength: Float,
        chromaticAberrationStrength: Float,
        coreRadius: Float,
        idleOuterShadowWidth: Float,
        idleOuterShadowOpacity: Float,
        activeOuterShadowWidth: Float,
        activeOuterShadowOpacity: Float,
        isBlurEnabled: Bool,
        isIdleImageEnabled: Bool = false,
        isIdleImageShadowEnabled: Bool = true,
        idleImageShadowOffset: Float = 1.0,
        idleImageShadowBlur: Float = 3.0,
        idleImageShadowOpacity: Float = 0.12
    ) {
        self.refractionStrength = refractionStrength
        self.refractionEdgeWidth = refractionEdgeWidth
        self.refractionCenterStrength = refractionCenterStrength
        self.refractionEdgeStrength = refractionEdgeStrength
        self.refractionXScale = refractionXScale
        self.refractionYScale = refractionYScale
        self.dimmingStrength = dimmingStrength
        self.rimHighlightWidth = rimHighlightWidth
        self.rimHighlightStrength = rimHighlightStrength
        self.chromaticAberrationStrength = chromaticAberrationStrength
        self.coreRadius = coreRadius
        self.idleOuterShadowWidth = idleOuterShadowWidth
        self.idleOuterShadowOpacity = idleOuterShadowOpacity
        self.activeOuterShadowWidth = activeOuterShadowWidth
        self.activeOuterShadowOpacity = activeOuterShadowOpacity
        self.isBlurEnabled = isBlurEnabled
        self.isIdleImageEnabled = isIdleImageEnabled
        self.isIdleImageShadowEnabled = isIdleImageShadowEnabled
        self.idleImageShadowOffset = idleImageShadowOffset
        self.idleImageShadowBlur = idleImageShadowBlur
        self.idleImageShadowOpacity = idleImageShadowOpacity
    }
}
