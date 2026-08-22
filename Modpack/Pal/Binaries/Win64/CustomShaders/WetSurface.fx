// ============================================================
// WetSurface - Simulated Ground Wetness
// Adds specular highlights and darkening to near-ground pixels
// to simulate a wet, freshly-rained-on world.
// ============================================================

#include "ReShade.fxh"

uniform float WET_INTENSITY <
    ui_type = "slider"; ui_label = "Wetness Intensity";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.55;

uniform float WET_DEPTH_CUTOFF <
    ui_type = "slider"; ui_label = "Ground Depth Limit";
    ui_tooltip = "Only apply wetness to nearby surfaces (not sky)";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.92;

uniform float SPEC_POWER <
    ui_type = "slider"; ui_label = "Specular Power";
    ui_min = 1.0; ui_max = 32.0; ui_step = 0.5;
> = 12.0;

uniform float SPEC_INTENSITY <
    ui_type = "slider"; ui_label = "Specular Intensity";
    ui_min = 0.0; ui_max = 2.0; ui_step = 0.05;
> = 0.6;

uniform float DARKEN_STRENGTH <
    ui_type = "slider"; ui_label = "Darkening Strength";
    ui_tooltip = "Wet surfaces absorb light and appear darker";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.3;

// Simple noise-based specular pattern to fake uneven wet reflections
float hash(float2 p) {
    return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

float smoothNoise(float2 p) {
    float2 i = floor(p);
    float2 f = frac(p);
    f = f * f * (3.0 - 2.0 * f);
    return lerp(
        lerp(hash(i), hash(i + float2(1,0)), f.x),
        lerp(hash(i + float2(0,1)), hash(i + float2(1,1)), f.x),
        f.y
    );
}

float4 WetSurface_PS(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
    float4 color = tex2D(ReShade::BackBuffer, uv);
    float depth  = ReShade::GetLinearizedDepth(uv);

    // Only apply to ground/nearby surfaces
    if (depth > WET_DEPTH_CUTOFF || depth < 0.001) return color;

    // Estimate how much of the image looks like ground (lower screen + some depth)
    float groundBias = smoothstep(0.3, 0.7, uv.y) * (1.0 - smoothstep(0.5, WET_DEPTH_CUTOFF, depth));

    // Darken surface to simulate water-absorbed light
    float3 wet = color.rgb * (1.0 - DARKEN_STRENGTH * groundBias * WET_INTENSITY);

    // Add specular highlights using noise as a normal map proxy
    float2 noiseUV = uv * float2(BUFFER_WIDTH, BUFFER_HEIGHT) * 0.004;
    float noisePatch = smoothNoise(noiseUV) * smoothNoise(noiseUV * 3.7);

    // Fake view-dependent specular using screen position
    float viewDot = pow(saturate(noisePatch), SPEC_POWER);
    float3 specular = viewDot * SPEC_INTENSITY * groundBias * WET_INTENSITY;

    // Specular highlight color: bright white-blue like water reflections
    wet += specular * float3(0.90, 0.93, 1.0);

    // Saturate wetness in puddle areas (richer color when wet)
    float satBoost = 1.0 + 0.15 * groundBias * WET_INTENSITY;
    float luma = dot(wet, float3(0.299, 0.587, 0.114));
    wet = lerp(luma.xxx, wet, satBoost);

    color.rgb = saturate(wet);
    return color;
}

technique WetSurface <ui_label = "Wet Surface - Ground Wetness";> {
    pass {
        VertexShader = PostProcessVS;
        PixelShader  = WetSurface_PS;
    }
}
