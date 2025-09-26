//  TriPlanarMPR.swift
//  Isis DICOM Viewer
//
//  Tri‑Planar MPR com linhas ortogonais arrastáveis e rotação oblíqua
//  - 3 viewports 2D (axial, coronal, sagital) com SCNView ortográfico
//  - Reutiliza a textura 3D e a TF já carregadas pelo VR
//  - Linhas centrais arrastáveis movem os planos; rotação 2‑toques gira a triade
//
//  Thales Matheus Mendonça Santos - September 2025

import SwiftUI
import SceneKit
import simd

// MARK: - Enum de planos
enum TriPlane: CaseIterable {
    case axial, coronal, sagittal
    var title: String {
        switch self {
        case .axial: return "Axial"
        case .coronal: return "Coronal"
        case .sagittal: return "Sagittal"
        }
    }
}

// MARK: - Estado compartilhado (triade ortonormal + ponto de interseção)
final class TriMPRState: ObservableObject {
    // Base {x',y',z'} (colunas) em coords normalizadas do volume [0,1]^3
    @Published var R: simd_float3x3 = matrix_identity_float3x3
    // Ponto de interseção (crosshair) em [0,1]^3
    @Published var cross: SIMD3<Float> = SIMD3(0.5, 0.5, 0.5)

    // clamps
    private let eps: Float = 1e-5

    // Accessor for matrix column by index (since `columns` is a tuple, not subscriptable)
    private func baseColumn(_ i: Int) -> SIMD3<Float> {
        switch i {
        case 0: return R.columns.0
        case 1: return R.columns.1
        default: return R.columns.2
        }
    }

    // Rotação incremental ao redor de um eixo da própria base (0=x', 1=y', 2=z').
    func rotate(aroundBaseAxis i: Int, deltaRadians: Float) {
        let axis = normalize(baseColumn(i))
        let c = cos(deltaRadians), s = sin(deltaRadians)
        let C = 1 - c
        let x = axis.x, y = axis.y, z = axis.z
        let rot = simd_float3x3(
            SIMD3<Float>( c + x*x*C,     x*y*C - z*s,  x*z*C + y*s),
            SIMD3<Float>( y*x*C + z*s,   c + y*y*C,    y*z*C - x*s),
            SIMD3<Float>( z*x*C - y*s,   z*y*C + x*s,  c + z*z*C)
        )
        R = rot * R
    }

    // Tradução do cross ao longo de um eixo da base (0=x',1=y',2=z')
    func translate(alongBaseAxis i: Int, deltaNormalized: Float) {
        cross = simd_clamp(cross + deltaNormalized * baseColumn(i),
                           SIMD3<Float>(repeating: 0 + eps),
                           SIMD3<Float>(repeating: 1 - eps))
    }
}

// MARK: - Um viewport (SCNView) para um plano
final class MPRViewportController: NSObject {
    let planeKind: TriPlane
    private let scnView = SCNView()
    private let scene = SCNScene()
    private let cameraNode = SCNNode()
    private let node = SCNNode(geometry: SCNPlane(width: 1, height: 1))
    private let matMPR: MPRPlaneMaterial
    private var device: MTLDevice

    init?(plane: TriPlane, device: MTLDevice) {
        self.planeKind = plane
        guard let dev = device as MTLDevice? else { return nil }
        self.device = dev
        self.matMPR = MPRPlaneMaterial(device: dev)
        super.init()
        setupView()
    }

    var view: SCNView { scnView }

    private func setupView() {
        scnView.scene = scene
        scnView.backgroundColor = .black
        scnView.allowsCameraControl = false
        scnView.autoenablesDefaultLighting = true

        // Câmera ortográfica 2D
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.usesOrthographicProjection = true
        cameraNode.camera?.orthographicScale = 1.0      // plano 1×1 em tela
        cameraNode.position = SCNVector3(0, 0, 2)
        cameraNode.camera?.zNear = 0.001
        cameraNode.camera?.zFar  = 10
        scene.rootNode.addChildNode(cameraNode)

        node.geometry?.firstMaterial = matMPR
        node.eulerAngles = SCNVector3Zero
        node.position = SCNVector3Zero
        scene.rootNode.addChildNode(node)
    }

