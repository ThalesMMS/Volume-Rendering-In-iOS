import MetalKit
import SceneKit
import SwiftUI

struct ContentView: View {
    var view = SCNView()
    
    @State var showOption = true
    @StateObject var model = DrawOptionModel()
    @State private var isInitialized = false
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            SceneView(scnView: view)
                .background(.gray)
                .onAppear(perform: {
                    if !isInitialized {
                        SceneViewController.Instance.onAppear(view)
                        isInitialized = true
                    }
                })
               
            HStack(alignment: .top) {
                Button(showOption ? "hide" : "show") {
                    showOption.toggle()
                }
                
                if showOption {
                    ScrollView(.vertical, showsIndicators: true) {
                        DrawOptionView(model: model)
                            .padding(.trailing, 8)
                    }
                    .frame(maxWidth: 420, maxHeight: 360, alignment: .topLeading)
                    .background(.clear)
                }
            }.padding(.vertical, 25)
        }
    }
}

class DrawOptionModel: ObservableObject {
    @Published var part = VolumeCubeMaterial.BodyPart.none
    @Published var method = SceneViewController.RenderMode.dvr
    @Published var preset = VolumeCubeMaterial.Preset.ct_arteries
    @Published var lightingOn: Bool = true
    @Published var step: Float = 512
    @Published var shift: Float = 0

    // NOVO:
    @Published var gateFloor: Float = 0.02
    @Published var gateCeil:  Float = 1.0
    @Published var useTFProj: Bool  = false
    @Published var adaptiveOn: Bool  = true

    // HU gate (projeções) e TF no MPR
    @Published var huGateOn: Bool = false
    @Published var huMinHU: Float = -900
    @Published var huMaxHU: Float = -500
    @Published var useTFMpr: Bool = true

    // MPR básico
    @Published var mprOn: Bool = false
    @Published var mprBlend: MPRPlaneMaterial.BlendMode = .single
    @Published var mprAxialSlice: Float = 0
    enum MPRPlane: String, CaseIterable { case axial, coronal, sagittal }
    @Published var mprPlane: MPRPlane = .axial
}

struct DrawOptionView: View {
    @ObservedObject var model: DrawOptionModel
    
