#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

struct LegacyGlassUniforms {
    float2 canvasSize;
    float2 lensCenterCanvas;
    float2 lensRadiusCanvas;
    float  cornerRadius;
    float  refractionStrength;
    float  dimmingMin;
    float  dimmingMax;
    float  dimmingStrength;
    float  averageBackgroundLuma;
    float2 textureOriginHost;
    float2 textureSizeHost;
    float2 lensOriginHost;
    float2 lensSizeHost;
    float  refractionEdgeWidth;
    float  refractionCenterStrength;
    float  refractionEdgeStrength;
    float  interactionScale;
    float  refractionYScale;
    float  chromaticAberrationStrength;
    float  rimHighlightWidth;
    float  rimHighlightStrength;
    float  coreRadius;
    float  glowProgress;
    float2 glowCenter;
    float  glowRadius;
    float  glowStrength;
    float  outerShadowWidth;
    float  outerShadowOpacity;
    float4 tintColor;
    float4 fillColor;
    float  fillProgress;
};

vertex VertexOut legacyGlassVertex(VertexIn in [[stage_in]]) {
    VertexOut out;
    out.position = float4(in.position, 0.0, 1.0);
    out.texCoord = in.texCoord;
    return out;
}

float roundedRectSDF(float2 lensUV, float2 lensRadius, float2 canvasSize, float cornerRadius) {
    const float2 lensSizePx = lensRadius * 2.0 * canvasSize;
    const float  minDimPx   = min(lensSizePx.x, lensSizePx.y);
    const float2 sizeUV     = lensSizePx / max(minDimPx, 1e-4);
    const float  rUV        = clamp(cornerRadius / max(minDimPx, 1e-4), 0.0, min(sizeUV.x, sizeUV.y) * 0.5);

    const float2 halfSize     = sizeUV * 0.5;
    const float2 halfSizeSafe = max(halfSize, float2(1e-4, 1e-4));
    const float  r            = clamp(rUV, 0.0, min(halfSizeSafe.x, halfSizeSafe.y));

    float2 p = lensUV - 0.5;
    float2 pScaled = p * sizeUV;
    float2 q = abs(pScaled) - (halfSizeSafe - float2(r, r));
    float outside = length(max(q, 0.0));
    float inside  = min(max(q.x, q.y), 0.0);
    return outside + inside - r;
}

float computeMask(float sdf, float aaWidth) {
    return 1.0 - smoothstep(-aaWidth, aaWidth, sdf);
}

float computeOuterShadowAlpha(float sdf, float aaWidth, float shadowEnd, float shadowOpacity) {
    float shadow = 1.0 - smoothstep(0.0, shadowEnd, sdf);
    shadow = max(shadow, 0.0);
    return shadow * shadowOpacity;
}

struct RefractionResult {
    float2 hostUV;
    float  normalizedRadius;
};

RefractionResult applyEdgeRefraction(float2 baseHostUV,
                                     float2 hostCenter,
                                     float2 fromCenter,
                                     float sdf,
                                     float coreRadius,
                                     float refractionStrength,
                                     float edgeWidth,
                                     float centerStrength,
                                     float edgeStrength,
                                     float refractionYScale) {
    const float centerK = centerStrength * refractionStrength;
    const float edgeK   = edgeStrength   * refractionStrength;

    const float coreRangeInv = 1.0 / max(1.0 - coreRadius, 1e-4);
    const float normalizedRadius = clamp((sdf + 0.5) * coreRangeInv, 0.0, 1.0);

    const float ringEdgeStart = max(0.0, 1.0 - edgeWidth);
    const float t             = clamp((normalizedRadius - ringEdgeStart) / max(edgeWidth, 1e-4), 0.0, 1.0);

    const float tSoft    = smoothstep(0.0, 1.0, pow(t, 1.2));
    const float edgeTerm = pow(tSoft, 2) * edgeK;

    const float centerTerm = (1.0 - pow(normalizedRadius, 2)) * centerK;

    const float radialScaleX = 1.0 + centerTerm + edgeTerm;
    const float radialScaleY = 1.0 + centerTerm + edgeTerm * refractionYScale;

    float2 hostUV = hostCenter + float2(fromCenter.x * radialScaleX, fromCenter.y * radialScaleY);

    RefractionResult result;
    result.hostUV = hostUV;
    result.normalizedRadius = normalizedRadius;
    return result;
}

