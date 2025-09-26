Contexto do repo (resumo): SceneKit + Metal, DVR/SR/MIP/MinIP/AIP já funcionam; MPR slab thin/oblíquo existe com shader dedicado; TF 1D presente. Precisamos: (A) posicionar o plano MPR fisicamente “dentro” do volume (orientação/escala corretas), (B) blindagem de uniforms booleanos (Int32), (C) gating por HU nativo, (D) TF opcional no MPR, (E) empty‑space skipping simples no DVR. Também consolidamos 3 correções: lastStep, textura placeholder para .none e remoção da textura gradient não usada.
A) Plano MPR no espaço físico (posição/orientação/escala corretas)
Objetivo
Renderizar o plano MPR acoplado ao cubo do volume (filho do nó volume), com posição no centro do retângulo do plano, orientação coerente (eixos U,V) e largura/altura iguais às normas de axisU/axisV (em coords de textura [0,1]^3), deixando a escala anisotrópica para o pai (volume.scale = mat.scale).
Mudança de API
Novo helper SCNNode+Basis.swift: setTransformFromBasisTex(originTex: UTex: VTex:) que:
ajusta rotação (converte base U,V → N para quaternion);
ajusta posição local (centro do plano em coords locais do cubo);
ajusta plane.width/plane.height = |U|/|V| (normas em [0,1]).
Patches
1) Novo arquivo VolumeRendering-iOS/Source/Helper/SCNNode+Basis.swift
import SceneKit
import simd

extension SCNNode {
    /// Configura pose de um plano (SCNPlane) filho do cubo do volume.
    /// originTex, UTex, VTex em coordenadas de textura [0,1]^3 (mesmo espaço do shader).
    /// - Nota: o nó deve ser FILHO de `volume` para herdar a escala anisotrópica.
    func setTransformFromBasisTex(originTex o: simd_float3,
                                  UTex u: simd_float3,
                                  VTex v: simd_float3)
    {
        // 1) Dimensões do retângulo (em [0,1])
        let w = simd_length(u)
        let h = simd_length(v)

        // 2) Base ortonormal (rotação)
        let Uhat = w > 0 ? simd_normalize(u) : simd_float3(1,0,0)
        let vOrtho = v - simd_dot(v, Uhat) * Uhat
        let Vhat = simd_length(vOrtho) > 0 ? simd_normalize(vOrtho) : simd_float3(0,1,0)
        let Nhat = simd_normalize(simd_cross(Uhat, Vhat))
        let R = simd_float3x3(columns: (Uhat, Vhat, Nhat))

        // 3) Centro do plano em local do cubo [-0.5..+0.5]^3
        // centerTex = o + 0.5*u + 0.5*v; centerLocal = centerTex - 0.5
        let centerLocal = o + 0.5*u + 0.5*v - simd_float3(0.5, 0.5, 0.5)

        // 4) Aplicar à node (posição local + rotação)
        self.simdOrientation = simd_quatf(R)
        self.simdPosition    = centerLocal

        // 5) Largura/altura do SCNPlane no espaço local do cubo
        if let plane = self.geometry as? SCNPlane {
            plane.width  = CGFloat(w)
            plane.height = CGFloat(h)
        }
    }
}
2) Atualizar SceneViewController.setMPROblique(...) para usar o helper
 func setMPROblique(using geom: DICOMGeometry,
                    originMm: simd_float3,
                    axisUMm: simd_float3,
                    axisVMm: simd_float3)
 {
     let (o,u,v) = geom.planeWorldToTex(originW: originMm, axisUW: axisUMm, axisVW: axisVMm)
     mprMat?.setOblique(origin: float3(o), axisU: float3(u), axisV: float3(v))
+    // Pose física do plano (filho do cubo do volume).
+    if let node = mprNode {
+        node.setTransformFromBasisTex(originTex: o, UTex: u, VTex: v)
+        node.isHidden = false
+    }
 }
