//
//  MPRPlaneMaterial.swift
//  Isis DICOM Viewer
//
//  MVP MPR Material (SceneKit + SCNProgram + Metal)
//  - Renderiza um plano de reamostragem dentro do volume (dicom 3D).
//  - Suporta MPR fino e thick slab com MIP/MinIP/Mean.
//  - Normalização HU -> [0,1] via min/max (mesma ideia do VR).
//  Thales Matheus Mendonça Santos - September 2025
//

import SceneKit
import simd

final class MPRPlaneMaterial: SCNMaterial {

    enum BlendMode: Int32, CaseIterable {
        case single = 0, mip = 1, minip = 2, mean = 3
    }

    struct Uniforms: sizeable {
        // Atenção à ordem/alinhamento (pad para 16 bytes p/ float3).
        var voxelMinValue: Int32 = -1024
        var voxelMaxValue: Int32 =  3071
        var blendMode: Int32 = BlendMode.single.rawValue
        var numSteps: Int32  = 1            // 1 => MPR fino; >1 => slab com agregação
        var slabHalf: Float  = 0            // espessura/2 em coords normalizadas [0,1]
        var _pad0: float3    = .zero

        var planeOrigin: float3 = .zero     // origem (canto inferior-esq) do plano em [0,1]^3
        var _pad1: Float = 0
        var planeX: float3 = float3(1,0,0)  // eixo u do plano (tamanho = largura em [0,1])
        var _pad2: Float = 0
        var planeY: float3 = float3(0,1,0)  // eixo v do plano (tamanho = altura em [0,1])
        var _pad3: Float = 0

        // Opção: aplicar TF 1D ao valor do slab/fino
        var useTFMpr: Int32 = 1
        var _pad4: Int32 = 0
        var _pad5: Int32 = 0
        var _pad6: Int32 = 0
    }

    // MARK: - Estado
    private var uniforms = Uniforms()
    private let uniformsKey = "U"   // bate com [[ buffer(4) ]] no shader
    private let volumeKey = "volume" // [[ texture(0) ]]
    private let tfKey       = "transferColor" // bate com [[ texture(3) ]]

    // Mantemos dimensão/resolução para conveniências (slice index -> coord normalizada).
    private(set) var dimension: int3 = int3(1,1,1)
    private(set) var resolution: float3 = float3(1,1,1)
    private var textureFactory: VolumeTextureFactory = VolumeTextureFactory(part: .none)

    /// Define dims e spacing diretamente (caminho MPR-only).
    func setDataset(dimension: int3, resolution: float3) {
        self.dimension = dimension
        self.resolution = resolution
    }