float4 sampleChromaticAberration(texture2d<float> texture,
                                 sampler textureSampler,
                                 float2 textureUV,
                                 float2 fromCenter,
                                 float normalizedRadius,
                                 float refractionYScale,
                                 float chromaticStrength) {
    float2 caDirection = float2(0.0, 0.0);
    const float distanceFromCenter = length(fromCenter);
    if (distanceFromCenter > 1e-4) {
        caDirection = fromCenter / distanceFromCenter;
    }

    const float caEdgeWeight = smoothstep(0.5, 1.0, normalizedRadius);
    const float caStrength   = chromaticStrength * 0.05;
    const float caScale      = caStrength * caEdgeWeight;

    const float2 caOffset = caDirection * caScale * float2(1.0, refractionYScale);

    const float2 uvR = clamp(textureUV - caOffset, float2(0.0, 0.0), float2(1.0, 1.0));
    const float2 uvG = textureUV;
    const float2 uvB = clamp(textureUV + caOffset, float2(0.0, 0.0), float2(1.0, 1.0));

    const float4 sampleR = texture.sample(textureSampler, uvR);
    const float4 sampleG = texture.sample(textureSampler, uvG);
    const float4 sampleB = texture.sample(textureSampler, uvB);

    return float4(sampleR.r, sampleG.g, sampleB.b, sampleG.a);
}

float4 applyEdgeBlur(texture2d<float> texture,
                     sampler textureSampler,
                     float2 textureUV,
                     float normalizedRadius,
                     float4 baseColor) {
    constexpr float blurStart = 0.5;
    constexpr float blurEnd   = 1.0;
    constexpr float edgeBlurStrengthFactor = 3.0;

    const float blurMix = clamp((normalizedRadius - blurStart) / max(blurEnd - blurStart, 1e-4), 0.0, 1.0);

    if (blurMix <= 0.0) {
        return baseColor;
    }

    const float2 texel = float2(1.0 / texture.get_width(), 1.0 / texture.get_height()) * edgeBlurStrengthFactor;

    float4 hBlur = 0.0;
    hBlur += texture.sample(textureSampler, textureUV - float2(texel.x, 0.0)) * 0.25;
    hBlur += texture.sample(textureSampler, textureUV)                          * 0.50;
    hBlur += texture.sample(textureSampler, textureUV + float2(texel.x, 0.0)) * 0.25;

    float4 vBlur = 0.0;
    vBlur += texture.sample(textureSampler, textureUV - float2(0.0, texel.y)) * 0.25;
    vBlur += hBlur                                                            * 0.50;
    vBlur += texture.sample(textureSampler, textureUV + float2(0.0, texel.y)) * 0.25;

    return mix(baseColor, vBlur, blurMix);
}

struct RimResult {
    float3 color;
    float  rimFactor;
};

RimResult applyRimHighlight(float sdf,
                            float aaWidth,
                            float rimHighlightWidth,
                            float baseStrength,
                            float3 baseColor) {
    const float2 lightDir1 = normalize(float2(-0.5, -0.8));
    const float2 lightDir2 = normalize(float2(0.5, 0.8));

    const float rimWidth = aaWidth * rimHighlightWidth + 0.01;
    const float rimBand  = 1.0 - smoothstep(0.0, rimWidth, abs(sdf));

    const float2 sdfGrad = float2(dfdx(sdf), dfdy(sdf));
    const float2 rimNormal = normalize(sdfGrad + float2(1e-6, 0.0));

    float rimBias1 = clamp(dot(rimNormal, lightDir1), 0.0, 1.0);
    float rimBias2 = clamp(dot(rimNormal, lightDir2), 0.0, 1.0);
    float rimBias  = clamp(rimBias1 + rimBias2, 0.0, 1.0);

    const float rimWeight = rimBand * rimBias;

    const float rimGlow = clamp(baseStrength * rimWeight, 0.0, 0.40);
    const float3 rimHighlightColor = float3(1.05, 1.05, 1.1);

    float3 rimmedColor = mix(baseColor, rimHighlightColor, rimGlow);

    float rimAlphaMin = 0.9;
    float rimFactor   = mix(1.0, rimAlphaMin, rimWeight);

    RimResult result;
    result.color = rimmedColor;
    result.rimFactor = rimFactor;
    return result;
}

float4 applyGlow(float2 uv,
                 float4 color,
                 float sdf,
                 float aaWidth,
                 float2 lensRadiusCanvas,
                 float2 canvasSize,
                 float glowProgress,
                 float2 glowCenter,
                 float glowRadius,
                 float glowStrength) {
    const float2 lensRadiusPx = lensRadiusCanvas * canvasSize;
    const float  minRadiusPx  = min(lensRadiusPx.x, lensRadiusPx.y);

    float2 deltaPx = (uv - glowCenter) * canvasSize;
    float distGlowPx = length(deltaPx);
    float distGlow = distGlowPx / max(minRadiusPx, 1e-4);

    const float radiusGlow = glowRadius;
    const float normalizedDistance = clamp(distGlow / max(radiusGlow, 1e-4), 0.0, 1.0);
    
    const float inverseSquareFalloff = 1.0 / (1.0 + normalizedDistance * normalizedDistance * 4.0);
    const float exponentialFalloff = exp(-normalizedDistance * 2.5);
    const float glowIntensityBase = mix(inverseSquareFalloff, exponentialFalloff, 0.3);
    
    const float fadeGlow = radiusGlow * 0.4;
    const float outerFeather = 1.0 - smoothstep(radiusGlow, radiusGlow + fadeGlow, distGlow);
    const float glowMask = glowIntensityBase * outerFeather;

    const float clipMask = smoothstep(aaWidth, 0.0, sdf);

    const float strength = glowProgress * clamp(glowStrength, 0.0, 1.0);
    const float glowIntensity = clipMask * strength * glowMask;
    
    const float3 glowColor = float3(1.0, 1.0, 1.0);
    const float glowAmount = glowIntensity * 0.6;
    
    color.rgb = color.rgb + glowColor * glowAmount;
    return color;
}

