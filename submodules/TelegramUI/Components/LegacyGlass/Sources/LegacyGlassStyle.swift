import Foundation

public struct LegacyGlassStyle {
    public var refractionStrength: Float
    public var refractionEdgeWidth: Float
    public var refractionCenterStrength: Float
    public var refractionEdgeStrength: Float
    public var refractionXScale: Float
    public var refractionYScale: Float
    public var brightnessAdaptationStrength: Float
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
    public var glowRadius: Float
    public var glowStrenght: Float
    
    public init(
        refractionStrength: Float,
        refractionEdgeWidth: Float,
        refractionCenterStrength: Float,
        refractionEdgeStrength: Float,
        refractionXScale: Float,
        refractionYScale: Float,
        brightnessAdaptationStrength: Float,
        rimHighlightWidth: Float,
        rimHighlightStrength: Float,
        chromaticAberrationStrength: Float,
        coreRadius: Float,
        idleOuterShadowWidth: Float,
        idleOuterShadowOpacity: Float,
        activeOuterShadowWidth: Float,
        activeOuterShadowOpacity: Float,
        glowRadius: Float = 8.0,
        glowStrenght: Float = 0.8,
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
        self.brightnessAdaptationStrength = brightnessAdaptationStrength
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
        self.glowRadius = glowRadius
        self.glowStrenght = glowStrenght
    }
}

public extension LegacyGlassStyle {
    static let clear = LegacyGlassStyle(
        refractionStrength: 1.61,
        refractionEdgeWidth: 0.60,
        refractionCenterStrength: 0.0,
        refractionEdgeStrength: -0.25,
        refractionXScale: 1.0,
        refractionYScale: 0.8,
        brightnessAdaptationStrength: 0.3,
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
    
    static let regular = LegacyGlassStyle(
        refractionStrength: 1.81,
        refractionEdgeWidth: 0.75,
        refractionCenterStrength: 0.0,
        refractionEdgeStrength: -0.45,
        refractionXScale: 1.0,
        refractionYScale: 0.8,
        brightnessAdaptationStrength: 0.5,
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
    
    static let lens = LegacyGlassStyle(
        refractionStrength: 1.61,
        refractionEdgeWidth: 0.80,
        refractionCenterStrength: 0.0,
        refractionEdgeStrength: -0.25,
        refractionXScale: 1.0,
        refractionYScale: 0.8,
        brightnessAdaptationStrength: 0.3,
        rimHighlightWidth: 1.5,
        rimHighlightStrength: 0.5,
        chromaticAberrationStrength: 0.95,
        coreRadius: 0.36,
        idleOuterShadowWidth: 0.2,
        idleOuterShadowOpacity: 0.2,
        activeOuterShadowWidth: 0.2,
        activeOuterShadowOpacity: 0.2,
        isBlurEnabled: false
    )
    
    static let inputBackground = LegacyGlassStyle(
        refractionStrength: -1.3,
        refractionEdgeWidth: 0.95,
        refractionCenterStrength: 0.0,
        refractionEdgeStrength: 0.2,
        refractionXScale: 1.0,
        refractionYScale: 10.0,
        brightnessAdaptationStrength: 0.0,
        rimHighlightWidth: 0.5,
        rimHighlightStrength: 0.25,
        chromaticAberrationStrength: 0.05,
        coreRadius: 0.2,
        idleOuterShadowWidth: 0.1,
        idleOuterShadowOpacity: 0.15,
        activeOuterShadowWidth: 0.0,
        activeOuterShadowOpacity: 0.0,
        glowRadius: 10.0,
        glowStrenght: 0.3,
        isBlurEnabled: true,
    )
    
    static let smallBackground = LegacyGlassStyle(
        refractionStrength: -1.5,
        refractionEdgeWidth: 1.0,
        refractionCenterStrength: 0.0,
        refractionEdgeStrength: 0.2,
        refractionXScale: 1.0,
        refractionYScale: 10.0,
        brightnessAdaptationStrength: 0.0,
        rimHighlightWidth: 0.5,
        rimHighlightStrength: 0.25,
        chromaticAberrationStrength: 0.05,
        coreRadius: 0.2,
        idleOuterShadowWidth: 0.1,
        idleOuterShadowOpacity: 0.15,
        activeOuterShadowWidth: 0.0,
        activeOuterShadowOpacity: 0.0,
        glowRadius: 10.0,
        glowStrenght: 0.3,
        isBlurEnabled: true,
    )
    
    static let largeBackground = LegacyGlassStyle(
        refractionStrength: -0.48,
        refractionEdgeWidth: 0.75,
        refractionCenterStrength: 0.0,
        refractionEdgeStrength: 0.25,
        refractionXScale: 1.0,
        refractionYScale: 10.0,
        brightnessAdaptationStrength: 0.0,
        rimHighlightWidth: 1.0,
        rimHighlightStrength: 0.35,
        chromaticAberrationStrength: 0.05,
        coreRadius: 0.34,
        idleOuterShadowWidth: 0.1,
        idleOuterShadowOpacity: 0.15,
        activeOuterShadowWidth: 0.0,
        activeOuterShadowOpacity: 0.0,
        glowRadius: 10.0,
        glowStrenght: 0.3,
        isBlurEnabled: true,
    )
    
    static let switchKnob = LegacyGlassStyle(
        refractionStrength: -0.32,
        refractionEdgeWidth: 0.95,
        refractionCenterStrength: -1.67,
        refractionEdgeStrength: 2.9,
        refractionXScale: 1.1,
        refractionYScale: 0.9,
        brightnessAdaptationStrength: 0.75,
        rimHighlightWidth: 1.0,
        rimHighlightStrength: 0.5,
        chromaticAberrationStrength: 0.37,
        coreRadius: 0.33,
        idleOuterShadowWidth: 0.0,
        idleOuterShadowOpacity: 0.0,
        activeOuterShadowWidth: 0.2,
        activeOuterShadowOpacity: 0.1,
        isBlurEnabled: false
    )
    
    static let sliderKnob = LegacyGlassStyle(
        refractionStrength: 1.6,
        refractionEdgeWidth: 1.0,
        refractionCenterStrength: 0.0,
        refractionEdgeStrength: -0.97,
        refractionXScale: 1.0,
        refractionYScale: 0.9,
        brightnessAdaptationStrength: 0.3,
        rimHighlightWidth: 1.0,
        rimHighlightStrength: 0.3,
        chromaticAberrationStrength: 1.5,
        coreRadius: 0.33,
        idleOuterShadowWidth: 0.3,
        idleOuterShadowOpacity: 0.2,
        activeOuterShadowWidth: 0.3,
        activeOuterShadowOpacity: 0.2,
        isBlurEnabled: false,
        isIdleImageEnabled: true,
        isIdleImageShadowEnabled: true,
        idleImageShadowOffset: 1.0,
        idleImageShadowBlur: 10.0,
        idleImageShadowOpacity: 0.1
    )
}