    // MARK: - Init
    init(device: MTLDevice) {
        super.init()
        let program = SCNProgram()
        program.vertexFunctionName   = "mpr_vertex"
        program.fragmentFunctionName = "mpr_fragment"
        self.program = program

        // Material flags: queremos visualizar o plano mesmo dentro do cubo
        isDoubleSided = true
        writesToDepthBuffer = false     // desenha por cima sem "brigar" com o volume
        readsFromDepthBuffer = false
        // SceneKit doesn't have .none; use .back and render both sides via isDoubleSided
        cullMode = .back

        // Uniform default
        setUniforms(uniforms)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    private func setVolumeTexture(_ texture: MTLTexture) {
        let prop = SCNMaterialProperty(contents: texture as Any)
        setValue(prop, forKey: volumeKey)
    }

    // MARK: - Binding helpers
    private func setUniforms(_ u: Uniforms) {
        var tmp = u
        // IMPORTANTE: usar stride por causa do alinhamento de float3 (16B) em Metal.
        let buffer = NSData(bytes: &tmp, length: Uniforms.stride)
        setValue(buffer, forKey: uniformsKey)
        print("Uniforms size=\(Uniforms.size) stride=\(Uniforms.stride)")
    }

    private func setTransferFunctionTexture(_ texture: MTLTexture) {
        setValue(SCNMaterialProperty(contents: texture), forKey: tfKey)
    }


    // MARK: - API pública (integração)
    /// Injeta a textura 3D do volume e captura dimension/resolution
    func setPart(device: MTLDevice, part: VolumeCubeMaterial.BodyPart) {
        apply(factory: VolumeTextureFactory(part: part), device: device)
    }

    func setDataset(device: MTLDevice, dataset: VolumeDataset) {
        apply(factory: VolumeTextureFactory(dataset: dataset), device: device)
    }

    func setHU(min: Int32, max: Int32) {
        uniforms.voxelMinValue = min
        uniforms.voxelMaxValue = max
        setUniforms(uniforms)
    }

    func setBlend(_ mode: BlendMode) {
        uniforms.blendMode = mode.rawValue
        setUniforms(uniforms)
    }

    /// Define espessura (slab) em número de amostras ao longo da normal.
    /// - Parameters:
    ///   - thicknessInVoxels: espessura total em voxels ao longo do eixo normal
    ///   - axis: 0=x, 1=y, 2=z (apenas para converter voxels->[0,1])
    ///   - steps: nº total de amostras dentro do slab (>= 1; 1 => fino)
    func setSlab(thicknessInVoxels: Int, axis: Int, steps: Int) {
        let denom: Float
        switch axis {
        case 0: denom = max(1, Float(dimension.x))
        case 1: denom = max(1, Float(dimension.y))
        default: denom = max(1, Float(dimension.z))
        }
        uniforms.slabHalf = 0.5 * Float(thicknessInVoxels) / denom
        uniforms.numSteps = Int32(max(1, steps))
        setUniforms(uniforms)
    }

    // MARK: - Planos canônicos (assume volume alinhado aos eixos – como no demo)
    /// k em [0 .. dimZ-1]
    func setAxial(slice k: Int) {
        let kz = max(0, min(Int(dimension.z)-1, k))
        // Centro do voxel: +0.5/dim para evitar "entre fatias"
        let z = (Float(kz) + 0.5) / max(1, Float(dimension.z))
        uniforms.planeOrigin = float3(0, 0, z)
        uniforms.planeX = float3(1, 0, 0)
        uniforms.planeY = float3(0, 1, 0)
        setUniforms(uniforms)
    }

    /// i em [0 .. dimX-1]
    func setSagittal(column i: Int) {
        let ix = max(0, min(Int(dimension.x)-1, i))
        let x = (Float(ix) + 0.5) / max(1, Float(dimension.x))
        uniforms.planeOrigin = float3(x, 0, 0)
        uniforms.planeX = float3(0, 1, 0) // varre Y
        uniforms.planeY = float3(0, 0, 1) // varre Z
        setUniforms(uniforms)
    }

    /// j em [0 .. dimY-1]
    func setCoronal(row j: Int) {
        let jy = max(0, min(Int(dimension.y)-1, j))
        let y = (Float(jy) + 0.5) / max(1, Float(dimension.y))
        uniforms.planeOrigin = float3(0, y, 0)
        uniforms.planeX = float3(1, 0, 0) // varre X
        uniforms.planeY = float3(0, 0, 1) // varre Z
        setUniforms(uniforms)
    }

    // MARK: - Planos oblíquos (futuro)
    /// Define plano arbitrário (origem + eixos, tudo em [0,1]³).
    func setOblique(origin: float3, axisU: float3, axisV: float3) {
        uniforms.planeOrigin = origin
        uniforms.planeX = axisU
        uniforms.planeY = axisV
        setUniforms(uniforms)
    }

    // MARK: - TF controls
    func setUseTF(_ on: Bool) {
        uniforms.useTFMpr = on ? 1 : 0
        setUniforms(uniforms)
    }

    func setTransferFunction(_ texture: MTLTexture) {
        setTransferFunctionTexture(texture)
    }
}

private extension MPRPlaneMaterial {
    func apply(factory: VolumeTextureFactory, device: MTLDevice) {
        textureFactory = factory
        guard let texture = factory.generate(device: device) else {
            print("🚨 ERRO: Falha ao gerar textura 3D para MPR.")
            return
        }

        dimension = factory.dimension
        resolution = factory.resolution

        let range = factory.dataset.intensityRange
        uniforms.voxelMinValue = range.lowerBound
        uniforms.voxelMaxValue = range.upperBound
        setUniforms(uniforms)

        setVolumeTexture(texture)
    }
}