    // Injeta dataset (textura 3D, TF, meta)
    func setDataset(volumeTex: MTLTexture, tfTex: MTLTexture?, dimension: int3, resolution: float3) {
        matMPR.setValue(SCNMaterialProperty(contents: volumeTex), forKey: "volume")
        if let tf = tfTex { matMPR.setTransferFunction(tf) }
        matMPR.setDataset(dimension: dimension, resolution: resolution)
        // MPR fino por padrão
        matMPR.setSlab(thicknessInVoxels: 0, axis: 2, steps: 1)
    }

    // Aplica obliquidade e posição do plano a partir de base R e cross
    func apply(R: simd_float3x3, cross: SIMD3<Float>) {
        // Triade {x',y',z'} (colunas)
        let xp = R.columns.0
        let yp = R.columns.1
        let zp = R.columns.2

        // u/v por plano
        let (u, v): (SIMD3<Float>, SIMD3<Float>)
        switch planeKind {
        case .axial:    (u, v) = (xp, yp)   // normal = z'
        case .coronal:  (u, v) = (xp, zp)   // normal = y'
        case .sagittal: (u, v) = (yp, zp)   // normal = x'
        }

        // origem no canto inferior‑esquerdo, centrando cross (u=v=0.5)
        let origin = cross - 0.5 * (u + v)
        matMPR.setOblique(origin: float3(origin), axisU: float3(u), axisV: float3(v))
        // A geometria é sempre 1×1; não precisa girar o node: o shader resolve a amostra 3D
    }
}

// MARK: - Representable para SwiftUI
struct MPRViewportView: UIViewRepresentable {
    typealias UIViewType = SCNView

    let controller: MPRViewportController

    func makeUIView(context: Context) -> SCNView { controller.view }
    func updateUIView(_ uiView: SCNView, context: Context) {}
}

// MARK: - Overlay com linhas/gestos
struct CrosshairOverlay: View {
    // callbacks
    let onDragVertical: (CGFloat, CGSize) -> Void   // (width, translation)
    let onDragHorizontal: (CGFloat, CGSize) -> Void // (height, translation)
    let onRotate: (CGFloat) -> Void                 // delta em radianos

    // estados internos do gesto de rotação
    @State private var lastAngle: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Linha vertical (controla x')
                Path { p in
                    p.move(to: CGPoint(x: w/2, y: 0))
                    p.addLine(to: CGPoint(x: w/2, y: h))
                }
                .stroke(.yellow, lineWidth: 2)
                // área de toque mais larga
                Rectangle()
                    .fill(.clear)
                    .frame(width: 44, height: h)
                    .position(x: w/2, y: h/2)
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in onDragVertical(w, value.translation) })

                // Linha horizontal (controla y' ou z', conforme plano)
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h/2))
                    p.addLine(to: CGPoint(x: w, y: h/2))
                }
                .stroke(.purple, lineWidth: 2)
                Rectangle()
                    .fill(.clear)
                    .frame(width: w, height: 44)
                    .position(x: w/2, y: h/2)
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in onDragHorizontal(h, value.translation) })

                // “alça” central + gesto de rotação de 2 dedos
                Circle()
                    .stroke(.white.opacity(0.9), lineWidth: 2)
                    .frame(width: 22, height: 22)
                    .position(x: w/2, y: h/2)
            }
            // rotação oblíqua (2 dedos)
            .gesture(RotationGesture()
                .onChanged { value in
                    let delta = value.radians - lastAngle
                    lastAngle = value.radians
                    onRotate(delta)
                }
                .onEnded { _ in lastAngle = 0 })
        }
    }
}

// MARK: - Painel Tri‑Planar (3 viewports)
struct TriPlanarMPRView: View {
    @StateObject private var state = TriMPRState()

