//
//  mpr.metal
//  Isis DICOM Viewer
//
//  MVP MPR Shader (Metal)
//  - Renderiza um plano de reamostragem dentro do volume (dicom 3D).
//  - Suporta MPR fino e thick slab com MIP/MinIP/Mean.
//  - Normalização HU -> [0,1] via min/max (mesma ideia do VR).
//  Thales Matheus Mendonça Santos - September 2025
//

#include <metal_stdlib>
#include "shared.metal"   // traz NodeBuffer, SCNSceneBuffer, samplers e Utils

using namespace metal;

struct MPRUniforms {
    int   voxelMinValue;
    int   voxelMaxValue;
    int   blendMode;     // 0=single, 1=MIP, 2=MinIP, 3=Mean
    int   numSteps;      // >=1; 1 => MPR fino
    float slabHalf;      // metade da espessura em [0,1]
    float3 _pad0;

    float3 planeOrigin;  // origem do plano em [0,1]^3
    float  _pad1;
    float3 planeX;       // eixo U do plano (tamanho = largura em [0,1])
    float  _pad2;
    float3 planeY;       // eixo V do plano (tamanho = altura em [0,1])
    float  _pad3;
    int   useTFMpr;      // 0=grayscale, 1=usar TF 1D
    int   _pad4; int _pad5; int _pad6;
};

struct VertexIn {
    float3 position  [[attribute(SCNVertexSemanticPosition)]];
    float3 normal    [[attribute(SCNVertexSemanticNormal)]];
    float4 color     [[attribute(SCNVertexSemanticColor)]];
    float2 uv        [[attribute(SCNVertexSemanticTexcoord0)]];
};

struct VSOut {
    float4 position [[position]];
    float2 uv;
};

vertex VSOut mpr_vertex(VertexIn in                   [[ stage_in ]],
                        constant NodeBuffer& scn_node [[ buffer(1) ]]) {
    VSOut out;
    out.position = Unity::ObjectToClipPos(float4(in.position, 1.0f), scn_node);
    out.uv = in.uv;
    return out;
}

inline float sampleDensity01(texture3d<short, access::sample> volume, float3 p,
                             short minV, short maxV) {
    short hu = volume.sample(sampler3d, p).r;
    return Util::normalize(hu, minV, maxV); // HU -> [0,1]
}

fragment float4 mpr_fragment(VSOut in                                       [[stage_in]],
                             constant SCNSceneBuffer& scn_frame              [[buffer(0)]],
                             constant NodeBuffer& scn_node                   [[buffer(1)]],
                             constant MPRUniforms& U                         [[buffer(4)]],
                             texture3d<short, access::sample> volume         [[texture(0)]],
                             texture2d<float, access::sample> transferColor  [[texture(3)]]) {

    // Coord do plano no volume (normalizada)
    float3 Pw = U.planeOrigin + in.uv.x * U.planeX + in.uv.y * U.planeY;

    // Fora do volume? (com pequena margem)
    if (any(Pw < -1e-6) || any(Pw > 1.0 + 1e-6)) {
        return float4(0,0,0,1);
    }

    if (U.numSteps <= 1 || U.slabHalf <= 0.0f || U.blendMode == 0) {
        // MPR fino (uma amostra) OU modo single
        float d = sampleDensity01(volume, Pw, (short)U.voxelMinValue, (short)U.voxelMaxValue);
        return (U.useTFMpr != 0) ? VR::getTfColour(transferColor, d) : float4(d, d, d, 1);
    }

    // Thick slab: percorre ao longo da normal do plano
    float3 N = normalize(cross(U.planeX, U.planeY));
    int steps = max(2, U.numSteps);
    int halfSteps = (steps - 1) / 2;
    float stepN = (2.0f * U.slabHalf) / float(steps - 1);

    float vmax = 0.0f;
    float vmin = 1.0f;
    float vacc = 0.0f;
    int   cnt  = 0;

    for (int i = -halfSteps; i <= halfSteps; ++i) {
        float3 Pi = Pw + float(i) * stepN * N;
        if (any(Pi < 0.0f) || any(Pi > 1.0f)) continue;

        float d = sampleDensity01(volume, Pi, (short)U.voxelMinValue, (short)U.voxelMaxValue);
        vmax = max(vmax, d);
        vmin = min(vmin, d);
        vacc += d;
        cnt++;
    }

    float val = 0.0f;
    switch (U.blendMode) {
        case 1: val = vmax; break;                          // MIP
        case 2: val = (cnt > 0 ? vmin : 0.0f); break;       // MinIP
        case 3: val = (cnt > 0 ? (vacc / float(cnt)) : 0.0f); break; // Mean
        default: // fallback single
            val = sampleDensity01(volume, Pw, (short)U.voxelMinValue, (short)U.voxelMaxValue);
    }

    if (U.useTFMpr != 0) {
        float4 tfColor = VR::getTfColour(transferColor, val);
        if (length(tfColor.rgb) < 0.001) {
            return float4(val, val, val, 1);
        }
        return tfColor;
    } else {
        return float4(val, val, val, 1);
    }
}

