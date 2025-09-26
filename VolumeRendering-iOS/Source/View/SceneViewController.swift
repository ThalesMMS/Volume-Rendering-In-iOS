//
//  SceneViewController.swift
//  VolumeRendering-iOS
//
//  Created by won on 2022/05/30.
//

import Foundation
import SceneKit

class SceneViewController: NSObject {
    static let Instance = SceneViewController() // like Singleton
    
    enum RenderMode: String, CaseIterable, Identifiable {
        var id: RawValue { rawValue }
        case surf, dvr, mip, minip, avg, mpr
    }

    var device: MTLDevice!
    var root: SCNNode!
    var cameraController: SCNCameraController!
    
    var volume: SCNNode!
    var mat: VolumeCubeMaterial!
    // --- MPR ---
    private var mprNode: SCNNode?
    private var mprMat: MPRPlaneMaterial?

    private var activeRenderMode: RenderMode = .dvr
    private var adaptiveOn: Bool = true
    private var lastStep: Float = 128
    private var interactionFactor: Float = 0.35 // 35% dos steps durante interação
    
    override public init() { super.init() }
    
    func onAppear(_ view: SCNView) {
        // Verificar device Metal
        guard let device = view.device else {
            print("🚨 ERRO: Dispositivo Metal não disponível")
            return
        }
        self.device = device
        
        // Verificar scene
        guard let scene = view.scene else {
            print("🚨 ERRO: Scene não inicializada")
            return
        }
        root = scene.rootNode
        cameraController = view.defaultCameraController
        
        let box = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0)
        mat = VolumeCubeMaterial(device: device)
        mat.setPart(device: device, part: .none)

        // Manter a inicialização da TF default, mas com verificação
        if let url = Bundle.main.url(forResource: "ct_arteries", withExtension: "tf") {
            let tf = TransferFunction.load(from: url)
            mat.tf = tf  // Armazena a TF para uso posterior
            if let tfTexture = tf.get(device: device) {
                mat.setTransferFunctionTexture(tfTexture)
            }
        }

        // Default de qualidade quando não houver lastStep do usuário
        mat.setStep(step: lastStep)
        volume = SCNNode(geometry: box)
        volume.geometry?.materials = [mat]
        volume.scale = SCNVector3(mat.scale)
        root.addChildNode(volume)
        
//        // for depth test
//        let node2 = SCNNode(geometry: SCNBox(width: 0.2, height: 0.2, length: 0.2, chamferRadius: 0))
//        node2.geometry?.firstMaterial?.diffuse.contents = UIColor.yellow
//        node2.position = SCNVector3Make(0.5, 0, 0.5)
//        root.addChildNode(node2)
//
//        let node3 = SCNNode(geometry: SCNSphere(radius: 0.2))
//        node3.geometry?.firstMaterial?.diffuse.contents = UIColor.green
//        node3.position = SCNVector3Make(-0.5, 0, 0.5)
//        root.addChildNode(node3)
        
        cameraController.target = volume.boundingSphere.center

        // MPR: criar mas não configurar ainda
        let plane = SCNPlane(width: 1, height: 1)
        let mpr = MPRPlaneMaterial(device: device)
        // NÃO chamar setPart aqui - deixar para quando houver dados reais
        
