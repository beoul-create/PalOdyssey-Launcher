#include "ReShade.fxh"

uniform float Timer < source = "timer"; >;

uniform float AuroraIntensity <
    ui_type = "slider";
    ui_min = 0.0; ui_max = 2.0;
    ui_tooltip = "How bright the Aurora is.";
> = 1.2;

uniform float3 AuroraColor <
    ui_type = "color";
> = float3(0.1, 0.9, 0.4);

float3 AuroraPass(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
    float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
    float depth = ReShade::GetLinearizedDepth(texcoord);
    
    // Calculate average luminance of the scene to detect if it's nighttime
    float luma = dot(color, float3(0.299, 0.587, 0.114));
    
    // Only apply to the sky (depth > 0.99)
    if (depth > 0.99)
    {
        // We only want the Aurora at night. If the sky is already bright (daytime), fade it out.
        float time_sec = Timer * 0.001;
        
        // Complex sine waves for Aurora curtain effect
        float x = texcoord.x * 5.0;
        float y = texcoord.y;
        
        float wave1 = sin(x + time_sec * 0.5) * 0.5 + 0.5;
        float wave2 = sin(x * 2.3 - time_sec * 0.8) * 0.5 + 0.5;
        float wave3 = sin(x * 0.7 + time_sec * 0.3) * 0.5 + 0.5;
        
        float combinedWave = (wave1 + wave2 + wave3) / 3.0;
        
        // Vertical gradient so it fades out towards the top and bottom of the sky
        float verticalFade = smoothstep(0.0, 0.4, y) * smoothstep(1.0, 0.6, y);
        
        // Animate vertical bands
        float bands = sin(x * 15.0 + time_sec * 2.0) * 0.5 + 0.5;
        
        float finalAurora = combinedWave * bands * verticalFade;
        
        // Add color
        float3 auroraGlow = AuroraColor * finalAurora * AuroraIntensity;
        
        // Auto-fade during daytime: If the sky is brighter than 0.2, fade the aurora out
        float nightMultiplier = 1.0 - smoothstep(0.05, 0.25, luma);
        
        color += auroraGlow * nightMultiplier;
    }
    
    return color;
}

technique Aurora
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = AuroraPass;
    }
}