float4 applyDimming(float4 color, float min, float max, float dimmingStrength, float averageLuma) {
    const float luma = clamp(averageLuma, 0.0, 1.0);
    const float dimmingCurve = 1.1;
    float dimming = mix(min, max, pow(luma, dimmingCurve));
    dimming *= clamp(dimmingStrength, 0.0, 1.0);
    color.rgb = mix(color.rgb, float3(0.0), dimming);
    return color;
}

fragment float4 legacyGlassFragment(VertexOut in [[stage_in]],
                                    constant LegacyGlassUniforms& uniforms [[buffer(0)]],
                                    texture2d<float> backgroundTexture [[texture(0)]],
                                    texture2d<float> idleTexture [[texture(1)]],
                                    sampler textureSampler [[sampler(0)]]) {
    const float2 uv = in.texCoord;

    const float2 lensMin = uniforms.lensCenterCanvas - uniforms.lensRadiusCanvas;
    const float2 lensMax = uniforms.lensCenterCanvas + uniforms.lensRadiusCanvas;

    float2 lensUV = (uv - lensMin) / (lensMax - lensMin);
    
    const float sdf = roundedRectSDF(lensUV, uniforms.lensRadiusCanvas, uniforms.canvasSize, uniforms.cornerRadius);

    const float aaWidth = fwidth(sdf) * 1.0;

    const float mask = computeMask(sdf, aaWidth);

    const float outerShadowAlpha = (1.0 - mask) * computeOuterShadowAlpha(sdf,
                                                                          aaWidth,
                                                                          uniforms.outerShadowWidth,
                                                                          uniforms.outerShadowOpacity);

    if (mask <= 0.0) {
        return float4(0.0, 0.0, 0.0, outerShadowAlpha);
    }
    
    const float2 baseHostUV = uniforms.lensOriginHost + lensUV * uniforms.lensSizeHost;
    const float2 hostCenter = uniforms.lensOriginHost + 0.5 * uniforms.lensSizeHost;
    const float2 fromCenter = baseHostUV - hostCenter;

    RefractionResult refraction = applyEdgeRefraction(baseHostUV,
                                                      hostCenter,
                                                      fromCenter,
                                                      sdf,
                                                      uniforms.coreRadius,
                                                      uniforms.refractionStrength,
                                                      uniforms.refractionEdgeWidth,
                                                      uniforms.refractionCenterStrength,
                                                      uniforms.refractionEdgeStrength,
                                                      uniforms.refractionYScale);
    float2 hostUV = refraction.hostUV;
    const float normalizedRadius = refraction.normalizedRadius;

    float2 textureUV = (hostUV - uniforms.textureOriginHost) / uniforms.textureSizeHost;
    textureUV = clamp(textureUV, float2(0.0, 0.0), float2(1.0, 1.0));
    
    float4 color = sampleChromaticAberration(backgroundTexture,
                                             textureSampler,
                                             textureUV,
                                             fromCenter,
                                             normalizedRadius,
                                             uniforms.refractionYScale,
                                             uniforms.chromaticAberrationStrength);
    
    color = applyEdgeBlur(backgroundTexture, textureSampler, textureUV, normalizedRadius, color);

    if (uniforms.tintColor.a > 0) {
        color.rgb = mix(color.rgb, uniforms.tintColor.rgb, uniforms.tintColor.a);
    }
    
    RimResult rim = applyRimHighlight(sdf, aaWidth, uniforms.rimHighlightWidth, uniforms.rimHighlightStrength, color.rgb);
    color.rgb = rim.color;

    if (uniforms.glowProgress > 0.0) {
        color = applyGlow(uv,
                          color,
                          sdf,
                          aaWidth,
                          uniforms.lensRadiusCanvas,
                          uniforms.canvasSize,
                          uniforms.glowProgress,
                          uniforms.glowCenter,
                          uniforms.glowRadius,
                          uniforms.glowStrength);
    }

    color = applyDimming(color,
                         uniforms.dimmingMin,
                         uniforms.dimmingMax,
                         uniforms.dimmingStrength,
                         uniforms.averageBackgroundLuma);

    if (uniforms.fillProgress > 0.0 && uniforms.fillColor.a > 0.0) {
        float fillMix = clamp(uniforms.fillProgress, 0.0, 1.0);
        color.rgb = mix(color.rgb, uniforms.fillColor.rgb, fillMix);
    }

    color.a = mask;
    color.rgb *= color.a;

    color.a = clamp(color.a + outerShadowAlpha, 0.0, 1.0);
    return color;
}

