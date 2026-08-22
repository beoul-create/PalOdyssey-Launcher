// ============================================================
// MXAO - Screen Space Ambient Occlusion
// Darkens corners, crevices, and contact points for depth
// ============================================================

#include "ReShade.fxh"

uniform float MXAO_SAMPLE_RADIUS <
    ui_type = "slider"; ui_label = "Sample Radius";
    ui_min = 0.5; ui_max = 10.0; ui_step = 0.1;
> = 2.5;

uniform float MXAO_INTENSITY <
    ui_type = "slider"; ui_label = "AO Intensity";
    ui_min = 0.0; ui_max = 4.0; ui_step = 0.05;
> = 1.8;

uniform int MXAO_SAMPLES <
    ui_type = "slider"; ui_label = "Sample Count";
    ui_min = 4; ui_max = 24; ui_step = 1;
> = 16;

uniform float MXAO_FADEOUT_START <
    ui_type = "slider"; ui_label = "Fade Start Depth";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.4;

uniform float MXAO_FADEOUT_END <
    ui_type = "slider"; ui_label = "Fade End Depth";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.8;

static const float2 poisson[24] = {
    float2(-0.326212,-0.40581),  float2(-0.840144,-0.07358),
    float2(-0.695914, 0.457137), float2(-0.203345, 0.620716),
    float2( 0.96234, -0.194983), float2( 0.473434,-0.480026),
    float2( 0.519456, 0.767022), float2( 0.185461,-0.893124),
    float2( 0.507431, 0.064425), float2( 0.89642,  0.412458),
    float2(-0.32194,-0.932615),  float2(-0.791559,-0.59771),
    float2(-0.548796, 0.242832), float2( 0.284476,-0.756969),
    float2( 0.125428, 0.356932), float2(-0.116803,-0.126124),
    float2(-0.758421,-0.394606), float2(-0.138397, 0.928315),
    float2( 0.668488, 0.295092), float2( 0.388873,-0.120213),
    float2(-0.556804,-0.705952), float2( 0.143588, 0.718888),
    float2(-0.919315, 0.243532), float2( 0.321987, 0.476985)
};

float3 GetNormalFromDepth(float2 uv) {
    float2 px = ReShade::PixelSize;
    float depthC = ReShade::GetLinearizedDepth(uv);
    float depthR = ReShade::GetLinearizedDepth(uv + float2(px.x, 0));
    float depthU = ReShade::GetLinearizedDepth(uv + float2(0, px.y));
    return normalize(float3(depthC - depthR, depthC - depthU, px.x));
}

float4 MXAO_PS(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
    float4 color = tex2D(ReShade::BackBuffer, uv);
    float depth = ReShade::GetLinearizedDepth(uv);

    // Fade out at distance
    float fade = 1.0 - smoothstep(MXAO_FADEOUT_START, MXAO_FADEOUT_END, depth);
    if (fade <= 0.0 || depth >= 1.0) return color;

    float3 normal = GetNormalFromDepth(uv);
    float ao = 0.0;
    float radius = MXAO_SAMPLE_RADIUS * 0.001 / max(depth, 0.01);

    [loop]
    for (int i = 0; i < MXAO_SAMPLES; i++) {
        float2 sampleOffset = poisson[i] * radius;
        float2 sampleUV = uv + sampleOffset;
        float sampleDepth = ReShade::GetLinearizedDepth(sampleUV);

        float depthDelta = depth - sampleDepth;

        // Only count samples above the surface
        float rangeCheck = smoothstep(0.0, 1.0, radius / max(abs(depthDelta), 0.0001));
        ao += step(0.0001, depthDelta) * rangeCheck;
    }

    ao = (ao / MXAO_SAMPLES) * MXAO_INTENSITY * fade;
    ao = saturate(ao);

    color.rgb *= (1.0 - ao * 0.85);
    return color;
}

technique MXAO <ui_label = "MXAO - Ambient Occlusion";> {
    pass {
        VertexShader = PostProcessVS;
        PixelShader  = MXAO_PS;
    }
}
