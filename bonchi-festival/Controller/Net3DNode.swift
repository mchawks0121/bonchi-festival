//
//  Net3DNode.swift
//  bonchi-festival
//
//  iOS Controller: SCNNode that renders a 3-D flying net in the AR scene.
//  Created by ARGameView.Coordinator when the player fires the slingshot.
//  The net flies forward from the slingshot toward the target area, spinning
//  and expanding as it travels, then fades out on arrival.
//

import SceneKit
import UIKit

// MARK: - Net3DNode

final class Net3DNode: SCNNode {

    // MARK: - Init

    /// - Parameter playerIndex: 0-based player slot used to tint the rim.
    init(playerIndex: Int = 0) {
        super.init()
        setupMesh(playerIndex: playerIndex)
    }

    required init?(coder: NSCoder) { fatalError("Net3DNode does not support NSCoding") }

    // MARK: - Setup

    private static let accentColors: [UIColor] = [
        UIColor(red: 0.0, green: 1.0, blue: 1.0, alpha: 1),   // Player 1 cyan
        UIColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 1),  // Player 2 orange
        UIColor(red: 1.0, green: 0.2,  blue: 0.8, alpha: 1),  // Player 3 magenta
    ]

    private func setupMesh(playerIndex: Int) {
        let accent = Net3DNode.accentColors[playerIndex % Net3DNode.accentColors.count]

        let rimMat = pbrMat(accent, roughness: 0.55, metalness: 0.20,
                            emission: accent.withAlphaComponent(0.45))
        let meshMat = pbrMat(UIColor(red: 0.30, green: 0.90, blue: 0.45, alpha: 0.90),
                             roughness: 0.80, metalness: 0.0)
        meshMat.isDoubleSided = true

        // Outer torus rim — oriented to face +Z so the net is perpendicular to camera forward.
        let rim = SCNNode(geometry: SCNTorus(ringRadius: 0.042, pipeRadius: 0.0045))
        rim.geometry!.materials = [rimMat]
        rim.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        addChildNode(rim)

        // 8 radial spokes
        for i in 0..<8 {
            let angle = Float(i) * .pi / 4
            let spoke = SCNNode(
                geometry: SCNBox(width: 0.082, height: 0.0015, length: 0.0015, chamferRadius: 0)
            )
            spoke.geometry!.materials = [meshMat]
            spoke.eulerAngles = SCNVector3(0, 0, angle)
            addChildNode(spoke)
        }

        // Two inner concentric rings
        for r: CGFloat in [0.020, 0.032] {
            let ring = SCNNode(geometry: SCNTorus(ringRadius: r, pipeRadius: 0.002))
            ring.geometry!.materials = [rimMat]
            ring.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
            addChildNode(ring)
        }

        castsShadow = false
    }

    // MARK: - Launch animation

    /// Fly the net from `origin` in `direction`, then call `completion` when done.
    /// - Parameters:
    ///   - origin:    World-space start position.
    ///   - direction: Normalised world-space flight direction.
    ///   - power:     0–1 factor that scales travel distance and spin.
    ///   - completion: Called after the animation finishes (use to remove from scene).
    func launch(from origin: SCNVector3, direction: SCNVector3,
                power: Float, completion: @escaping () -> Void) {
        position = origin

        let distance: Float   = 0.65 + power * 1.20   // 0.65–1.85 m
        let travelTime: TimeInterval = 0.55

        let dest = SCNVector3(
            origin.x + direction.x * distance,
            origin.y + direction.y * distance,
            origin.z + direction.z * distance
        )

        // Travel
        let move = SCNAction.move(to: dest, duration: travelTime)
        move.timingMode = .easeOut

        // Tumbling spin: X + Z give a dynamic "coin-toss" look
        let turns    = Double(1.2 + Double(power) * 1.5)   // 1.2–2.7 full turns
        let spinZ    = SCNAction.rotateBy(x: 0, y: 0, z: CGFloat(.pi * 2 * turns),
                                          duration: travelTime)
        let spinX    = SCNAction.rotateBy(x: CGFloat(.pi * turns * 0.4), y: 0, z: 0,
                                          duration: travelTime)
        spinZ.timingMode = .easeOut
        spinX.timingMode = .easeOut

        // Scale: compact at start → full size → shrink on landing
        scale = SCNVector3(0.25, 0.25, 0.25)
        let scaleUp   = SCNAction.scale(to: 1.0, duration: travelTime * 0.35)
        let scaleHold = SCNAction.scale(to: 1.0, duration: travelTime * 0.35)
        let scaleDown = SCNAction.scale(to: 0.5, duration: travelTime * 0.30)
        let scaleSeq  = SCNAction.sequence([scaleUp, scaleHold, scaleDown])

        // Fade: appear quickly, linger, then dissolve
        opacity = 0
        let fadeIn  = SCNAction.fadeIn(duration: 0.06)
        let hold    = SCNAction.wait(duration: travelTime * 0.55)
        let fadeOut = SCNAction.fadeOut(duration: travelTime * 0.45)
        let fadeSeq = SCNAction.sequence([fadeIn, hold, fadeOut])

        runAction(SCNAction.group([move, spinZ, spinX, scaleSeq, fadeSeq])) {
            completion()
        }
    }

    // MARK: - PBR material helper

    private func pbrMat(_ color: UIColor, roughness: Float, metalness: Float,
                        emission: UIColor = .black) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents   = color
        m.roughness.contents = NSNumber(value: roughness)
        m.metalness.contents = NSNumber(value: metalness)
        m.emission.contents  = emission
        m.isDoubleSided      = true
        m.lightingModel      = .physicallyBased
        return m
    }
}