Obs. sobre profundidade: manter mprMat.writesToDepthBuffer = false (como já está) evita conflitos com o volume (que não escreve depth “físico”). O plano ficará corretamente posicionado sem tentar “ocluir” DVR. Se quiser experimentar oclusão, altere os flags mais tarde.
Critérios de aceitação
Ao chamar setMPROblique(...), o plano gira e transla para o local correto.
plane.width/height refletem o tamanho do retângulo em [0,1].
Ao alterar geom ou os vetores, a pose atualiza sem distorções (além da anisotropia herdada do pai).
Armadilhas
Se o plano for irmão (e não filho) do volume, você deve aplicar a mesma escala anisotrópica no nó do plano manualmente. O design acima assume filho do volume.
B) Blindagem de uniforms booleanos (usar Int32)
Objetivo
Evitar desalinhamento/UB de Bool Swift ↔︎ bool MSL em alguns GPUs. Usar Int32 (0/1) em Swift e int em Metal.
Mudança de API
VolumeCubeMaterial.Uniforms: isLightingOn, isBackwardOn, useTFProj → Int32
volumerendering.metal::Uniforms: bool → int
Callers que setam flags passam 1/0.
Patches
1) VolumeCubeMaterial.swift (trechos impactados)
 struct Uniforms: sizeable {
-    var isLightingOn: Bool = true
-    var isBackwardOn: Bool = false
+    var isLightingOn: Int32 = 1
+    var isBackwardOn: Int32 = 0
     var method: Int32 = Method.dvr.idInt32
     var renderingQuality: Int32 = 512
     var voxelMinValue: Int32 = -1024
     var voxelMaxValue: Int32 =  3071
     var densityFloor: Float = 0.02
     var densityCeil:  Float = 1.00
     var dimX: Int32 = 1
     var dimY: Int32 = 1
     var dimZ: Int32 = 1
-    var useTFProj: Bool = false
+    var useTFProj: Int32 = 0
     var _pad0: Int32 = 0
     var _pad1: Int32 = 0
     var _pad2: Int32 = 0
 }

 func setLighting(on: Bool) {
-    uniforms.isLightingOn = on
+    uniforms.isLightingOn = on ? 1 : 0
     pushUniforms()
 }

 func setUseTFOnProjections(_ on: Bool) {
-    uniforms.useTFProj = on
+    uniforms.useTFProj = on ? 1 : 0
     pushUniforms()
 }
2) volumerendering.metal (struct + usos)
 struct Uniforms {
-    bool  isLightingOn;
-    bool  isBackwardOn;
+    int   isLightingOn;
+    int   isBackwardOn;
     int   method;
     int   renderingQuality;
     int   voxelMinValue;
     int   voxelMaxValue;
     float densityFloor;
     float densityCeil;
     int   dimX; int dimY; int dimZ;
-    bool  useTFProj;
+    int   useTFProj;
     int   _pad0; int _pad1; int _pad2;
 };
 ...
-    bool isLightingOn = uniforms.isLightingOn;
-    bool isBackwardOn = uniforms.isBackwardOn;
+    bool isLightingOn = (uniforms.isLightingOn != 0);
+    bool isBackwardOn = (uniforms.isBackwardOn != 0);
 ...
-    out.color = useTFProj ? VR::getTfColour(tfTable, val) : float4(val);
+    out.color = (uniforms.useTFProj != 0) ? VR::getTfColour(tfTable, val) : float4(val);
Critérios de aceitação
Binários idênticos em funcionalidade, sem warnings de alinhamento.
Todos os toggles continuam funcionando.
C) Gating por HU (além do [0,1])
Objetivo
Permitir gating diretamente em HU. Útil para MIP/MinIP/AIP clínicos.
Mudança de API
Swift Uniforms (volume): gateHuMin/Max: Int32, useHuGate: Int32
Metal Uniforms: idem.
Shaders de projeção: escolhem entre HU ou densidade normalizada.
Patches
1) VolumeCubeMaterial.Uniforms + setters
 struct Uniforms: sizeable {
   ...
   var densityFloor: Float = 0.02
   var densityCeil:  Float = 1.00
+  var gateHuMin: Int32 = -32768
+  var gateHuMax: Int32 =  32767
+  var useHuGate: Int32 = 0
   ...
 }

+func setHuGate(enabled: Bool) {
+    uniforms.useHuGate = enabled ? 1 : 0
+    pushUniforms()
+}
+
+func setHuWindow(minHU: Int32, maxHU: Int32) {
+    uniforms.gateHuMin = minHU
+    uniforms.gateHuMax = maxHU
+    pushUniforms()
+}
2) volumerendering.metal (gates + usos)
 struct Uniforms {
   ...
   float densityFloor; float densityCeil;
+  int   gateHuMin; int gateHuMax; int useHuGate;
   int   dimX; int dimY; int dimZ;
   int   useTFProj; int _pad0; int _pad1; int _pad2;
 };
Aplique em MIP/MinIP/AIP (mesma lógica; exemplo no MIP):
 short hu = VR::getDensity(volume, currPos);
 float density = Util::normalize(hu, minV, maxV);
