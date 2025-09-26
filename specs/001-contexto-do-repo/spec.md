# Feature Specification: Melhorias de Renderização (MPR físico, flags seguras, HU gating, TF opcional no MPR, DVR skipping e correções)

**Feature Branch**: `001-contexto-do-repo`  
**Created**: 2025-09-26  
**Status**: Draft  
**Input**: User description: "Contexto do repo (resumo): SceneKit + Metal, DVR/SR/MIP/MinIP/AIP já funcionam; MPR slab thin/oblíquo existe com shader dedicado; TF 1D presente. Precisamos: (A) posicionar o plano MPR fisicamente “dentro” do volume (orientação/escala corretas), (B) blindagem de uniforms booleanos (Int32), (C) gating por HU nativo, (D) TF opcional no MPR, (E) empty‑space skipping simples no DVR. Também consolidamos 3 correções: lastStep, textura placeholder para .none e remoção da textura gradient não usada. PRECISAMOS DE SEGUIR O GUIA NO technical_instructions.md"

## Execution Flow (main)
```
1. Parse user description from Input
   → If empty: ERROR "No feature description provided"
2. Extract key concepts from description
   → Identify: actors, actions, data, constraints
3. For each unclear aspect:
   → Mark with [NEEDS CLARIFICATION: specific question]
4. Fill User Scenarios & Testing section
   → If no clear user flow: ERROR "Cannot determine user scenarios"
5. Generate Functional Requirements
   → Each requirement must be testable
   → Mark ambiguous requirements
6. Identify Key Entities (if data involved)
7. Run Review Checklist
   → If any [NEEDS CLARIFICATION]: WARN "Spec has uncertainties"
   → If implementation details found: ERROR "Remove tech details"
8. Return: SUCCESS (spec ready for planning)
```

---

## ⚡ Quick Guidelines
- ✅ Focus on WHAT users need and WHY
- ❌ Avoid HOW to implement (no tech stack, APIs, code structure)
- 👥 Written for business stakeholders, not developers

### Section Requirements
- **Mandatory sections**: Must be completed for every feature
- **Optional sections**: Include only when relevant to the feature
- When a section doesn't apply, remove it entirely (don't leave as "N/A")

### For AI Generation
When creating this spec from a user prompt:
1. **Mark all ambiguities**: Use [NEEDS CLARIFICATION: specific question] for any assumption you'd need to make
2. **Don't guess**: If the prompt doesn't specify something (e.g., "login system" without auth method), mark it
3. **Think like a tester**: Every vague requirement should fail the "testable and unambiguous" checklist item
4. **Common underspecified areas**:
   - User types and permissions
   - Data retention/deletion policies  
   - Performance targets and scale
   - Error handling behaviors
   - Integration requirements
   - Security/compliance needs

---

## Clarifications

### Session 2025-09-26
- Q: Qual baseline de performance devemos usar para validar FPS? → A: iPhone 15 Pro Max
- Q: Precisamos fixar uma janela HU padrão quando o gating estiver ON? → A: [-900, -500]
- Q: TF no MPR vem ON ou OFF por padrão? → A: ON por padrão
- Q: Queremos um limite de segurança para empty‑space skipping? → A: Moderado (ZRUN=4, ZSKIP=3)
- Q: Valor padrão de passos após encerrar interação adaptativa? → A: 128 passos

## User Scenarios & Testing *(mandatory)*

### Primary User Story
Como usuário (clínico/desenvolvedor) eu quero visualizar volumes médicos com:
- Plano MPR corretamente posicionado dentro do volume (coerência física/geométrica);
- Projeções com gating por HU quando habilitado;
- Opção de aplicar a mesma Transfer Function (TF) do DVR no MPR;
- Performance melhor em DVR sem alterar o resultado visual;
- Comportamento robusto dos controles/toggles e ausência de recursos não usados.

### Acceptance Scenarios
1. MPR físico e coerente
   - Given um plano MPR oblíquo com origem e eixos U,V bem definidos,
     When o plano é exibido,
     Then ele aparece centrado em origem+0.5U+0.5V, orientado por U,V e normal N=U×V,
     com largura=|U| e altura=|V| em [0,1]^3, visivelmente “dentro” do volume.
2. Flags/Uniforms seguros
   - Given toggles para iluminação, backward, TF em projeções/MPR,
     When habilitados/desabilitados,
     Then o comportamento corresponde ao esperado em todos os devices, sem avisos de alinhamento/validação de GPU.
3. Gating por HU nativo nas projeções
   - Given useHuGate=on e janela HU [-900, -500],
     When renderizo tórax com MinIP/AIP/MIP,
     Then as estruturas dentro da janela HU passam; fora da janela são descartadas.
     With useHuGate=off, Then a lógica volta ao gating por densidade normalizada.
4. TF opcional no MPR
   - Given TF ativa no DVR e o toggle TF no MPR ligado,
     When visualizo o slab MPR,
     Then a coloração do MPR corresponde à do DVR para a mesma TF; ao desligar, volta a escala de cinza.
5. Empty‑space skipping conservador no DVR
   - Given presets com grandes regiões transparentes (ex.: pulmão),
     When empty‑space skipping está ligado (conservador),
     Then o FPS melhora sem artefatos perceptíveis em bordas de estruturas.