        let node = SCNNode(geometry: plane)
        node.geometry?.materials = [mpr]
        node.isHidden = true
        volume.addChildNode(node)
        self.mprNode = node
        self.mprMat = mpr
    }
    
    func setMethod(method: VolumeCubeMaterial.Method) {
        mat.setMethod(method: method)
    }
    
    func setPart(part: VolumeCubeMaterial.BodyPart) {
        mat.setPart(device: device, part: part)
        volume.scale = SCNVector3(mat.scale)
        mat.setShift(device: device, shift: 0)

        // Só configurar MPR se tivermos dados reais
        if part != .none {
            mprMat?.setPart(device: device, part: part)
            if let tf = mat.tf {
                if let tfTexture = tf.get(device: device) {
                    mprMat?.setTransferFunction(tfTexture)
                }
            }
            if let dim = mprMat?.dimension {
                let mid = Int(dim.z / 2)
                mprMat?.setAxial(slice: mid)
                mprMat?.setSlab(thicknessInVoxels: 0, axis: 2, steps: 1)
            }
        }

        setRenderMode(activeRenderMode)
    }
    
    func setPreset(preset: VolumeCubeMaterial.Preset) {
        mat.setPreset(device: device, preset: preset)
        mat.setShift(device: device, shift: 0)
        if let tf = mat.tf {
            if let tfTexture = tf.get(device: device) {
                mprMat?.setTransferFunction(tfTexture)
            }
        }
    }
    
    func setLighting(isOn: Bool) {
        mat.setLighting(on: isOn)
    }
    
    func setStep(step: Float) {
        lastStep = step
        mat.setStep(step: step)
    }
    
    func setShift(shift: Float) {
        mat.setShift(device: device, shift: shift)
        if let tf = mat.tf {
            if let tfTexture = tf.get(device: device) {
                mprMat?.setTransferFunction(tfTexture)
            }
        }
    }

    // MARK: - Render mode (VR vs MPR)
    func setRenderMode(_ mode: RenderMode) {
        // Validação crítica: impedir MPR sem dados
        if mode == .mpr {
            // Verificar se temos dados carregados
            if mat.textureGenerator == nil || mat.textureGenerator.part == .none {
                print("⚠️ MPR requer dados carregados. Selecione 'chest' ou 'head' primeiro.")
                return  // Não mudar para MPR
            }
        }
        activeRenderMode = mode
    
        // Validação: não permitir MPR se não houver dados
        if mode == .mpr && mat.textureGenerator.part == .none {
            print("⚠️ MPR não disponível sem dados carregados")
            return
        }
        
        let isMprActive = (mode == .mpr)
        
        mat.cullMode = isMprActive ? .back : .front
        volume.isHidden = isMprActive      // ✅ esconde DVR quando MPR
        mprNode?.isHidden = !isMprActive   // ✅ mostra o plano MPR
        
        // Garantir que o material está configurado
        if volume.geometry?.materials.isEmpty ?? true {
            volume.geometry?.materials = [mat]
        }
        
        // cullMode só importa pro volume (VR), não pro MPR
        if !isMprActive {
            mat.cullMode = .front
            mat.setMethod(method: mapToVRMethod(mode))
        }
    }

    private func mapToVRMethod(_ mode: RenderMode) -> VolumeCubeMaterial.Method {
        switch mode {
        case .surf:  return .surf
        case .dvr:   return .dvr
        case .mip:   return .mip
        case .minip: return .minip
        case .avg:   return .avg
        case .mpr:   return .dvr // não usado; apenas para satisfazer retorno
        }
    }

     // =========================
    // MARK: - MPR Controls MVP
    // =========================
    func enableMPR(_ on: Bool) {
        mprNode?.isHidden = !on
        // Opcional: quando MPR ligar, podemos desligar o volume para não "brigar".
        // volume.isHidden = on
    }

    func setMPRBlend(_ mode: MPRPlaneMaterial.BlendMode) {
        mprMat?.setBlend(mode)
    }

    func setMPRHuWindow(min: Int32, max: Int32) {
        mprMat?.setHU(min: min, max: max)
    }

    func setMPRSlab(thicknessInVoxels: Int, steps: Int) {
        // Usa eixo normal dependendo do plano "vigente".
        // Aqui, adotamos o último "setAxial/Sagittal/Coronal" chamado para escolher eixo.
        // Para simplificar: axial=2, sagital=0, coronal=1. (Poderia haver um estado interno.)
        // Exemplo: considere axial por padrão:
        mprMat?.setSlab(thicknessInVoxels: thicknessInVoxels, axis: 2, steps: steps)
    }

    func setMPRPlaneAxial(slice k: Int) {
        mprMat?.setAxial(slice: k)
        // Ajuste o eixo normal do slab para Z (axis=2) ao mexer nos parâmetros
    }

    func setMPRPlaneSagittal(column i: Int) {
        mprMat?.setSagittal(column: i)
        // Se desejar, ao mudar o plano, também troque o eixo do slab para X (axis=0)
    }

    func setMPRPlaneCoronal(row j: Int) {
        mprMat?.setCoronal(row: j)
        // Eixo do slab para Y (axis=1) se quiser controlar via UI
    }

    func setDensityGate(floor: Float, ceil: Float) {
        mat.setDensityGate(floor: floor, ceil: ceil)
    }
    func setUseTFOnProjections(_ on: Bool) {
        mat.setUseTFOnProjections(on)
    }
    func setHuGate(enabled: Bool) { mat.setHuGate(enabled: enabled) }
    func setHuWindow(minHU: Int32, maxHU: Int32) { mat.setHuWindow(minHU: minHU, maxHU: maxHU) }

    func setMPRUseTF(_ on: Bool) { mprMat?.setUseTF(on) }
    func setAdaptive(_ on: Bool) { adaptiveOn = on }

    // --- Adaptive: reduzir steps enquanto interage ---
    @objc func handlePan(_ g: UIPanGestureRecognizer) {
        switch g.state {
        case .began:
            if adaptiveOn { mat.setStep(step: max(64, lastStep * interactionFactor)) }
        case .ended, .cancelled, .failed:
            if adaptiveOn { mat.setStep(step: lastStep) }
        default: break
        }
    }
    @objc func handlePinch(_ g: UIPinchGestureRecognizer) {
        switch g.state {
        case .began:
            if adaptiveOn { mat.setStep(step: max(64, lastStep * interactionFactor)) }
        case .ended, .cancelled, .failed:
            if adaptiveOn { mat.setStep(step: lastStep) }
        default: break
        }
    }
    @objc func handleRotate(_ g: UIRotationGestureRecognizer) {
        switch g.state {
        case .began:
            if adaptiveOn { mat.setStep(step: max(64, lastStep * interactionFactor)) }
        case .ended, .cancelled, .failed:
            if adaptiveOn { mat.setStep(step: lastStep) }
        default: break
        }
    }

    func setMPROblique(using geom: DICOMGeometry,
                    originMm: simd_float3,
                    axisUMm: simd_float3,
                    axisVMm: simd_float3)
    {
        let (o,u,v) = geom.planeWorldToTex(originW: originMm, axisUW: axisUMm, axisVW: axisVMm)
        mprMat?.setOblique(origin: float3(o), axisU: float3(u), axisV: float3(v))
        if let node = mprNode {
            node.setTransformFromBasisTex(originTex: o, UTex: u, VTex: v)
            node.isHidden = false
        }
    }

    func updateAxialSlice(normalizedValue: Float) {
        guard let dim = mprMat?.dimension else { return }
        let sliceCount = Float(max(1, dim.z - 1))
        let sliceIndex = Int(round(normalizedValue * sliceCount))
        setMPRPlaneAxial(slice: sliceIndex)
    }
}
