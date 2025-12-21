import UIKit

public final class LegacyGlassKnobView: UIView {
    
    public override var frame: CGRect {
        didSet {
            if self.legacyGlassView.snapshotExclusionMode == .overlayWindow {
                self.legacyGlassView.syncOverlayNow()
            }
        }
    }

    public override var center: CGPoint {
        didSet {
            if self.legacyGlassView.snapshotExclusionMode == .overlayWindow {
                self.legacyGlassView.syncOverlayNow()
            }
        }
    }
    
    public var iconImage: UIImage? {
        didSet {
            self.didSetIconImage(self.iconImage)
        }
    }
    
    public var iconTintColor: UIColor? {
        didSet {
            self.iconImageView?.tintColor = self.iconTintColor
        }
    }
    
    private var iconImageView: UIImageView?
    public let legacyGlassView: LegacyGlassView

    public init(style: LegacyGlassStyle, qualityProfile: LegacyGlassQualityProfile, size: CGSize) {
        var updatedStyle = style
        updatedStyle.isIdleImageEnabled = true
        
        let idleImage = makeKnobIdleImage(size: size, style: updatedStyle)
        self.legacyGlassView = LegacyGlassView(
            style: updatedStyle,
            qualityProfile: qualityProfile,
            idleImage: idleImage,
            allowsGroupSnapshotting: false
        )
        self.legacyGlassView.isUserInteractionEnabled = false
        self.legacyGlassView.snapshotExclusionMode = .none
        self.legacyGlassView.setCaptureMode(.staticBackground)
        
        super.init(frame: .zero)

        self.addSubview(self.legacyGlassView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        self.legacyGlassView.frame = self.bounds
        
        if self.legacyGlassView.snapshotExclusionMode == .overlayWindow {
            self.legacyGlassView.syncOverlayNow()
        }
        
        if let iconImageView = self.iconImageView, let size = iconImageView.image?.size {
            iconImageView.frame = CGRect(
                x: (self.bounds.width - size.width) * 0.5,
                y: (self.bounds.height - size.height) * 0.5,
                width: size.width,
                height: size.height
            )
        }
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if self.legacyGlassView.snapshotExclusionMode == .overlayWindow {
            self.legacyGlassView.syncOverlayNow()
        }
    }

    public func interactionBegan(at point: CGPoint) {
        self.legacyGlassView.rendererView.ensureFastCaptureWithDebounce(to: .dynamicBackground(.slow))
        self.legacyGlassView.interactionBegan(at: point)
    }

    public func interactionUpdate(at point: CGPoint) {
        self.legacyGlassView.rendererView.ensureFastCaptureWithDebounce(to: .dynamicBackground(.slow), duration: 1.0)
        self.legacyGlassView.interactionUpdate(at: point)
    }

    public func interactionEnded(shouldCompleteToPeak: Bool = false) {
        self.legacyGlassView.rendererView.ensureFastCaptureWithDebounce(to: .staticBackground, duration: 1.0)
        self.legacyGlassView.interactionEnded(shouldCompleteToPeak: shouldCompleteToPeak)
    }
    
    private func didSetIconImage(_ iconImage: UIImage?) {
        if let image = iconImage {
            if let iconImageView = self.iconImageView {
                iconImageView.image = image
            } else {
                let imageView = UIImageView(image: image)
                self.legacyGlassView.contentView.addSubview(imageView)
                self.iconImageView = imageView
            }
        } else {
            iconImageView?.removeFromSuperview()
            iconImageView = nil
        }
        self.setNeedsLayout()
    }
    
}

private func makeKnobIdleImage(size: CGSize, style: LegacyGlassStyle) -> UIImage? {
    guard size.width > 1, size.height > 1 else {
        return nil
    }

    return LegacyGlassKnobImageMaker.makeKnobIdleImage(
        size: size,
        cornerRadius: size.height * 0.5,
        baseColor: .white,
        hasShadow: style.isIdleImageShadowEnabled,
        shadowOffset: CGFloat(style.idleImageShadowOffset),
        shadowBlur: CGFloat(style.idleImageShadowBlur),
        shadowOpacity: CGFloat(style.idleImageShadowOpacity)
    )
}

private enum LegacyGlassKnobImageMaker {
    private struct CacheKey: Hashable {
        let width: Int
        let height: Int
        let cornerRadius: Int
        let colorKey: String
        let hasShadow: Bool
        let shadowOffset: Int
        let shadowBlur: Int
        let shadowOpacity: Int
    }

    private static var imageCache: [CacheKey: UIImage] = [:]

    static func makeKnobIdleImage(
        size: CGSize,
        cornerRadius: CGFloat,
        baseColor: UIColor,
        hasShadow: Bool = false,
        shadowOffset: CGFloat = 1.0,
        shadowBlur: CGFloat = 3.0,
        shadowOpacity: CGFloat = 0.12
    ) -> UIImage? {
        guard size.width > 0, size.height > 0 else {
            return nil
        }
        
        let scale = UIScreen.main.scale
        let key = CacheKey(
            width: Int(size.width * scale),
            height: Int(size.height * scale),
            cornerRadius: Int(cornerRadius * scale),
            colorKey: baseColor.description,
            hasShadow: hasShadow,
            shadowOffset: Int(shadowOffset * 100),
            shadowBlur: Int(shadowBlur * 100),
            shadowOpacity: Int(shadowOpacity * 1000)
        )

        if let cached = Self.imageCache[key] {
            return cached
        }

        let shadowPadding: CGFloat = 10.0
        let imageSize = CGSize(
            width: size.width + shadowPadding * 2,
            height: size.height + shadowPadding * 2
        )

        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = scale
        format.preferredRange = .standard

        let renderer = UIGraphicsImageRenderer(size: imageSize, format: format)
        let image = renderer.image { ctx in
            let cgContext = ctx.cgContext
            
            cgContext.translateBy(x: shadowPadding, y: shadowPadding)
            
            let rect = CGRect(origin: .zero, size: size)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)

            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            
            if baseColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
                let sRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
                if let cgColor = CGColor(colorSpace: sRGBColorSpace, components: [red, green, blue, alpha]) {
                    cgContext.setFillColor(cgColor)
                } else {
                    cgContext.setFillColor(baseColor.cgColor)
                }
            } else {
                var white: CGFloat = 0
                if baseColor.getWhite(&white, alpha: &alpha) {
                    let sRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
                    if let cgColor = CGColor(colorSpace: sRGBColorSpace, components: [white, white, white, alpha]) {
                        cgContext.setFillColor(cgColor)
                    } else {
                        cgContext.setFillColor(baseColor.cgColor)
                    }
                } else {
                    cgContext.setFillColor(baseColor.cgColor)
                }
            }
            
            if hasShadow {
                cgContext.saveGState()
                cgContext.setShadow(
                    offset: CGSize(width: 0, height: shadowOffset),
                    blur: shadowBlur,
                    color: UIColor.black.withAlphaComponent(shadowOpacity).cgColor
                )
                cgContext.addPath(path.cgPath)
                cgContext.fillPath()
                cgContext.restoreGState()
            }
            
            cgContext.addPath(path.cgPath)
            cgContext.fillPath()
        }

        Self.imageCache[key] = image
        return image
    }
}
