# Data Model (Phase 1)

## Entities
- PlanoMPR
  - originTex: float3
  - axisUTex: float3
  - axisVTex: float3
  - normalTex: float3 (derivado)
  - widthTex: float (|U|)
  - heightTex: float (|V|)
  - blendMode: enum {thin, mip, minip, mean}
  - numSteps: int
  - slabHalf: float
  - useTFMpr: int (0/1)

- VolumeUniforms
  - isLightingOn: int (0/1)
  - isBackwardOn: int (0/1)
  - method: int
  - renderingQuality: int (steps)
  - voxelMinValue: int
  - voxelMaxValue: int
  - densityFloor: float
  - densityCeil: float
  - dimX: int
  - dimY: int
  - dimZ: int
  - useTFProj: int (0/1)
  - gateHuMin: int
  - gateHuMax: int
  - useHuGate: int (0/1)

- TransferFunction
  - texture: texture2d<float>
  - preset: enum
  - shift: float

## Relationships
- PlanoMPR consome Volume (textura 3D) e TransferFunction 1D quando `useTFMpr=1`.
- VolumeUniforms é usado pelo DVR/SR/MIP/MinIP/AIP; MPR tem uniform set próprio.

## Validation Rules
- axisUTex e axisVTex não colineares (reprojetar V para ortogonal se necessário).
- widthTex, heightTex > 0 para exibição visível; fallback seguro se muito pequenos.
- Quando useHuGate=1, aplicar gateHuMin/Max; caso contrário usar densityFloor/Ceil.
- renderingQuality default 128; restaurar lastStep ao término de interação adaptativa.
- Empty-space skipping default: ZRUN=4, ZSKIP=3.
