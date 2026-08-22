// ============================================================
// NightTint - Blue Night Tinting
// Shifts the color palette to cool blue tones at night.
// Detects nighttime by measuring overall scene luminance.
// ============================================================

#include "ReShade.fxh"

uniform float NIGHT_THRESHOLD <
    ui_type = "slider"; ui_label = "Night Detection Threshold";
    ui_tooltip = "Overall scene brightness below this is considered night";
    ui_min = 0.0; ui_max = 0.5; ui_step = 0.005;
> = 0.12;

uniform float TINT_STRENGTH <
    ui_type = "slider"; ui_label = "Tint Strength";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.35;

uniform float3 NIGHT_COLOR <
    ui_type = "color"; ui_label = "Night Tint Color";
> = float3(0.35, 0.50, 0.85);

uniform float SHADOW_DEEPEN <
    ui_type = "slider"; ui_label = "Shadow Deepening";
    ui_tooltip = "Makes dark areas even darker at night";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.4;

float4 NightTint_PS(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
    float4 color = tex2D(ReShade::BackBuffer, uv);

    // Sample multiple points to estimate scene luminance robustly
    float3 s1 = tex2D(ReShade::BackBuffer, float2(0.25, 0.4)).rgb;
    float3 s2 = tex2D(ReShade::BackBuffer, float2(0.5,  0.4)).rgb;
    float3 s3 = tex2D(ReShade::BackBuffer, float2(0.75, 0.4)).rgb;
    float3 s4 = tex2D(ReShade::BackBuffer, float2(0.5,  0.2)).rgb;
    float sceneLuma = dot((s1 + s2 + s3 + s4) * 0.25, float3(0.299, 0.587, 0.114));

    float nightFactor = 1.0 - smoothstep(0.0, NIGHT_THRESHOLD, sceneLuma);
    if (nightFactor <= 0.01) return color;

    float pixelLuma = dot(color.rgb, float3(0.299, 0.587, 0.114));

    // Apply blue tint — stronger in shadows, subtler in highlights
    float shadowMask = 1.0 - smoothstep(0.0, 0.5, pixelLuma);
    float3 tinted = lerp(color.rgb, color.rgb * NIGHT_COLOR * 1.8, TINT_STRENGTH * nightFactor);

    // Deepen shadows at night
    tinted = lerp(tinted, tinted * (1.0 - SHADOW_DEEPEN * shadowMask), nightFactor * 0.5);

    color.rgb = saturate(tinted);
    return color;
}

technique NightTint <ui_label = "Night - Blue Tint";> {
    pass {
        VertexShader = PostProcessVS;
        PixelShader  = NightTint_PS;
    }
}