struct AdditionalTextureUniforms {
  float2 canvasSize;
  float2 additionalTextureOriginCanvas;
  float2 additionalTextureSizeCanvas;
  float2 backgroundTextureSize;
  float  cornerRadius;
  float4 backgroundColor;
};

fragment float4 additionalTextureFragment(VertexOut in [[stage_in]],
                                          constant AdditionalTextureUniforms& uniforms [[buffer(0)]],
                                          texture2d<float> backgroundTexture [[texture(0)]],
                                          texture2d<float> additionalTexture [[texture(1)]],
                                          sampler textureSampler [[sampler(0)]]) {
    float2 uv = in.texCoord;
    float4 color = backgroundTexture.sample(textureSampler, uv);

    if (uniforms.canvasSize.x <= 0.0 || uniforms.canvasSize.y <= 0.0 ||
      uniforms.backgroundTextureSize.x <= 0.0 || uniforms.backgroundTextureSize.y <= 0.0) {
        return color;
    }

    float2 canvasToTextureScale = uniforms.backgroundTextureSize / uniforms.canvasSize;
    float2 additionalTextureSizeInTextureSpace = uniforms.additionalTextureSizeCanvas * canvasToTextureScale;

    if (additionalTextureSizeInTextureSpace.x <= 0.0 || additionalTextureSizeInTextureSpace.y <= 0.0) {
        return color;
    }

    float2 additionalTextureMinCanvas = uniforms.additionalTextureOriginCanvas / uniforms.canvasSize;
    float2 additionalTextureMaxCanvas = (uniforms.additionalTextureOriginCanvas + uniforms.additionalTextureSizeCanvas) / uniforms.canvasSize;
    float2 additionalTextureRadiusCanvas = uniforms.additionalTextureSizeCanvas * 0.5 / uniforms.canvasSize;
    
    float2 additionalTextureSizeCanvasNormalized = additionalTextureMaxCanvas - additionalTextureMinCanvas;
    float2 lensUV = (uv - additionalTextureMinCanvas) / max(additionalTextureSizeCanvasNormalized, float2(1e-6, 1e-6));
    float sdf = roundedRectSDF(lensUV, additionalTextureRadiusCanvas, uniforms.canvasSize, uniforms.cornerRadius);
    
    float aaWidth = fwidth(sdf) * 0.5;
    float mask = computeMask(sdf, aaWidth);
    
        if (mask > 0.0) {
            float2 uvInCanvasPixels = uv * uniforms.canvasSize;
            float2 deltaInCanvasPixels = uvInCanvasPixels - uniforms.additionalTextureOriginCanvas;
            float2 textureScale = uniforms.backgroundTextureSize / uniforms.canvasSize;
            float2 deltaInTexturePixels = deltaInCanvasPixels * textureScale;
            float2 additionalUV = deltaInTexturePixels / max(additionalTextureSizeInTextureSpace, float2(1e-6, 1e-6));
            additionalUV = clamp(additionalUV, float2(0.0, 0.0), float2(1.0, 1.0));
            
            float backgroundColorAlpha = uniforms.backgroundColor.a * mask;
            float3 backgroundColorPremultiplied = uniforms.backgroundColor.rgb * backgroundColorAlpha;
            
            float backgroundAlpha = color.a;
            if (backgroundAlpha > 0.0) {
                color.rgb = color.rgb * (1.0 - backgroundColorAlpha) + backgroundColorPremultiplied;
                color.a = backgroundAlpha + backgroundColorAlpha * (1.0 - backgroundAlpha);
            } else {
                color.rgb = backgroundColorPremultiplied;
                color.a = backgroundColorAlpha;
            }
            
            float4 additionalColor = additionalTexture.sample(textureSampler, additionalUV);
            if (additionalColor.a > 0.0) {
                float textureAlpha = additionalColor.a * mask;
                float3 texturePremultiplied = additionalColor.rgb * textureAlpha;
                float currentAlpha = color.a;
                if (currentAlpha > 0.0) {
                    color.rgb = color.rgb * (1.0 - textureAlpha) + texturePremultiplied;
                    color.a = currentAlpha + textureAlpha * (1.0 - currentAlpha);
                } else {
                    color.rgb = texturePremultiplied;
                    color.a = textureAlpha;
                }
            }
        }

    return color;
}
