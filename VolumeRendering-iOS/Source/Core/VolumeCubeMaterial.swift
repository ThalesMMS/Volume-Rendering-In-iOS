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
        case none, chest, head, dicom

        var id: RawValue { rawValue }

        var displayName: String {
            switch self {
            case .none:
                return "none"
            case .dicom:
                return "DICOM"
            default:
                return rawValue
            }
        }
    }

    // MARK: - Uniforms (deve casar com struct Uniforms em volumerendering.metal)

    struct Uniforms: sizeable {
        // Flags como Int32 para alinhamento/portabilidade Swift/MSL
        var isLightingOn: Int32 = 1
        var isBackwardOn: Int32 = 0

        var method: Int32 = Method.dvr.idInt32
        var renderingQuality: Int32 = 512

        // HU window normalização [min..max]
        var voxelMinValue: Int32 = -1024
        var voxelMaxValue: Int32 =  3071

        // Gating para projeções (MIP/MinIP/AIP)
        var densityFloor: Float = 0.02
        var densityCeil:  Float = 1.00

        // Gating por HU nativo (quando habilitado)
        var gateHuMin: Int32 = -900
        var gateHuMax: Int32 = -500
        var useHuGate: Int32 = 0

        // Dimensão real do volume (passada ao shader p/ gradiente correto)
        var dimX: Int32 = 1
        var dimY: Int32 = 1
        var dimZ: Int32 = 1

        // Aplicar TF nas projeções?
        var useTFProj: Int32 = 0

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

    private(set) var textureGenerator: VolumeTextureFactory = VolumeTextureFactory(part: .none)
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

        // Flags de material primeiro
        cullMode = .front
        writesToDepthBuffer = true

        // Inicializa sem dados
        setPart(device: device, part: .none)

        // TF default com verificação - REMOVER este bloco problemático
        // if Bundle.main.url(forResource: "ct_arteries", withExtension: "tf") != nil {
        //     setPreset(device: device, preset: .ct_arteries)
        //     setShift(device: device, shift: 0)
        // }

        // Empurra uniforms iniciais
        pushUniforms()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Helpers

    private func pushUniforms() {
        var u = uniforms
        // stride garante padding correto para Metal
        let buffer = NSData(bytes: &u, length: Uniforms.stride)
        setValue(buffer, forKey: uniformsKey)
    }

    private func setDicomTexture(_ texture: MTLTexture) {
        let prop = SCNMaterialProperty(contents: texture as Any)
        setValue(prop, forKey: dicomKey)
    }

    func setTransferFunctionTexture(_ texture: MTLTexture) {
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
        apply(factory: VolumeTextureFactory(part: part), device: device)
    }

    func setDataset(device: MTLDevice, dataset: VolumeDataset) {
        apply(factory: VolumeTextureFactory(dataset: dataset), device: device)
    }

    func setPreset(device: MTLDevice, preset: Preset) {
        print("🔍 Tentando carregar preset: \(preset.rawValue)")

        guard let url = Bundle.main.url(forResource: preset.rawValue, withExtension: "tf") else {
            print("🚨 ERRO: Arquivo não encontrado: \(preset.rawValue).tf")
            print("🔍 Recursos disponíveis no bundle:")
            print("🚨 ERRO: Não foi possível encontrar o recurso \(preset.rawValue).tf")
            if let urls = Bundle.main.urls(forResourcesWithExtension: "tf", subdirectory: nil) {
                urls.forEach { print("  - \($0.lastPathComponent)") }
            }
            return
        }

        print("✅ Arquivo encontrado: \(url.path)")
        tf = TransferFunction.load(from: url)
    }

    func setLighting(on: Bool) {
        uniforms.isLightingOn = on ? 1 : 0
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
        if let tfTexture = tf.get(device: device) { // Unwrapping seguro
            setTransferFunctionTexture(tfTexture)
        }
    }

    /// Gating para MIP/MinIP/AIP em [0,1] (após normalização HU).
    func setDensityGate(floor: Float, ceil: Float) {
        uniforms.densityFloor = max(0, min(1, floor))
        uniforms.densityCeil  = max(uniforms.densityFloor, min(1, ceil))
        pushUniforms()
    }

    /// Aplica TF nas projeções (em vez de grayscale).
    func setUseTFOnProjections(_ on: Bool) {
        uniforms.useTFProj = on ? 1 : 0
        pushUniforms()
    }

    // MARK: - HU Gate controls (projections)
    func setHuGate(enabled: Bool) {
        uniforms.useHuGate = enabled ? 1 : 0
        pushUniforms()
    }

    func setHuWindow(minHU: Int32, maxHU: Int32) {
        uniforms.gateHuMin = minHU
        uniforms.gateHuMax = maxHU
        pushUniforms()
    }

}

private extension VolumeCubeMaterial {
    func apply(factory: VolumeTextureFactory, device: MTLDevice) {
        textureGenerator = factory
        guard let texture = factory.generate(device: device) else {
            print("🚨 ERRO: Falha ao gerar textura para o volume.")
            return
        }
        setDicomTexture(texture)

        #if DEBUG
        print("[VolumeCubeMaterial] dataset dim=\(factory.dimension) range=\(factory.dataset.intensityRange)")
        #endif

        let dimension = factory.dimension
        uniforms.dimX = dimension.x
        uniforms.dimY = dimension.y
        uniforms.dimZ = dimension.z

        let range = factory.dataset.intensityRange
        uniforms.voxelMinValue = range.lowerBound
        uniforms.voxelMaxValue = range.upperBound

        pushUniforms()
    }
}
