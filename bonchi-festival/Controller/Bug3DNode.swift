//
//  Bug3DNode.swift
//  bonchi-festival
//
//  iOS Controller: SceneKit 3-D node that visually represents one AR bug.
//
//  Each BugType gets a distinct procedurally-built shape and colour palette:
//    • butterfly (Null Bug)   — cyan sphere with translucent wing planes
//    • beetle    (Virus Bug)  — red/magenta capsule with dark accent spots
//    • stag      (Glitch Bug) — gold box with four orange spike cones
//
//  All nodes hover vertically and rotate continuously.  Calling captured()
//  triggers a scale-up / fade-out dismissal animation.
//

import SceneKit
import UIKit

// MARK: - Bug3DNode

final class Bug3DNode: SCNNode {

    let bugType: BugType

    init(type: BugType) {
        self.bugType = type
        super.init()
        setupGeometry()
        startAnimations()
    }

    required init?(coder: NSCoder) { fatalError("Bug3DNode does not support NSCoding; use init(type:) instead") }

    // MARK: - Public

    /// Scale-up / fade-out animation played when the bug is captured.
    func captured() {
        removeAllActions()
        let grow   = SCNAction.scale(to: 2.2, duration: 0.18)
        let fade   = SCNAction.fadeOut(duration: 0.30)
        let remove = SCNAction.removeFromParentNode()
        grow.timingMode = .easeOut
        runAction(SCNAction.sequence([SCNAction.group([grow, fade]), remove]))
    }

    // MARK: - Private: geometry

    private func setupGeometry() {
        switch bugType {
        case .butterfly: setupButterfly()
        case .beetle:    setupBeetle()
        case .stag:      setupStag()
        }
    }

    /// Null Bug — small cyan sphere with translucent wing planes.
    private func setupButterfly() {
        let body = SCNSphere(radius: 0.04)
        body.materials = [makeMaterial(
            diffuse:  UIColor(red: 0.2,  green: 0.8, blue: 1.0, alpha: 1),
            emissive: UIColor(red: 0.05, green: 0.45, blue: 0.75, alpha: 1)
        )]
        geometry = body

        let wingGeo = SCNPlane(width: 0.14, height: 0.09)
        let wingMat = SCNMaterial()
        wingMat.diffuse.contents  = UIColor(red: 0.3, green: 1.0, blue: 0.9, alpha: 0.65)
        wingMat.emission.contents = UIColor(red: 0.1, green: 0.6, blue: 0.5, alpha: 0.40)
        wingMat.isDoubleSided = true
        wingMat.lightingModel = .phong
        wingGeo.materials = [wingMat]

        for sign: Float in [-1, 1] {
            let wing = SCNNode(geometry: wingGeo)
            wing.eulerAngles = SCNVector3(0, sign * .pi / 4, 0)
            wing.position    = SCNVector3(sign * 0.07, 0, 0)
            addChildNode(wing)
        }
    }

    /// Virus Bug — red/magenta capsule with dark accent spots.
    private func setupBeetle() {
        let cap = SCNCapsule(capRadius: 0.05, height: 0.13)
        cap.materials = [makeMaterial(
            diffuse:  UIColor(red: 0.85, green: 0.10, blue: 0.25, alpha: 1),
            emissive: UIColor(red: 0.45, green: 0.0,  blue: 0.10, alpha: 1)
        )]
        geometry = cap

        let spotGeo = SCNSphere(radius: 0.018)
        spotGeo.materials = [makeMaterial(
            diffuse:  UIColor(red: 0.10, green: 0.0, blue: 0.12, alpha: 1),
            emissive: .black
        )]
        for i in 0..<4 {
            let angle = Float(i) * .pi / 2
            let spot  = SCNNode(geometry: spotGeo)
            spot.position = SCNVector3(
                0.04 * cos(angle),
                i % 2 == 0 ? Float(0.025) : Float(-0.025),
                0.04 * sin(angle)
            )
            addChildNode(spot)
        }
    }

    /// Glitch Bug — gold box with four orange spike cones.
    private func setupStag() {
        let box = SCNBox(width: 0.10, height: 0.10, length: 0.10, chamferRadius: 0.01)
        box.materials = [makeMaterial(
            diffuse:  UIColor(red: 1.0,  green: 0.55, blue: 0.0, alpha: 1),
            emissive: UIColor(red: 0.55, green: 0.18, blue: 0.0, alpha: 1)
        )]
        geometry = box

        let spikeGeo = SCNCone(topRadius: 0, bottomRadius: 0.025, height: 0.07)
        spikeGeo.materials = [makeMaterial(
            diffuse:  UIColor(red: 1.0,  green: 0.82, blue: 0.0, alpha: 1),
            emissive: UIColor(red: 0.5,  green: 0.28, blue: 0.0, alpha: 1)
        )]

        let spikeConfig: [(SCNVector3, SCNVector3)] = [
            (SCNVector3(0,      0.13, 0), SCNVector3(0,        0,           0)),
            (SCNVector3(0,     -0.13, 0), SCNVector3(Float.pi, 0,           0)),
            (SCNVector3( 0.13,  0,    0), SCNVector3(0,        0, -Float.pi / 2)),
            (SCNVector3(-0.13,  0,    0), SCNVector3(0,        0,  Float.pi / 2)),
        ]
        for (pos, rot) in spikeConfig {
            let spike = SCNNode(geometry: spikeGeo)
            spike.position    = pos
            spike.eulerAngles = rot
            addChildNode(spike)
        }
    }

    // MARK: - Private: animations

    private func startAnimations() {
        // Start invisible then fade in
        opacity = 0
        runAction(SCNAction.fadeIn(duration: 0.45))

        // Continuous Y-rotation
        runAction(SCNAction.repeatForever(
            SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 3.0)
        ), forKey: "rotate")

        // Gentle hover (±3 cm), randomised duration so bugs look independent
        let up   = SCNAction.moveBy(x: 0, y: 0.03, z: 0,  duration: Double.random(in: 0.60...0.80))
        let down = SCNAction.moveBy(x: 0, y: -0.03, z: 0, duration: Double.random(in: 0.60...0.80))
        up.timingMode   = .easeInEaseOut
        down.timingMode = .easeInEaseOut
        runAction(SCNAction.repeatForever(SCNAction.sequence([up, down])), forKey: "hover")
    }

    // MARK: - Private: helpers

    private func makeMaterial(diffuse: UIColor, emissive: UIColor) -> SCNMaterial {
        let mat = SCNMaterial()
        mat.diffuse.contents  = diffuse
        mat.emission.contents = emissive
        mat.specular.contents = UIColor(white: 0.6, alpha: 1)
        mat.lightingModel     = .phong
        return mat
    }
}
