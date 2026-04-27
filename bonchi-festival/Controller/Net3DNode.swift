//
//  Net3DNode.swift
//  bonchi-festival
//
//  iOS Controller: RealityKit Entity that renders a 3-D flying net in the AR scene.
//  Created by ARGameView.Coordinator when the player fires the slingshot.
//
//  Implementation intent:
//    Rewritten to use RealityKit (no SceneKit) as required.
//    The net geometry is built from ModelEntity / generateBox / generateSphere primitives.
//    The parabolic flight animation is driven by a 60 fps Timer using kinematic equations,
//    which replaces the former SCNAction.customAction approach.
//
//  Security considerations:
//    No file I/O; all geometry is generated procedurally at runtime.
//    Timer is invalidated both on completion and in deinit to prevent leaks.
//
//  Constraints:
//    SceneKit (SCNNode, SCNScene, SCNAction, etc.) must NOT be used.
//

import RealityKit
import UIKit

// MARK: - Net3DNode

/// RealityKit-based flying net entity fired from the slingshot.
/// The `entity` property is the root Entity; callers add it to a world AnchorEntity.
final class Net3DNode {

    private static let meshBaseColor = UIColor(red: 0.30, green: 0.90, blue: 0.45, alpha: 0.90)

    /// Root RealityKit entity.  Callers: `netAnchor.addChild(net3D.entity)`
    let entity: Entity

    /// Flight simulation timer — invalidated after the net lands or on deinit.
    private var flightTimer: Timer?

    /// Material updates are applied directly to each visible segment because OpacityComponent
    /// is not available on all RealityKit deployment targets used by this project.
    /// Ring (torus) entities are intentionally absent — no circle objects are rendered.
    private var meshEntities: [ModelEntity] = []

    // MARK: - Init

    /// - Parameter playerIndex: reserved for future use; currently unused as rings are removed.
    init(playerIndex: Int = 0) {
        self.entity = Entity()
        setupMesh()
    }

    deinit {
        flightTimer?.invalidate()
    }

    // MARK: - Geometry

    private func setupMesh() {
        let meshMat = pbr(Self.meshBaseColor, roughness: 0.80, metalness: 0.0)

        // 8 radial spokes (thin flat boxes).
        // All ring/torus entities are intentionally omitted — no circle objects are rendered.
        for i in 0..<8 {
            let angle = Float(i) * .pi / 4
            let spoke = ModelEntity(
                mesh: .generateBox(size: SIMD3<Float>(0.082, 0.0015, 0.0015)),
                materials: [meshMat]
            )
            spoke.orientation = simd_quatf(angle: angle, axis: SIMD3<Float>(0, 0, 1))
            entity.addChild(spoke)
            meshEntities.append(spoke)
        }
    }

    // MARK: - Launch animation

    /// Fly the net from `origin` in `direction` with a realistic parabolic arc,
    /// then call `completion` when done.
    ///
    /// Trajectory: pos(t) = origin + velocity·t + ½·g·t²
    /// This makes weak throws arc and drop noticeably, while strong throws fly flat —
    /// matching player expectation from the drag gesture.
    ///
    /// - Parameters:
    ///   - origin:     World-space start position (SIMD3<Float>).
    ///   - direction:  Normalised world-space flight direction.
    ///   - power:      0–1 factor scaling initial speed and spin.
    ///   - completion: Called after the animation finishes (removes entity/anchor from scene).
    func launch(from origin: SIMD3<Float>, direction: SIMD3<Float>,
                power: Float, completion: @escaping () -> Void) {
        // Position entity at world-space origin (entity parent anchor is at world zero)
        entity.position = origin

        // Initial speed proportional to power (2.0–5.5 m/s)
        let speed: Float = 2.0 + power * 3.5
        let vx = direction.x * speed
        let vy = direction.y * speed
        let vz = direction.z * speed

        // Simulated world gravity (m/s²)
        let g: Float = -9.0

        // Travel time grows with power so harder shots reach farther (0.60–1.00 s)
        let travelTime: Float = 0.60 + power * 0.40

        // Initial orientation: face the direction of travel
        let flatLen = sqrt(direction.x * direction.x + direction.z * direction.z)
        if flatLen > 0.05 {
            entity.orientation = simd_quatf(angle: atan2(direction.x, -direction.z),
                                             axis: SIMD3<Float>(0, 1, 0))
        }

        // Start compact and invisible
        entity.scale = SIMD3<Float>(repeating: 0.22)
        setOpacity(0)

        // Precompute spin parameters
        let turns     = 0.8 + Double(power) * 2.0   // 0.8–2.8 full turns
        let spinSpeed = Float(turns * 2 * Double.pi) / travelTime

        let startTime = Date()
        let ox = origin.x, oy = origin.y, oz = origin.z

        // 60 fps Timer drives the physics + scale + opacity + spin each frame.
        // Timer is stored so it can be invalidated by stopAllTimers if needed.
        flightTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }

            let elapsed  = Float(Date().timeIntervalSince(startTime))
            let progress = elapsed / travelTime

            if elapsed >= travelTime {
                timer.invalidate()
                self.flightTimer = nil
                completion()
                return
            }

            // Kinematic position update (parabolic arc)
            self.entity.position = SIMD3<Float>(
                ox + vx * elapsed,
                oy + vy * elapsed + 0.5 * g * elapsed * elapsed,
                oz + vz * elapsed
            )

            // Tumbling spin: two axes for a natural toss appearance
            let spinAngle = spinSpeed * elapsed
            let yaw  = simd_quatf(angle: atan2(direction.x, -direction.z),
                                   axis: SIMD3<Float>(0, 1, 0))
            let spinZ = simd_quatf(angle:  spinAngle,        axis: SIMD3<Float>(0, 0, 1))
            let spinX = simd_quatf(angle:  spinAngle * 0.45, axis: SIMD3<Float>(1, 0, 0))
            self.entity.orientation = yaw * spinZ * spinX

            // Scale: compact → open → slight compress on landing
            let scale: Float
            if progress < 0.30 {
                scale = 0.22 + (1.0 - 0.22) * (progress / 0.30)
            } else if progress < 0.72 {
                scale = 1.0
            } else {
                scale = 1.0 + (0.55 - 1.0) * ((progress - 0.72) / 0.28)
            }
            self.entity.scale = SIMD3<Float>(repeating: scale)

            // Opacity: snap in → linger → dissolve
            let opacity: Float
            if progress < 0.07 / travelTime {
                opacity = progress / (0.07 / travelTime)
            } else if progress < 0.52 {
                opacity = 1.0
            } else {
                opacity = 1.0 - (progress - 0.52) / 0.48
            }
            let clampedOpacity = Swift.max(Float.zero, Swift.min(Float(1), opacity))
            self.setOpacity(clampedOpacity)
        }
    }

    private func setOpacity(_ opacity: Float) {
        let alpha = CGFloat(opacity)
        let meshColor = Self.meshBaseColor.withAlphaComponent(alpha * Self.meshBaseColor.cgColor.alpha)

        for segment in meshEntities {
            segment.model?.materials = [
                pbr(meshColor, roughness: 0.80, metalness: 0.0)
            ]
        }
    }

    // MARK: - PBR material factory

    /// Creates a PhysicallyBasedMaterial for net geometry.
    private func pbr(_ color: UIColor, roughness: Float, metalness: Float,
                     emission: UIColor = .black) -> PhysicallyBasedMaterial {
        var mat = PhysicallyBasedMaterial()
        mat.baseColor = .init(tint: color)
        mat.roughness = .init(floatLiteral: roughness)
        mat.metallic  = .init(floatLiteral: metalness)
        if emission != .black {
            mat.emissiveColor     = .init(color: emission)
            mat.emissiveIntensity = 0.5
        }
        return mat
    }
}
