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
    
    var device: MTLDevice!
    var root: SCNNode!
    var cameraController: SCNCameraController!
    
    var volume: SCNNode!
    var mat: VolumeCubeMaterial!
    // --- MPR ---
    private var mprNode: SCNNode?
    private var mprMat: MPRPlaneMaterial?

    private var adaptiveOn: Bool = true
    private var lastStep: Float = 512
    private var interactionFactor: Float = 0.35 // 35% dos steps durante interação
    
    override public init() { super.init() }
    
    func onAppear(_ view: SCNView) {
        device = view.device!
        root = view.scene!.rootNode
        cameraController = view.defaultCameraController
        
        let box = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0)
        mat = VolumeCubeMaterial(device: device)
        mat.setPart(device: device, part: .none)
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

        // --- MPR: cria plano (inicialmente oculto) como filho do volume ---
        let plane = SCNPlane(width: 1, height: 1)
        let mpr = MPRPlaneMaterial(device: device)
        mpr.setPart(device: device, part: .none) // manter sync com "part"
        let node = SCNNode(geometry: plane)
        node.geometry?.materials = [mpr]
        node.isHidden = true
        // Importante: o plano herda a escala do pai (volume).
        volume.addChildNode(node)
        self.mprNode = node
        self.mprMat  = mpr
    }
    
    func setMethod(method: VolumeCubeMaterial.Method) {
        mat.setMethod(method: method)
    }
    
    func setPart(part: VolumeCubeMaterial.BodyPart) {
        mat.setPart(device: device, part: part)
        volume.geometry?.materials = [mat]
        mat.setShift(device: device, shift: 0)
        // Mantém MPR usando a mesma série de dados
        mprMat?.setPart(device: device, part: part)
        // Default: axial no meio
        if let dim = mprMat?.dimension {
            let mid = Int(dim.z / 2)
            mprMat?.setAxial(slice: mid)
            mprMat?.setSlab(thicknessInVoxels: 0, axis: 2, steps: 1) // fino
        }
    }
    
    func setPreset(preset: VolumeCubeMaterial.Preset) {
        mat.setPreset(device: device, preset: preset)
        mat.setShift(device: device, shift: 0)
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
    }
}