    var body: some View {
        VStack (spacing: 10) {
            HStack {
                Picker("Choose a mode", selection: $model.method) {
                    ForEach(SceneViewController.RenderMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                .onChange(of: model.method) { SceneViewController.Instance.setRenderMode($0) }
                .foregroundColor(.orange)
                .onAppear() {
                    UISegmentedControl.appearance().selectedSegmentTintColor = .blue
                    UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
                    UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.blue], for: .normal)
                }
            }.frame(height: 30)
            
            HStack {
                Picker("Choose a Part", selection: $model.part) {
                    ForEach(VolumeCubeMaterial.BodyPart.allCases, id: \.self) { part in
                        Text(part.rawValue)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                .onChange(of: model.part) {
                    SceneViewController.Instance.setPart(part: $0)
                    model.shift = 0
                }
                .foregroundColor(.orange)
                .onAppear() {
                    UISegmentedControl.appearance().selectedSegmentTintColor = .blue
                    UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
                    UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.blue], for: .normal)
                }
            }.frame(height: 30)
            
            HStack {
                Picker("Choose a Preset", selection: $model.preset) {
                    ForEach(VolumeCubeMaterial.Preset.allCases, id: \.self) { part in
                        Text(part.rawValue)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                .onChange(of: model.preset) {
                    SceneViewController.Instance.setPreset(preset: $0)
                    model.shift = 0
                }
                .foregroundColor(.orange)
                .onAppear() {
                    UISegmentedControl.appearance().selectedSegmentTintColor = .blue
                    UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
                    UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.blue], for: .normal)
                }
            }.frame(height: 30)
            
            HStack {
                Toggle("Lighting On",
                       isOn: $model.lightingOn)
                .foregroundColor(.white)
                .onChange(of: model.lightingOn,
                          perform: SceneViewController.Instance.setLighting)
            }.frame(height: 30)
            
            HStack {
                Text("Step")
                    .foregroundColor(.white)
                
                Slider(value: $model.step, in: 128...512, step: 1)
                    .padding()
                    .onChange(of: model.step, perform: SceneViewController.Instance.setStep)
            }.frame(height: 30)
            
            HStack {
                Text("Shift")
                    .foregroundColor(.white)
                Slider(value: $model.shift, in: -100...100, step: 1)
                    .padding()
                    .onChange(of: model.shift, perform: SceneViewController.Instance.setShift)
            }.frame(height: 30)
            
            Spacer()

            HStack {
                Toggle("TF nas projeções (MIP/MinIP/AIP)", isOn: $model.useTFProj)
                    .onChange(of: model.useTFProj) { SceneViewController.Instance.setUseTFOnProjections($0) }
            }.frame(height: 30)

            HStack {
                Toggle("TF no MPR", isOn: $model.useTFMpr)
                    .onChange(of: model.useTFMpr) { SceneViewController.Instance.setMPRUseTF($0) }
            }.frame(height: 30)

            HStack {
                Picker("MPR Blend", selection: $model.mprBlend) {
                    ForEach(MPRPlaneMaterial.BlendMode.allCases, id: \.self) { mode in
                        let title: String = {
                            switch mode {
                            case .single: return "single"
                            case .mip:    return "mip"
                            case .minip:  return "minip"
                            case .mean:   return "avg"
                            }
                        }()
                        Text(title).tag(mode)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .onChange(of: model.mprBlend) { SceneViewController.Instance.setMPRBlend($0) }
            }.frame(height: 30)

            HStack {
                Toggle("Gate por HU (projeções)", isOn: $model.huGateOn)
                    .onChange(of: model.huGateOn) { SceneViewController.Instance.setHuGate(enabled: $0) }
            }.frame(height: 30)

            VStack {
                HStack {
                    Text("HU Min").foregroundColor(.white)
                    Slider(
                        value: Binding(get: { Double(model.huMinHU) }, set: { model.huMinHU = Float($0) }),
                        in: -1200...3000, step: 1
                    )
                        .padding()
                        .onChange(of: model.huMinHU) { _ in
                            SceneViewController.Instance.setHuWindow(minHU: Int32(model.huMinHU), maxHU: Int32(model.huMaxHU))
                        }
                }.frame(height: 30)

                HStack {
                    Text("HU Max").foregroundColor(.white)
                    Slider(
                        value: Binding(get: { Double(model.huMaxHU) }, set: { model.huMaxHU = Float($0) }),
                        in: -1200...3000, step: 1
                    )
                        .padding()
                        .onChange(of: model.huMaxHU) { _ in
                            SceneViewController.Instance.setHuWindow(minHU: Int32(model.huMinHU), maxHU: Int32(model.huMaxHU))
                        }
                }.frame(height: 30)
            }

            VStack {
                HStack {
                    Text("Gate Floor").foregroundColor(.white)
                    Slider(
                        value: Binding(get: { Double(model.gateFloor) }, set: { model.gateFloor = Float($0) }),
                        in: 0.0...1.0, step: 0.01
                    )
                        .padding()
                        .onChange(of: model.gateFloor) { _ in
                            SceneViewController.Instance.setDensityGate(floor: model.gateFloor, ceil: model.gateCeil)
                        }
                }.frame(height: 30)

                HStack {
                    Text("Gate Ceil").foregroundColor(.white)
                    Slider(
                        value: Binding(get: { Double(model.gateCeil) }, set: { model.gateCeil = Float($0) }),
                        in: 0.0...1.0, step: 0.01
                    )
                        .padding()
                        .onChange(of: model.gateCeil) { _ in
                            SceneViewController.Instance.setDensityGate(floor: model.gateFloor, ceil: model.gateCeil)
                        }
                }.frame(height: 30)
            }

            HStack {
                Toggle("Adaptive steps (durante interação)", isOn: $model.adaptiveOn)
                    .onChange(of: model.adaptiveOn) { SceneViewController.Instance.setAdaptive($0) }
            }.frame(height: 30)

            if model.method == .mpr {
                HStack {
                    Text("Axial Slice").foregroundColor(.white)

                    // Slider normalizado 0...1 (passa Double, converte para Float)
                    Slider(
                        value: Binding(
                            get: { Double(model.mprAxialSlice) },
                            set: { model.mprAxialSlice = Float($0) }
                        ),
                        in: 0.0...1.0,
                        step: {
                            // passo coerente: 1/(nFatias-1); fallback 0.01
                            let z = max(1, SceneViewController.Instance.mprDimZ)
                            return z > 1 ? 1.0 / Double(z - 1) : 0.01
                        }()
                    )
                    .padding()
                    .onChange(of: model.mprAxialSlice) { val in
                        SceneViewController.Instance.updateAxialSlice(normalizedValue: val)
                    }
                }
                .frame(height: 30)
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .previewInterfaceOrientation(.landscapeRight)
            .previewDevice("iPad Pro (11-inch) (3rd generation)")
    }
}

