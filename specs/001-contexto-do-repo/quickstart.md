# Quickstart (Phase 1)

## Setup
1. Abra o projeto no Xcode.
2. Garanta git-lfs instalado e `git lfs pull` executado.
3. Rode no device iPhone 15 Pro Max (ou equivalente) com preset `ct_lung`.

## Validações Visuais
- MPR físico
  - Aplique um plano oblíquo; verifique alinhamento e tamanho em [0,1]^3.
- HU gating
  - Habilite useHuGate=1; janela [-900, -500]; veja MIP/MinIP/AIP filtrando estruturas.
  - Desligue o gate; comportamento volta ao normalizado.
- TF no MPR
  - Com TF no DVR, ligue TF no MPR (default ON); compare coloração.
- Empty‑space skipping
  - Em `ct_lung`, confirme melhoria de FPS visível sem artefatos.
- Robustez
  - Interaja (zoom/rotate) e solte; passos voltam ao lastStep.
  - Com `part=.none`, app segue estável (placeholder 1×1×1).

## Métrica de Performance
- DVR com `ct_lung` no iPhone 15 Pro Max deve atingir ≥ 60 FPS.
- Registre o valor medido no PR.

## Artefatos para PR
- Screenshots: `Screenshot/` (adicione imagens do antes/depois do MPR oblíquo)
- Vídeo curto (opcional): demonstração de HU gate e TF no MPR
- Métrica: valor de FPS medido no device alvo
