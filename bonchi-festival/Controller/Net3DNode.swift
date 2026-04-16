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

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented for Net3DNode") }

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

    /// Fly the net from `origin` in `direction` with a realistic parabolic arc,
    /// then call `completion` when done.
    ///
    /// Trajectory: horizontal velocity is constant; vertical velocity decreases
    /// under simulated world-space gravity (pos(t) = origin + v·t + ½·g·t²).
    /// This makes weak throws arc and drop noticeably, while strong throws fly
    /// flatter and farther — matching player expectation from the drag gesture.
    ///
    /// - Parameters:
    ///   - origin:    World-space start position.
    ///   - direction: Normalised world-space flight direction.
    ///   - power:     0–1 factor that scales initial speed and spin.
    ///   - completion: Called after the animation finishes (use to remove from scene).
    func launch(from origin: SCNVector3, direction: SCNVector3,
                power: Float, completion: @escaping () -> Void) {
        position = origin

        // Initial speed proportional to power (1.4 – 3.6 m/s).
        let speed: Float = 1.4 + power * 2.2
        // Upward bias adds arc to near-horizontal shots (simulates the throw loft).
        let upBias: Float = 0.30 * (1.0 - abs(direction.y))

        // Velocity components in world space.
        let vx = direction.x * speed
        let vy = direction.y * speed + upBias
        let vz = direction.z * speed

        // World-space gravitational acceleration (m/s²).
        // Weaker than real-world (9.8) for a more floaty, game-friendly arc.
        let g: Float = -5.0

        // Travel time grows with power so harder shots reach farther.
        let travelTime: TimeInterval = 0.50 + Double(power) * 0.20  // 0.50–0.70 s

        // Capture origin as plain Floats (value types) for the physics closure.
        let ox = origin.x, oy = origin.y, oz = origin.z

        // Orient rim to face the direction of travel at launch.
        let flatLen = sqrt(direction.x * direction.x + direction.z * direction.z)
        if flatLen > 0.05 {
            eulerAngles = SCNVector3(0, atan2(direction.x, -direction.z), 0)
        }

        // Parabolic position: pos(t) = origin + velocity·t + ½·g·t²
        // SCNAction.customAction provides `elapsed` = time since action started (not delta),
        // so the kinematic equations can be applied directly each frame.
        let physicsMove = SCNAction.customAction(withDuration: travelTime) { node, elapsed in
            let t = Float(elapsed)
            node.position = SCNVector3(
                ox + vx * t,
                oy + vy * t + 0.5 * g * t * t,
                oz + vz * t
            )
        }

        // Tumbling spin — two axes for a natural toss look; faster at higher power.
        let turns = Double(0.8 + Double(power) * 2.0)   // 0.8–2.8 full turns
        let spinZ = SCNAction.rotateBy(x: 0, y: 0, z: CGFloat(.pi * 2.0 * turns),
                                       duration: travelTime)
        let spinX = SCNAction.rotateBy(x: CGFloat(.pi * turns * 0.45), y: 0, z: 0,
                                       duration: travelTime)
        spinZ.timingMode = .easeOut
        spinX.timingMode = .easeOut

        // Scale: compact at launch → fully open → slight compress on landing.
        scale = SCNVector3(0.22, 0.22, 0.22)
        let scaleSeq = SCNAction.sequence([
            SCNAction.scale(to: 1.0,  duration: travelTime * 0.30),
            SCNAction.scale(to: 1.0,  duration: travelTime * 0.42),
            SCNAction.scale(to: 0.55, duration: travelTime * 0.28),
        ])

        // Fade: snap in → linger → dissolve.
        opacity = 0
        let fadeSeq = SCNAction.sequence([
            SCNAction.fadeIn(duration: 0.07),
            SCNAction.wait(duration: travelTime * 0.52),
            SCNAction.fadeOut(duration: travelTime * 0.48),
        ])

        runAction(SCNAction.group([physicsMove, spinZ, spinX, scaleSeq, fadeSeq])) {
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