    private let axialVC: MPRViewportController
    private let coronalVC: MPRViewportController
    private let sagittalVC: MPRViewportController

    init?() {
        // Reutiliza device/volume/TF do controller principal
        guard let device = SceneViewController.Instance.device else { return nil }
        guard let ax = MPRViewportController(plane: .axial, device: device),
              let co = MPRViewportController(plane: .coronal, device: device),
              let sa = MPRViewportController(plane: .sagittal, device: device)
        else { return nil }
        self.axialVC = ax; self.coronalVC = co; self.sagittalVC = sa

        // Dataset atual
        if let vol = SceneViewController.Instance.currentVolumeTexture(),
           let meta = SceneViewController.Instance.currentDatasetMeta() {
            let tf = SceneViewController.Instance.currentTFTexture()
            [axialVC, coronalVC, sagittalVC].forEach {
                $0.setDataset(volumeTex: vol, tfTex: tf,
                              dimension: meta.dimension, resolution: meta.resolution)
            }
            // aplica estado inicial (R=I, cross=centro)
            [axialVC, coronalVC, sagittalVC].forEach { $0.apply(R: matrix_identity_float3x3, cross: SIMD3(0.5,0.5,0.5)) }
        }
    }

    // Aplica R/cross em todos
    private func syncAll() {
        [axialVC, coronalVC, sagittalVC].forEach { $0.apply(R: state.R, cross: state.cross) }
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 6) {
                // Topo: Axial (ocupando largura toda)
                ZStack {
                    MPRViewportView(controller: axialVC).background(Color.black)
                    CrosshairOverlay(
                        onDragVertical: { width, t in
                            // mover x' (eixo da linha vertical) — usa deltaX/width
                            state.translate(alongBaseAxis: 0, deltaNormalized: Float(t.width / width))
                            syncAll()
                        },
                        onDragHorizontal: { height, t in
                            // mover y' — usa -deltaY/height (origem UI no topo)
                            state.translate(alongBaseAxis: 1, deltaNormalized: Float(-t.height / height))
                            syncAll()
                        },
                        onRotate: { deltaRad in
                            // girar ao redor de z' (normal do axial)
                            state.rotate(aroundBaseAxis: 2, deltaRadians: Float(deltaRad))
                            syncAll()
                        }
                    )
                    .allowsHitTesting(true)
                }
                .frame(height: geo.size.height * 0.5)

                // Base: dois viewports lado a lado (Coronal e Sagital)
                HStack(spacing: 6) {
                    ZStack {
                        MPRViewportView(controller: coronalVC).background(Color.black)
                        CrosshairOverlay(
                            onDragVertical: { width, t in
                                // mover x'
                                state.translate(alongBaseAxis: 0, deltaNormalized: Float(t.width / width))
                                syncAll()
                            },
                            onDragHorizontal: { height, t in
                                // mover z'
                                state.translate(alongBaseAxis: 2, deltaNormalized: Float(-t.height / height))
                                syncAll()
                            },
                            onRotate: { deltaRad in
                                // girar ao redor de y' (normal do coronal)
                                state.rotate(aroundBaseAxis: 1, deltaRadians: Float(deltaRad))
                                syncAll()
                            }
                        )
                    }
                    ZStack {
                        MPRViewportView(controller: sagittalVC).background(Color.black)
                        CrosshairOverlay(
                            onDragVertical: { width, t in
                                // mover y'
                                state.translate(alongBaseAxis: 1, deltaNormalized: Float(t.width / width))
                                syncAll()
                            },
                            onDragHorizontal: { height, t in
                                // mover z'
                                state.translate(alongBaseAxis: 2, deltaNormalized: Float(-t.height / height))
                                syncAll()
                            },
                            onRotate: { deltaRad in
                                // girar ao redor de x' (normal do sagital)
                                state.rotate(aroundBaseAxis: 0, deltaRadians: Float(deltaRad))
                                syncAll()
                            }
                        )
                    }
                }
                .frame(height: geo.size.height * 0.5)
            }
            .onAppear { syncAll() }
        }
    }
}
