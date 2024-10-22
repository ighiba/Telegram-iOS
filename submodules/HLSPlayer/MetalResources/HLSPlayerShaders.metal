#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float4 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut vertexShader(VertexIn in [[stage_in]]) {
    VertexOut out;
    out.position = in.position;
    out.texCoord = in.texCoord;
    return out;
}

fragment float4 fragmentShader(VertexOut in [[stage_in]],
                               texture2d<float, access::sample> yTexture [[texture(0)]],
                               texture2d<float, access::sample> uvTexture [[texture(1)]],
                               sampler textureSampler [[sampler(0)]]) {
    float Y = yTexture.sample(textureSampler, in.texCoord.xy).r;
    float U = uvTexture.sample(textureSampler, in.texCoord.xy).r - 0.5;
    float V = uvTexture.sample(textureSampler, in.texCoord.xy).g - 0.5;
    
    float R = Y + 1.402 * V;
    float G = Y - 0.344136 * U - 0.714136 * V;
    float B = Y + 1.772 * U;
    
    return float4(R, G, B, 1.0);
}
