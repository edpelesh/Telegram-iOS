#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
    float2 worldPos;
};

struct Uniforms {
    float4x4 modelViewProjection; // 64 bytes
    float4 captureRect; // 16 bytes
    float2 knobCenter; // 8 bytes
    float time; // 4 bytes
    float lastTime; // 4 bytes
    float refractionStrength; // 4 bytes
    float interactionProgress; // 4 bytes
    float2 viewportSize; // 8 bytes
    float2 knobPosition; // 8 bytes
    float2 knobViewOrigin; // 8 bytes
    float2 backgroundSize; // 8 bytes
    float2 parentViewSize; // 8 bytes
    float2 parentViewSizePoints; // 8 bytes
    float2 pillSize; // 8 bytes
    float pillRadius; // 4 bytes
    float2 touchPosition; // 8 bytes
    float2 touchVelocity; // 8 bytes
    float currentElongation; // 4 bytes
    float currentSquash; // 4 bytes
    float shadowScale; // 4 bytes
    float thickness; // 4 bytes
};

vertex VertexOut vertexShader(VertexIn in [[stage_in]],
                              constant Uniforms &uniforms [[buffer(1)]]) {
    VertexOut out;
    out.position = float4(in.position, 0.0, 1.0);
    out.texCoord = in.texCoord;
    out.worldPos = in.texCoord * uniforms.viewportSize;
    return out;
}

