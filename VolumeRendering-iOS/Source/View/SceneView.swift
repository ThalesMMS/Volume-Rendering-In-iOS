import MetalKit
import SceneKit
import SwiftUI

struct SceneView: UIViewRepresentable {
    typealias UIViewType = SCNView
    var scnView: SCNView
    
    func makeUIView(context: Context) -> SCNView {
        let scene = SCNScene()
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        scnView.showsStatistics = true
        scnView.backgroundColor = .clear
        scnView.clearsContextBeforeDrawing = true

        scnView.scene = scene

        // NOVO: gestures para adaptive steps
        let pan = UIPanGestureRecognizer(target: SceneViewController.Instance, action: #selector(SceneViewController.handlePan(_:)))
        let pinch = UIPinchGestureRecognizer(target: SceneViewController.Instance, action: #selector(SceneViewController.handlePinch(_:)))
        let rot = UIRotationGestureRecognizer(target: SceneViewController.Instance, action: #selector(SceneViewController.handleRotate(_:)))
        pan.cancelsTouchesInView = false
        pinch.cancelsTouchesInView = false
        rot.cancelsTouchesInView = false
        scnView.addGestureRecognizer(pan)
        scnView.addGestureRecognizer(pinch)
        scnView.addGestureRecognizer(rot)

        return scnView
    }

    
    func updateUIView(_ uiView: SCNView, context: Context) {}
}
