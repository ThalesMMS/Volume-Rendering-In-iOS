# Tasks: Melhorias de Renderização

**Input**: design docs deste diretório
**Prerequisites**: plan.md (required), research.md, data-model.md, contracts/

## Execution Flow (main)
1. Setup (doc updates)
2. Tests (screenshots/metrics)
3. Core (shaders/materials)
4. UI (opcional mínima)
5. Polish (docs/perf notes)

## Tasks
### Setup
- [X] T001 [P] Criar `VolumeRendering-iOS/Source/Helper/SCNNode+Basis.swift` com `setTransformFromBasisTex`
- [X] T002 Atualizar `VolumeRendering-iOS/Source/View/SceneViewController.swift::setMPROblique(...)` para usar helper

### Tests (TDD visual)
- [ ] T003 [P] Capturar screenshots do MPR oblíquo antes/depois (alinhamento)
- [ ] T004 [P] Medir FPS DVR ct_lung em iPhone 15 Pro Max e registrar

### Core
- [X] T005 [P] `VolumeCubeMaterial.swift`: Bool → Int32; setters `setLighting`, `setUseTFOnProjections`
- [X] T006 [P] `volumerendering.metal`: Bool → int; ajustar leituras e `useTFProj`
- [X] T007 [P] Uniforms HU gate (Swift/Metal) + setters `setHuGate`, `setHuWindow` (default [-900, -500])
- [X] T008 [P] Aplicar HU gate em MIP/MinIP/AIP no shader
- [X] T009 [P] `mpr.metal`: `useTFMpr` + textura `transferColor`; retorno TF quando ON
- [X] T010 [P] `MPRPlaneMaterial.swift`: campo `useTFMpr` (default ON), bind `transferColor`, `setUseTF(_:)`
- [X] T011 Propagar TF do volume para MPR em `SceneViewController` (preset/shift)
- [X] T012 DVR: empty‑space skipping (ZRUN=4, ZSKIP=3)
- [X] T013 `SceneViewController.setStep`: restaurar `lastStep` corretamente; default `renderingQuality` = 128 quando `lastStep` ausente
- [X] T014 `VolumeTextureFactory`: placeholder 1×1×1 para `.none`
- [X] T015 `volumerendering.metal`: auditar binding `gradient`; se existir, remover; se não existir, apenas confirmar ausência (sem mudanças)

### UI (opcional)
- [X] T016 [P] `ContentView.swift`: toggles/controles para HU gate e TF no MPR

### Polish
- [X] T017 [P] Atualizar `README.md` (Add data, Licenses, Screenshots, Known issues)
- [X] T018 [P] Atualizar `quickstart.md` com artefatos e FPS medido
- [ ] T019 Revisão constitucional: anexar evidências visuais no PR e checar princípios

## Dependencies
- Tests antes de implementação visual (T003-T004 antes de T005+)
- T001 precede T002
- T009-T011 podem ocorrer em paralelo após T005-T006

## Parallel Example
```
# Grupo 1 (paralelo)
T003, T004, T005, T006, T007, T009, T010, T012, T014, T015, T016, T017, T018

# Grupo 2 (sequencial por dependência)
T001 → T002 → T011 → T013
```

## Validation Checklist
- [ ] Uniforms/flags em Int32 (Swift/Metal) e sem warnings
- [ ] Nenhum binding/texture não usado (gradient removido)
- [ ] HU gate ON funcional; default HU aplicado
- [ ] MPR com TF ON por padrão e sincronizado com DVR
- [ ] DVR skipping moderado e sem artefatos
- [ ] Passos restauram lastStep; fallback 128
- [ ] FPS ≥ 60 (ct_lung) e valor registrado no PR
