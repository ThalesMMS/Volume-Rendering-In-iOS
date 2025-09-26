# Research (Phase 0)

## Decisions
- MPR físico: pose por base (U,V,N), centro em origem+0.5U+0.5V, tamanho |U|×|V|.
- Uniforms: Bool → Int32 (Swift/Metal) e remoção de bindings não usados (gradient).
- Projeções: suportar HU gating ON/OFF; default HU [-900, -500].
- TF: TF 1D única; MPR com TF ON por padrão; propagação preset/shift.
- DVR: empty‑space skipping moderado (ZRUN=4, ZSKIP=3).
- Robustez: restaurar lastStep; placeholder 1×1×1 quando `.none`.
- Baseline de performance: iPhone 15 Pro Max com ct_lung ≥ 60 FPS.

## Rationale
- Coerência geométrica reduz ambiguidades entre CPU e GPU e facilita validação visual.
- Int32 em uniforms elimina UB de alinhamento entre Swift e MSL.
- HU gating atende cenários clínicos (MIP/MinIP/AIP) com valores absolutos.
- TF consistente evita discrepâncias entre DVR e MPR e simplifica a UX.
- Skipping moderado busca ganho de FPS sem artefatos em bordas.
- Correções evitam estados inválidos e crashes em bindings exigentes.

## Alternatives Considered
- Skipping agressivo (ZRUN=3, ZSKIP=4): maior risco de artefatos.
- TF apenas no DVR: reduz consistência visual com MPR.
- Manter bool nativo em uniforms: riscos de desalinhamento em alguns GPUs.

## Open Questions
- Metas de logging/telemetria (observability) ainda não definidas.
- UI para controles HU/TF no MPR pode ser adiada; API primeiro.
