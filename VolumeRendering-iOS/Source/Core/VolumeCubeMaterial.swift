import SceneKit
import SwiftUI

/// SceneKit material que hosteia o shader Metal de volume (SR/DVR/MIP/MinIP/AIP).
final class VolumeCubeMaterial: SCNMaterial {

    // MARK: - Enums

    enum Preset: String, CaseIterable, Identifiable {
        var id: RawValue { rawValue }
        case ct_arteries, ct_entire, ct_lung
    }

    /// Métodos de renderização. Os IDs precisam casar com o `switch` do shader.
    enum Method: String, CaseIterable, Identifiable {
        var id: RawValue { rawValue }
        var idInt32: Int32 {
            switch self {
            case .surf:  return 0
            case .dvr:   return 1
            case .mip:   return 2
            case .minip: return 3
            case .avg:   return 4
            }
        }
        case surf, dvr, mip, minip, avg
    }

    enum BodyPart: String, CaseIterable, Identifiable {
        var id: RawValue { rawValue }
        case none, chest, head
    }

    // MARK: - Uniforms (deve casar com struct Uniforms em volumerendering.metal)

    struct Uniforms: sizeable {
        // Mantendo Bool aqui (funciona bem em iOS). Se algum device reclamar de alinhamento,
        // troque para Int32 e adapte o .metal.
        var isLightingOn: Bool = true
        var isBackwardOn: Bool = false

        var method: Int32 = Method.dvr.idInt32
        var renderingQuality: Int32 = 512

        // HU window normalização [min..max]
        var voxelMinValue: Int32 = -1024
        var voxelMaxValue: Int32 =  3071

        // --- NOVOS CAMPOS ---
        // Gating para projeções (MIP/MinIP/AIP), em [0,1] após normalização HU.
        var densityFloor: Float = 0.02
        var densityCeil:  Float = 1.00

        // Dimensão real do volume (passada ao shader p/ gradiente correto)
        var dimX: Int32 = 1
        var dimY: Int32 = 1
        var dimZ: Int32 = 1

        // Aplicar TF nas projeções?
        var useTFProj: Bool = false

        // Padding para múltiplos de 16B (evita surpresas de alinhamento)
        var _pad0: Int32 = 0
        var _pad1: Int32 = 0
        var _pad2: Int32 = 0
    }

    // MARK: - Estado

    private var uniforms = Uniforms()
    private let uniformsKey    = "uniforms"       // [[ buffer(4) ]]
    private let dicomKey       = "dicom"          // [[ texture(0) ]]
    private let tfKey          = "transferColor"  // [[ texture(3) ]]

    var textureGenerator: VolumeTextureFactory!
    var tf: TransferFunction?

    /// Escala do cubo (SceneKit) = voxel spacing * dimensão (mantém proporção anatômica)
    var scale: float3 { textureGenerator.scale }

    // MARK: - Init

    init(device: MTLDevice) {
        super.init()

        let program = SCNProgram()
        program.vertexFunctionName   = "volume_vertex"
        program.fragmentFunctionName = "volume_fragment"
        self.program = program

        // Inicializa sem dados até que o caller selecione a série
        setPart(device: device, part: .none)

        // TF default (pode trocar em runtime)
        setPreset(device: device, preset: .ct_arteries)
        setShift(device: device, shift: 0)

        // Empurra uniforms iniciais
        pushUniforms()

        // Flags de material
        cullMode = .front
        writesToDepthBuffer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Helpers

    private func pushUniforms() {
        var u = uniforms
        let buffer = NSData(bytes: &u, length: Uniforms.size)
        setValue(buffer, forKey: uniformsKey)
    }

    private func setDicomTexture(_ texture: MTLTexture) {
        let prop = SCNMaterialProperty(contents: texture as Any)
        setValue(prop, forKey: dicomKey)
    }

    private func setTransferFunctionTexture(_ texture: MTLTexture) {
        let prop = SCNMaterialProperty(contents: texture as Any)
        setValue(prop, forKey: tfKey)
    }

    // MARK: - API de controle

    func setMethod(method: Method) {
        uniforms.method = method.idInt32
        pushUniforms()
    }

    /// Injeta o volume e atualiza dimX/Y/Z (para gradiente correto no shader).
    func setPart(device: MTLDevice, part: BodyPart) {
        textureGenerator = VolumeTextureFactory(part)
        let volumeTex = textureGenerator.generate(device: device)
        setDicomTexture(volumeTex)

        // Dimensões reais para o cálculo de gradiente no shader
        uniforms.dimX = textureGenerator.dimension.x
        uniforms.dimY = textureGenerator.dimension.y
        uniforms.dimZ = textureGenerator.dimension.z
        pushUniforms()
    }

    func setPreset(device: MTLDevice, preset: Preset) {
        let url = Bundle.main.url(forResource: preset.rawValue, withExtension: "tf")!
        tf = TransferFunction.load(from: url)
    }

    func setLighting(on: Bool) {
        uniforms.isLightingOn = on
        pushUniforms()
    }

    func setStep(step: Float) {
        uniforms.renderingQuality = Int32(step)
        pushUniforms()
    }

    /// Desloca a TF (útil para presets que varrem faixas HU)
    func setShift(device: MTLDevice, shift: Float) {
        tf?.shift = shift
        guard let tf = tf else { return }
        let tfTexture = tf.get(device: device)
        setTransferFunctionTexture(tfTexture)
    }

    /// Gating para MIP/MinIP/AIP em [0,1] (após normalização HU).
    func setDensityGate(floor: Float, ceil: Float) {
        uniforms.densityFloor = max(0, min(1, floor))
        uniforms.densityCeil  = max(uniforms.densityFloor, min(1, ceil))
        pushUniforms()
    }

    /// Aplica TF nas projeções (em vez de grayscale).
    func setUseTFOnProjections(_ on: Bool) {
        uniforms.useTFProj = on
        pushUniforms()
    }
}
