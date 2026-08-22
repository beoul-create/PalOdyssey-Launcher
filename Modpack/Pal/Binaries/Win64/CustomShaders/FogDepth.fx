// ============================================================
// FogDepth - Atmospheric Distance Fog
// Adds subtle haze to distant geometry, like real atmosphere
// ============================================================

#include "ReShade.fxh"

uniform float FOG_START <
    ui_type = "slider"; ui_label = "Fog Start Distance";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.5;

uniform float FOG_END <
    ui_type = "slider"; ui_label = "Fog End Distance";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.95;

uniform float FOG_DENSITY <
    ui_type = "slider"; ui_label = "Fog Density";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.25;

uniform float3 FOG_COLOR <
    ui_type = "color"; ui_label = "Fog Color";
> = float3(0.72, 0.78, 0.85);

float4 FogDepth_PS(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
    float4 color = tex2D(ReShade::BackBuffer, uv);
    float depth  = ReShade::GetLinearizedDepth(uv);

    // Skip skybox (depth ~= 1.0)
    if (depth > 0.99) return color;

    float fogFactor = smoothstep(FOG_START, FOG_END, depth) * FOG_DENSITY;
    color.rgb = lerp(color.rgb, FOG_COLOR, saturate(fogFactor));
    return color;
}

technique FogDepth <ui_label = "Fog - Atmospheric Depth Haze";> {
    pass {
        VertexShader = PostProcessVS;
        PixelShader  = FogDepth_PS;
    }
}