float sdfRect(float2 center, float2 size, float2 p, float r) {
    float2 p_rel = p - center;
    float2 q = abs(p_rel) - size;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float softShadowFactor(float sd, float blur, float weight) {
    float softness = blur * 2.0;
    float a = smoothstep(softness, 0.0, sd);
    a = a * a * a;
    return a * weight;
}


float4 bgImage(texture2d<float> tex, sampler s, float2 uv) {
    return float4(tex.sample(s, uv));
}

fragment float4 sliderKnobFragment(VertexOut in [[stage_in]],
                               texture2d<float> backgroundTexture [[texture(0)]],
                               constant Uniforms &uniforms [[buffer(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);

    float2 fragCoord = in.texCoord * uniforms.viewportSize;
    float2 viewportSize = uniforms.viewportSize;

    float2 pillSize = uniforms.pillSize;
    float pillRadius = uniforms.pillRadius;
    
    float2 centerIOS = uniforms.knobCenter;
    float2 center = float2(centerIOS.x, viewportSize.y - centerIOS.y);
    
    float2 touchPos = uniforms.touchPosition;
    float2 touchVelocity = uniforms.touchVelocity;
    
    float2 basePillHalfSize = pillSize * 0.5;

    float stretchX = uniforms.currentElongation;
    float compressY = uniforms.currentSquash;

    float2 elongatedSize = basePillHalfSize;
    elongatedSize.x += stretchX;
    elongatedSize.y = clamp(basePillHalfSize.y - compressY, basePillHalfSize.y * 0.5, basePillHalfSize.y * 1.35);
    
    float maxStretchMultiplier = 1.6;
    elongatedSize.x = clamp(elongatedSize.x, basePillHalfSize.x * 0.7, basePillHalfSize.x * maxStretchMultiplier);
    
    float2 pillHalfSize = elongatedSize;
    
    float morphedHeight = pillHalfSize.y * 2.0;
    float r = morphedHeight * 0.5;
    r = min(r, min(pillHalfSize.x, pillHalfSize.y));
    r = max(r, 1.0);
    
    float2 sdfHalfSize = max(pillHalfSize - float2(r), float2(0.0));
    float2 morphedCenter = center;

    float sd = sdfRect(morphedCenter, sdfHalfSize, fragCoord, r);
    float shadowOffset = 2.0;
    float shadowBlur = 8.0;
    float2 shadowCenter = morphedCenter + float2(shadowOffset, -shadowOffset);
    float shadowSd = sdfRect(shadowCenter, sdfHalfSize, fragCoord, r);
    
    float shadowOffset2 = 1.0;
    float shadowBlur2 = 2.5;
    float2 shadowCenter2 = morphedCenter + float2(shadowOffset2, -shadowOffset2);
    float shadowSd2 = sdfRect(shadowCenter2, sdfHalfSize, fragCoord, r);

    bool insideGlass = (sd <= 0.0);
    bool insideShadow = (shadowSd < shadowBlur);
    bool insideShadow2 = (shadowSd2 < shadowBlur2);
    
    float interactionProgress = uniforms.interactionProgress;
    float shadowScale = uniforms.shadowScale;
    float thickness = uniforms.thickness;
    
    if (!insideGlass && !insideShadow && !insideShadow2) {
        discard_fragment();
    }
    float index = 1.5;
    float base_height = thickness * 8.0;
    float color_mix = 0.3;
    float4 color_base = float4(1.0, 1.0, 1.0, 0.0);

    float2 uv = fragCoord / uniforms.viewportSize;

    float4 bg_col = float4(0.0);
    
    float4 captureRect = uniforms.captureRect;
    
    float2 fragCoordIOS = fragCoord;
    fragCoordIOS.y = viewportSize.y - fragCoordIOS.y;
    
    if (!is_null_texture(backgroundTexture) && uniforms.backgroundSize.x > 0.0 && uniforms.backgroundSize.y > 0.0) {
        float2 fragCoordWindow = fragCoordIOS + uniforms.knobViewOrigin;
        float2 relativePos = fragCoordWindow - captureRect.xy;
        float2 uv = relativePos / captureRect.zw;
        
        float2 bgUV = float2(uv.x, 1.0 - uv.y);
        bgUV = clamp(bgUV, 0.0, 1.0);
        bg_col = bgImage(backgroundTexture, textureSampler, bgUV);
        bg_col = mix(float4(0.0), bg_col, clamp(sd / 100.0, 0.0, 1.0) * 0.1 + 0.9);
        bg_col.a = smoothstep(-4.0, 0.0, sd);
    } else {
        bg_col = float4(0.9, 0.9, 0.9, 1.0);
        bg_col.a = smoothstep(-4.0, 0.0, sd);
    }

    if (!insideGlass && !insideShadow && !insideShadow2) {
        discard_fragment();
    }

    float4 result;

    if (insideGlass) {
        float dx = dfdx(sd);
        float dy = dfdy(sd);
        float n_cos = max(thickness + sd, 0.0) / thickness;
        float n_sin = sqrt(1.0 - n_cos * n_cos);
        float3 normal = normalize(float3(dx * n_cos, dy * n_cos, n_sin));

        float3 incident = float3(0.0, 0.0, -1.0);
        float3 refract_vec = refract(incident, normal, 1.0 / index);
        float h;
        if (sd >= 0.0) {
            h = 0.0;
        } else if (sd < -thickness) {
            h = thickness;
        } else {
            float x = thickness + sd;
            h = sqrt(thickness * thickness - x * x);
        }
        float refract_length = (h + base_height) / dot(float3(0.0, 0.0, -1.0), refract_vec);

        float2 refractedOffset = refract_vec.xy * refract_length;
        refractedOffset.y = -refractedOffset.y;

        float2 fragCoordFromCenter = fragCoord - morphedCenter;
        float maxDist = length(pillHalfSize);
        float normalizedDist = maxDist > 0.0 ? length(fragCoordFromCenter) / maxDist : 0.0;

        float chromaticStrength = normalizedDist * 0.25;
        float2 redOffset = refractedOffset * (1.0 + chromaticStrength);
        float2 blueOffset = refractedOffset * (1.0 - chromaticStrength);
        float2 redOffsetIOS = float2(redOffset.x, -redOffset.y);
        float2 refractedOffsetIOS = float2(refractedOffset.x, -refractedOffset.y);
        float2 blueOffsetIOS = float2(blueOffset.x, -blueOffset.y);
        
        float2 redFragCoord = fragCoordIOS + redOffsetIOS;
        float2 greenFragCoord = fragCoordIOS + refractedOffsetIOS;
        float2 blueFragCoord = fragCoordIOS + blueOffsetIOS;

        float2 redCoord = redFragCoord + uniforms.knobViewOrigin;
        float2 greenCoord = greenFragCoord + uniforms.knobViewOrigin;
        float2 blueCoord = blueFragCoord + uniforms.knobViewOrigin;

        float2 redRelative = redCoord - captureRect.xy;
        float2 greenRelative = greenCoord - captureRect.xy;
        float2 blueRelative = blueCoord - captureRect.xy;
        
        float2 redNormalized = redRelative / captureRect.zw;
        float2 greenNormalized = greenRelative / captureRect.zw;
        float2 blueNormalized = blueRelative / captureRect.zw;
        
        float2 redUV = float2(redNormalized.x, 1.0 - redNormalized.y);
        float2 greenUV = float2(greenNormalized.x, 1.0 - greenNormalized.y);
        float2 blueUV = float2(blueNormalized.x, 1.0 - blueNormalized.y);
        
        redUV = clamp(redUV, 0.0, 1.0);
        greenUV = clamp(greenUV, 0.0, 1.0);
        blueUV = clamp(blueUV, 0.0, 1.0);

        float4 refract_color = float4(0.0);
        if (!is_null_texture(backgroundTexture) && uniforms.backgroundSize.x > 0.0 && uniforms.backgroundSize.y > 0.0) {
            float4 redSample = bgImage(backgroundTexture, textureSampler, redUV);
            float4 greenSample = bgImage(backgroundTexture, textureSampler, greenUV);
            float4 blueSample = bgImage(backgroundTexture, textureSampler, blueUV);

            refract_color = float4(redSample.r, greenSample.g, blueSample.b, greenSample.a);
        } else {
            refract_color = bg_col;
        }

        float3 reflect_vec = reflect(incident, normal);
        float c = clamp(abs(reflect_vec.x - reflect_vec.y), 0.0, 1.0);
        float4 reflect_color = float4(c, c, c, 0.0);

        result = mix(mix(refract_color, reflect_color, (1.0 - normal.z) * 2.0),
                     color_base, color_mix);

        result = clamp(result, 0.0, 1.0);
        bg_col = clamp(bg_col, 0.0, 1.0);
        result = mix(result, bg_col, bg_col.a);
        result.a = smoothstep(2.0, -2.0, sd);
        
        float4 whitePill = float4(1.0, 1.0, 1.0, result.a);
        float glassProgress = smoothstep(0.0, 0.5, interactionProgress);
        
        result.rgb = mix(whitePill.rgb, result.rgb, glassProgress);
        result.a = whitePill.a;

        if (sd > 0.0) {
            result.a = 0.0;
            discard_fragment();
        }
    } else {
        float primaryShadow = softShadowFactor(shadowSd, shadowBlur, 0.07) * shadowScale;
        float secondaryShadow = softShadowFactor(shadowSd2, shadowBlur2, 0.13) * shadowScale;
        float shadowAlpha = max(primaryShadow, secondaryShadow);
        
        if (shadowAlpha > 0.01) {
            float3 tintColor = clamp(bg_col.rgb, 0.0, 1.0);
            float maxChan = max(tintColor.x, max(tintColor.y, tintColor.z));
            if (maxChan > 0.0001) {
                tintColor /= maxChan;
            } else {
                tintColor = float3(0.0);
            }
            float tintAmount = smoothstep(0.2, 0.7, interactionProgress) * 0.5;
            float3 shadowRgb = mix(float3(0.0), tintColor, tintAmount);
            result = float4(shadowRgb, shadowAlpha);
        } else {
            discard_fragment();
        }
    }

    if (result.a < 0.01) {
        discard_fragment();
    }

    return result;
}
