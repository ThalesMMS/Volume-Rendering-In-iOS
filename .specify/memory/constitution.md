<!--
Sync Impact Report
- Version change: none → 1.0.0
- Modified principles: n/a (new document)
- Added sections: Core Principles; Domain Constraints; Development Workflow & Quality Gates; Governance
- Removed sections: None
- Templates requiring updates:
  ✅ .specify/templates/plan-template.md (version reference → v1.0.0, path corrected)
  ✅ .specify/templates/spec-template.md (no changes required)
  ✅ .specify/templates/tasks-template.md (no changes required)
- Follow-up TODOs: None
-->

# Volume-Rendering-In-iOS Constitution

## Core Principles

### I. Rendering Correctness & Coordinate Coherence (NON-NEGOTIABLE)
- All geometry, sampling, and shader math operate in normalized texture space [0,1]^3.
- Any world/physical-space interaction MUST be mapped deterministically to texture space and documented.
- CPU and GPU coordinate conventions MUST match; transforms are single-sourced and reviewable.
- MPR planes MUST be posed physically inside the volume: orientation from basis (U,V,N), center at origin+0.5U+0.5V, and sized to |U|×|V| in [0,1]^3.
- Acceptance: visual inspection with a non-orthogonal slab verifies alignment while orbiting the camera.

### II. GPU Interface Safety & Memory Layout Discipline
- Uniforms and shader inputs MUST use fixed-size, alignment-safe types (e.g., Int32 for boolean flags).
- No unused resource bindings are permitted; remove dead textures/params to avoid device binding errors.
- Uniform structs MUST remain packed and explicit; any layout change requires a call-site sweep.
- Acceptance: no GPU validation warnings; binaries functionally identical after refactors.

### III. Performance With Visual Fidelity
- Target 60 fps on representative iOS hardware for default presets; document deviations.
- Raymarchers MUST include conservative optimizations (e.g., empty-space skipping) that do not change results materially.
- Gating MUST support density-normalized and native HU ranges for projections.
- Acceptance: presets like lung/air demonstrate measurable FPS improvement without visible artifacts at structure boundaries.

### IV. Transfer Function Consistency Across Views
- A single source-of-truth 1D transfer function drives both volume rendering and MPR slabs when enabled.
- MPR can optionally apply the same TF to the slab result; the toggle is controlled by a uniform.
- TF updates (preset/shift) propagate to all consumers atomically.
- Acceptance: toggling TF-on for MPR yields matching look to DVR with identical TF.

### V. Simplicity, Observability, and Robustness
- Prefer the simplest solution that meets accuracy/performance objectives; remove unused code and bindings.
- Acceptance capture: record before/after screenshots or short videos for visual changes, plus brief notes.
- Public API changes (uniforms, textures, options) MUST include minimal usage notes in README or inline docs.

## Domain Constraints
- Tech Stack: Swift + SceneKit + Metal.
- Data: Int16 signed little-endian raw volumes packaged as .raw.zip in the app bundle.
- Coordinate Systems: normalized texture space [0,1]^3 for sampling; anisotropic scale applied by parent node.
- Device Targets: Current iOS simulator and common devices; performance baselines documented per device when relevant.
- Transfer Functions: 1D texture bound as `transferColor`; no unused gradient textures.
- Projections: DVR, SR, MIP, MinIP, AIP supported; projections respect HU gating when enabled.

## Development Workflow & Quality Gates
- Constitution Check: reviewers verify adherence to the Core Principles for every PR.
- Visual Acceptance: PRs that change rendering include artifacts (images/videos) demonstrating expected output.
- Performance Note: mention FPS impact for heavy shaders; include device and scene preset.
- Uniform/API Changes: document in README section “Rendering Controls” with flag descriptions and defaults.
- Tooling: keep `.specify/templates/*` aligned with this constitution; version reference must match.

## Governance
- Supremacy: This constitution governs design principles and review gates for this repository.
- Amendments: Any change requires a PR that updates this file, states the bump rationale, and includes a brief migration note if APIs change.
- Versioning Policy: Semantic versioning for the constitution.
  - MAJOR: incompatible principle removals/redefinitions.
  - MINOR: new principle/section or materially expanded guidance.
  - PATCH: clarifications and non-semantic edits.
- Compliance: Reviewers MUST block PRs that violate non-negotiable rules unless a narrowly-scoped exception is approved and documented.

**Version**: 1.0.0 | **Ratified**: 2025-09-26 | **Last Amended**: 2025-09-26