6. Correções de robustez
   - Given interação que reduz passos adaptativos,
     When a interação termina,
     Then o número de passos retorna ao último valor escolhido pelo usuário.
   - Given nenhuma parte carregada (none),
     Then o app permanece estável com um placeholder mínimo (sem crash).
   - Given recursos não usados (ex.: textura gradient desativada),
     Then não há bindings/recursos supérfluos pendentes.

7. Baseline de performance
   - Given preset ct_lung no iPhone 15 Pro Max,
     When renderizo DVR padrão,
     Then o FPS alvo é ≥ 60 e o valor medido deve ser registrado no PR.

### Edge Cases
- Vetores U ou V quase nulos ou colineares: plano ainda deve aparecer com orientação definida de forma estável.
- Plano parcialmente fora do volume: exibição consistente sem artefatos de amostragem.
- Janela HU fora do range do dado: comportamento previsível (clamp ou ausência de elementos passantes).
- TF ausente ou inválida: MPR permanece funcional quando TF‑off; DVR usa TF padrão válida.
- Devices com requisitos estritos de binding: nenhuma textura/parâmetro não utilizado permanece no pipeline.

## Requirements *(mandatory)*

### Functional Requirements
- **FR-001**: O sistema MUST posicionar o plano MPR fisicamente dentro do volume, com centro em origem+0.5U+0.5V, orientação por (U,V,N) e tamanho |U|×|V| em [0,1]^3.
- **FR-002**: O sistema MUST garantir coerência de coordenadas entre CPU e GPU; todas as transformações são determinísticas e documentadas.
- **FR-003**: Toggles/flags de renderização MUST ter semântica de 32 bits consistente entre CPU e GPU e não produzir avisos/erros de alinhamento.
- **FR-004**: Projeções (MIP/MinIP/AIP) MUST suportar gating por HU com janela [minHU, maxHU] quando habilitado e retornar ao gating por densidade normalizada quando desabilitado.
- **FR-005**: O modo de gating (HU vs. normalizado) MUST ser selecionável por controle explícito.
- **FR-006**: O MPR MUST suportar aplicar opcionalmente a mesma TF 1D utilizada no DVR ao valor do slab final.
- **FR-007**: Atualizações de TF (preset/shift) MUST refletir-se de forma consistente no DVR e, quando habilitado, no MPR.
- **FR-008**: O DVR MUST incluir empty‑space skipping conservador que melhora desempenho sem alterar materialmente o resultado visual.
- **FR-009**: O sistema MUST restaurar automaticamente o número de passos do raymarch para o último valor escolhido pelo usuário após interações que reduzam temporariamente a qualidade.
- **FR-010**: Na ausência de volume carregado, o sistema MUST operar com um placeholder mínimo e permanecer estável.
- **FR-011**: Recursos não utilizados (ex.: textura gradient) MUST ser removidos do pipeline para evitar falhas de binding e reduzir complexidade.
- **FR-012**: Mudanças em controles de renderização MUST ser documentadas brevemente (README) e acompanhadas de evidências visuais quando alterarem a aparência.
- **FR-013**: No iPhone 15 Pro Max com preset ct_lung (DVR padrão), o FPS alvo MUST ser ≥ 60.
- **FR-014**: Quando useHuGate=ON e não houver input do usuário, a janela HU default MUST ser [-900, -500].
- **FR-015**: O estado padrão do MPR MUST iniciar com TF habilitada (useTFMpr=ON).
- **FR-016**: Empty‑space skipping MUST usar por padrão ZRUN=4 e ZSKIP=3; alterações devem ser documentadas no PR com impacto de FPS.
- **FR-017**: O valor padrão de passos MUST ser 128 quando não houver lastStep conhecido; após interação adaptativa deve restaurar o lastStep do usuário.

*Example of marking unclear requirements:*
- **FR-006**: System MUST authenticate users via [NEEDS CLARIFICATION: auth method not specified - email/password, SSO, OAuth?]
- **FR-007**: System MUST retain user data for [NEEDS CLARIFICATION: retention period not specified]

### Key Entities *(include if feature involves data)*
- **Plano MPR**: origem (tex), eixos U e V (tex), normal N, dimensões |U| e |V|, modo slab (thin/oblíquo).
- **Janela HU**: minHU, maxHU, flag de habilitação (useHuGate), modo de projeção (MIP/MinIP/AIP).
- **Transfer Function (TF)**: textura 1D e parâmetros (preset/shift) compartilhados por DVR e MPR (opcional).
- **Controles de Renderização**: iluminação, backward, qualidade/steps, modo de gating, TF no MPR.

---

## Review & Acceptance Checklist
*GATE: Automated checks run during main() execution*

### Content Quality
- [ ] No implementation details (languages, frameworks, APIs)
- [ ] Focused on user value and business needs
- [ ] Written for non-technical stakeholders
- [ ] All mandatory sections completed

### Requirement Completeness
- [ ] No [NEEDS CLARIFICATION] markers remain
- [ ] Requirements are testable and unambiguous  
- [ ] Success criteria are measurable
- [ ] Scope is clearly bounded
- [ ] Dependencies and assumptions identified

---

## Execution Status
*Updated by main() during processing*

- [ ] User description parsed
- [ ] Key concepts extracted
- [ ] Ambiguities marked
- [ ] User scenarios defined
- [ ] Requirements generated
- [ ] Entities identified
- [ ] Review checklist passed

---