-// Gating normalizado
-if (density < densityFloor || density > densityCeil) continue;
+// Gating: HU ou normalizado
+bool pass;
+if (uniforms.useHuGate != 0) {
+    pass = (hu >= uniforms.gateHuMin) && (hu <= uniforms.gateHuMax);
+} else {
+    pass = (density >= densityFloor) && (density <= densityCeil);
+}
+if (!pass) continue;
3) UI (opcional mínimo) – adicionar 3 controles (toggle + 2 sliders/steppers) em ContentView.swift chamando SceneViewController.Instance.setHuGate(...) e setHuWindow(...). (Se não precisar de UI agora, manter só a API.)
Critérios de aceitação
Com useHuGate=1, projeções respeitam HU mesmo se densityFloor/Ceil estiverem configurados.
Com useHuGate=0, comportamento atual (normalizado) persiste.
D) TF opcional no MPR (slab)
Objetivo
Aplicar TF 1D ao valor resultante do slab (single/MIP/MinIP/Mean) em mpr.metal.
Mudança de API
MPRUniforms: useTFMpr: Int32
mpr_fragment: recebe texture2d<float> transferColor e usa VR::getTfColour(...)
MPRPlaneMaterial: binding da TF e setter setUseTF(_:).
Propagar TF do volume para o MPR em SceneViewController (mesma textura).
Patches
1) mpr.metal
 struct MPRUniforms {
   int   voxelMinValue;
   int   voxelMaxValue;
   int   blendMode;
   int   numSteps;
   float slabHalf;
   float3 _pad0;
   float3 planeOrigin; float _pad1;
   float3 planeX;      float _pad2;
   float3 planeY;      float _pad3;
+  int   useTFMpr;
+  int   _pad4; int _pad5; int _pad6;
 };
 ...
-fragment float4 mpr_fragment(...,
-                             texture3d<short, access::sample> volume [[texture(0)]]) {
+fragment float4 mpr_fragment(...,
+                             texture3d<short, access::sample> volume         [[texture(0)]],
+                             texture2d<float, access::sample> transferColor [[texture(3)]]) {
   ...
-  return float4(val, val, val, 1);
+  return (U.useTFMpr != 0) ? VR::getTfColour(transferColor, val) : float4(val);
}
2) MPRPlaneMaterial.swift
 final class MPRPlaneMaterial: SCNMaterial {
   struct Uniforms: sizeable {
     ...
+    var useTFMpr: Int32 = 0
   }
   private let uniformsKey = "uniforms"
   private let dicomKey    = "dicom"
+  private let tfKey       = "transferColor"
   ...
   private func setDicomTexture(_ texture: MTLTexture) { ... }
+  private func setTransferFunctionTexture(_ texture: MTLTexture) {
+      let prop = SCNMaterialProperty(contents: texture as Any)
+      setValue(prop, forKey: tfKey)
+  }
   ...
+  func setUseTF(_ on: Bool) {
+      uniforms.useTFMpr = on ? 1 : 0
+      setUniforms(uniforms)
+  }
+  func setTransferFunction(_ texture: MTLTexture) {
+      setTransferFunctionTexture(texture)
+  }
 }
3) Propagar TF do volume em SceneViewController (quando setPreset/setShift atualizam TF):
 func setPreset(preset: VolumeCubeMaterial.Preset) {
     mat.setPreset(device: device, preset: preset)
     mat.setShift(device: device, shift: 0)
+    // Propaga TF corrente ao MPR (se existir)
+    if let tfTex = (mat.value(forKey: "transferColor") as? SCNMaterialProperty)?.contents as? MTLTexture {
+        mprMat?.setTransferFunction(tfTex)
+    }
 }
 func setShift(shift: Float) {
     mat.setShift(device: device, shift: shift)
+    if let tfTex = (mat.value(forKey: "transferColor") as? SCNMaterialProperty)?.contents as? MTLTexture {
+        mprMat?.setTransferFunction(tfTex)
+    }
 }
Se quiser um controle na UI: Toggle("TF no MPR", ...) chamando SceneViewController.Instance.setMPRUseTF(on:) que só encaminha para mprMat?.setUseTF(on).
Critérios de aceitação
Em slab MPR, alternar TF on/off muda o look como no MIP.
TF sincronizada com a TF do volume (preset/shift).
E) Empty-space skipping (DVR) simples
Objetivo
Acelerar DVR quando a TF gera α≈0 por várias amostras seguidas (ar/pulmão).
Mudança de API
Nenhuma pública. Apenas lógica no shader.
Patch (em direct_volume_rendering de volumerendering.metal)
 float4 col = float4(0.0f);
