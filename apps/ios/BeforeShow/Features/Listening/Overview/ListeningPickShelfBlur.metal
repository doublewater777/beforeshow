#include <metal_stdlib>
using namespace metal;

// Sampling decodes sRGB automatically; a write through a linear view needs explicit encoding.
static half4 shelfOutput(half4 color, uint encodeSRGB) {
    if (!encodeSRGB) { return color; }
    float3 linear = max(float3(color.rgb), 0.0);
    float3 encoded = select(1.055 * pow(linear, float3(1.0 / 2.4)) - 0.055,
                            12.92 * linear, linear <= 0.0031308);
    return half4(half3(encoded), color.a);
}

// The 3D record shelf's far end goes soft towards the top-right corner.
// Runs as RealityKit post-processing; `overscan` maps the oversized render back to screen space.
kernel void shelfFarBlur(texture2d<half, access::sample> source [[texture(0)]],
                         texture2d<half, access::write> target [[texture(1)]],
                         constant float &overscan [[buffer(0)]],
                         constant uint &encodeSRGB [[buffer(1)]],
                         uint2 gid [[thread_position_in_grid]]) {
    float2 size = float2(target.get_width(), target.get_height());
    if (gid.x >= uint(size.x) || gid.y >= uint(size.y)) { return; }
    constexpr sampler linear(filter::linear, address::clamp_to_edge, coord::pixel);
    float2 position = float2(gid) + 0.5;
    float2 uv = (position / size - 0.5) * overscan + 0.5;
    float strength = smoothstep(0.36, 0.1, uv.y) * smoothstep(0.4, 0.8, uv.x);
    // About 5pt at full strength.
    float radius = size.x / overscan * 0.0125 * strength;
    if (radius < 0.5) {
        target.write(shelfOutput(source.sample(linear, position), encodeSRGB), gid);
        return;
    }
    half4 sum = 0;
    float total = 0;
    for (int i = -3; i <= 3; i++) {
        for (int j = -3; j <= 3; j++) {
            float weight = exp(-float(i * i + j * j) / 8.0);
            sum += source.sample(linear, position + float2(i, j) * radius / 3.0) * half(weight);
            total += weight;
        }
    }
    target.write(shelfOutput(sum / half(total), encodeSRGB), gid);
}