+int zeroCount = 0;
+constexpr int ZRUN = 6;   // amostras transparentes consecutivas para detetar “vazio”
+constexpr int ZSKIP = 2;  // salto curto (tuneável)

 for (int iStep = 0; iStep < raymarch.numSteps; iStep++)
 {
   ...
   if (isLightingOn)
       src.rgb = Util::calculateLighting(...);

   if (density < 0.1f)
       src.a = 0.0f;

+  // Empty-space skipping (transparência consecutiva)
+  if (src.a < 0.001f) {
+      zeroCount++;
+      if (zeroCount >= ZRUN) {
+          iStep += ZSKIP;      // salta algumas amostras
+          zeroCount = 0;
+          continue;
+      }
+  } else {
+      zeroCount = 0;
+  }

   if (isBackwardOn) {
     ...
   } else {
     ...
   }
   if (col.a > 1) break;
 }
Critérios de aceitação
FPS melhor em presets “lung/air” sem perda visual significativa.
Sem artefatos notáveis em limites de estruturas (valores conservadores acima).
Correções de robustez (recomendadas)
1) Adaptive steps: restaurar para o valor real do slider
// SceneViewController.swift
func setStep(step: Float) {
-    mat.setStep(step: step)
+    lastStep = step          // ✅ garante restauração correta
+    mat.setStep(step: step)
}
2) Textura placeholder quando part == .none
// VolumeTextureFactory.generate(...)
 if part == .none {
-    return device.makeTexture(descriptor: descriptor)!
+    descriptor.width = 1
+    descriptor.height = 1
+    descriptor.depth = 1
+    return device.makeTexture(descriptor: descriptor)!
 }
3) Remover textura gradient [[texture(2)]] não usada
Em volumerendering.metal, remova o parâmetro texture3d<float, ...> gradient [[texture(2)]] da volume_fragment.
Nenhum outro código precisa dessa textura hoje; isso evita crashes em devices que exigem binding.
README.md – addenda
Inclua os blocos abaixo (ou ajuste sua seção atual):
Add your own data
Raw layout: Int16 (signed), little‑endian, row‑major (x fast, depois y, depois z por slice).
Arquivo: <name>.raw (size = dimX*dimY*dimZ*2 bytes). Comprima como <name>.raw.zip e coloque no bundle.
Dimensões/spacing: configure em VolumeTextureFactory(part) ou crie nova entrada (dimensão e resolution).
Licenses/Attributions
UnityVolumeRendering (MIT): ideias/TF presets.
ZIPFoundation (MIT/BSD): leitura de .zip.
Este repositório: (sua licença).
Screenshots
Adicione uma tabela com MIP vs MinIP e gating (0.02–1.00) + TF on/off.
Known issues
(Remova a observação sobre gradient [[texture(2)]] se aplicar o patch de remoção.)
Checklist final (para Codex)
Criar SCNNode+Basis.swift (helper).
SceneViewController: aplicar helper em setMPROblique; fix de setStep; propagar TF para mprMat.
MPR:
mpr.metal: useTFMpr + transferColor + return TF.
MPRPlaneMaterial: useTFMpr + tfKey + setUseTF(_:) + setTransferFunction(_:).
Volume:
VolumeTextureFactory: placeholder 1×1×1 para .none.
VolumeCubeMaterial.Uniforms: booleans → Int32; novos campos de HU gate; setters setHuGate, setHuWindow.
volumerendering.metal: booleans → int; HU gate em MIP/MinIP/AIP; remover gradient do fragment.
DVR: empty‑space skipping.
UI (opcional agora): toggles/sliders para HU gate e TF no MPR.
README: adicionar “Add your own data”, “Licenses”, screenshots; limpar “Known issues”.
Testes de aceitação (rápidos)
MPR oblíquo: forneça geom real e um plano não ortogonal; verifique pose e tamanho do plano alinhados ao volume ao orbitar a câmera.
Gating HU: useHuGate=1, [-900, -500] em tórax → MinIP realça vias aéreas; desligue (0) e ajuste densityFloor/Ceil → efeito volta ao normalizado.
TF no MPR: on/off muda claramente MIP no MPR slab.
DVR skipping: FPS melhora em ct_lung com pouca mudança visual.
Adaptive: arraste/zoom/rotate → steps reduzem e voltam ao final (sem “ficar preso” em 512).