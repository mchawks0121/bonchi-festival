//
//  SlingshotNode.swift
//  bonchi-festival
//
//  iOS Controller: RealityKit Entity that renders a minimal 3-D Y-shaped slingshot.
//  The entity must be added as a child of an AnchorEntity(.camera) so it stays fixed
//  in the camera's view frustum regardless of how the device moves.
//
//  Implementation intent:
//    Rewritten to use RealityKit (no SceneKit) as required.
//    Fork/tine geometry uses generateBox/generateSphere primitives.
//    Rubber bands are unit-height box entities scaled and oriented each frame to span
//    the tine tips → pull-point, replacing the former SCNCylinder height mutation.
//
//  Security considerations:
//    No file I/O; all geometry is generated procedurally at runtime.
//
//  Constraints:
//    SceneKit (SCNNode, SCNScene, SCNAction, etc.) must NOT be used.
//    The entity is attached to AnchorEntity(.camera) by the caller (ARGameView.Coordinator).
//
//  All positions are in the entity's local coordinate space (camera space):
//    +X right, +Y up, -Z into scene (camera looks in -Z direction in ARKit/RealityKit).
//

import RealityKit
import UIKit

// MARK: - SlingshotNode

/// RealityKit-based slingshot entity fixed in the camera's view frustum.
/// The `entity` property is the root Entity; callers attach it to AnchorEntity(.camera).
final class SlingshotNode {

    // MARK: Geometry constants (camera-local space, metres)

    /// Position of the fork's centre in camera space.
    private static let forkCenter = SIMD3<Float>(0, -0.09, -0.26)

    // Positions in forkRoot's local frame:
    private static let stemBottom  = SIMD3<Float>(0,     -0.058,  0)
    private static let branch      = SIMD3<Float>(0,      0.006,  0)
    private static let leftTip     = SIMD3<Float>(-0.052, 0.068, -0.005)
    private static let rightTip    = SIMD3<Float>( 0.052, 0.068, -0.005)
    private static let neutralPull = SIMD3<Float>(0,      0.042,  0.0)

    private static let maxPullDepth:   Float = 0.080
    private static let maxPullLateral: Float = 0.022
    private static let maxPullDown:    Float = 0.012

    // MARK: Root entity

    /// Root entity for this slingshot; attach to AnchorEntity(.camera).
    let entity: Entity

    // MARK: Sub-entities for dynamic band alignment

    /// Band entity spanning left tine → pull point.
    /// A unit-height box scaled to match the band length each frame.
    private let leftBandEntity:  ModelEntity
    /// Band entity spanning right tine → pull point.
    private let rightBandEntity: ModelEntity
    /// Glowing pouch sphere visible only during drag.
    private let pouchEntity:     ModelEntity

    /// forkRoot is offset from entity root by forkCenter (camera-space).
    private let forkRoot: Entity

    /// Current pull-point in forkRoot's local frame.
    private var pullPoint = SlingshotNode.neutralPull

    // MARK: - Init

    init() {
        entity         = Entity()
        forkRoot       = Entity()
        leftBandEntity = SlingshotNode.makeBandEntity()
        rightBandEntity = SlingshotNode.makeBandEntity()

        // Pouch: neon glowing sphere visible only while dragging
        let neonMat = SlingshotNode.makeNeonMat()
        pouchEntity = ModelEntity(mesh: .generateSphere(radius: 0.012), materials: [neonMat])

        forkRoot.position = SlingshotNode.forkCenter
        entity.addChild(forkRoot)

        setupFork()
        setupBands()
        pouchEntity.isEnabled = false     // hidden until drag starts
        pouchEntity.position  = SlingshotNode.neutralPull
        forkRoot.addChild(pouchEntity)

        updateBands()
    }

    // MARK: - Public API

    /// Update rubber-band and pouch position to match the current drag gesture.
    /// - Parameters:
    ///   - offset:  SwiftUI dragOffset (+width = right, +height = pulled down).
    ///   - maxDrag: The view's maxDragDistance (points) used for normalisation.
    func updateDrag(offset: CGSize, maxDrag: CGFloat) {
        let nx = Float(offset.width  / maxDrag)
        let ny = Float(offset.height / maxDrag)

        pullPoint = SIMD3<Float>(
             nx * SlingshotNode.maxPullLateral,
             SlingshotNode.neutralPull.y - ny * SlingshotNode.maxPullDown,
             ny * SlingshotNode.maxPullDepth          // +Z = toward camera
        )
        updateBands()
        pouchEntity.isEnabled = true
    }

    /// Snap rubber bands and pouch back to the neutral (un-pulled) position.
    func resetDrag() {
        pullPoint = SlingshotNode.neutralPull
        updateBands()
        pouchEntity.isEnabled = false
    }

    // MARK: - Private: fork geometry

    private func setupFork() {
        // Dark anodized-metal body: near-black, high metalness.
        let bodyMat = pbr(UIColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1),
                          roughness: 0.28, metalness: 0.85)
        // Yellow-green glow caps on tine tips (changed from cyan to avoid "blue circle"
        // appearance when the spheres are visible in the AR camera view).
        let tipMat = pbr(UIColor(red: 0.45, green: 1.00, blue: 0.20, alpha: 1),
                         roughness: 0.25, metalness: 0.10,
                         emission: UIColor(red: 0.18, green: 0.48, blue: 0.04, alpha: 1))

        // Stem: unit-height box entity, scaled and rotated to span stemBottom → branch
        forkRoot.addChild(
            staticBar(from: SlingshotNode.stemBottom,
                      to: SlingshotNode.branch,
                      radius: 0.008, material: bodyMat)
        )

        // Left tine: branch → leftTip
        forkRoot.addChild(
            staticBar(from: SlingshotNode.branch,
                      to: SlingshotNode.leftTip,
                      radius: 0.007, material: bodyMat)
        )

        // Right tine: branch → rightTip
        forkRoot.addChild(
            staticBar(from: SlingshotNode.branch,
                      to: SlingshotNode.rightTip,
                      radius: 0.007, material: bodyMat)
        )

        // Neon sphere caps on each tine tip
        for tip in [SlingshotNode.leftTip, SlingshotNode.rightTip] {
            let dot = ModelEntity(mesh: .generateSphere(radius: 0.010), materials: [tipMat])
            dot.position = tip
            forkRoot.addChild(dot)
        }
    }

    // MARK: - Private: rubber bands

    private func setupBands() {
        // Slim yellow-green elastic band with soft emissive glow (changed from cyan).
        forkRoot.addChild(leftBandEntity)
        forkRoot.addChild(rightBandEntity)
    }

    /// Creates a unit-height (height=1) rounded-box band entity to be scaled at runtime.
    private static func makeBandEntity() -> ModelEntity {
        let mat = makeNeonMat()
        // Height=1.0 so scale.y can be set directly to the desired length.
        let mesh = MeshResource.generateBox(size: SIMD3<Float>(0.0056, 1.0, 0.0056),
                                            cornerRadius: 0.0028)
        let e = ModelEntity(mesh: mesh, materials: [mat])
        e.scale = SIMD3<Float>(1, 0.001, 1)   // near-zero until first update
        return e
    }

    /// Yellow-green neon band material shared by bands and pouch.
    /// Changed from cyan to avoid blue appearance in the AR camera view.
    private static func makeNeonMat() -> PhysicallyBasedMaterial {
        var mat = PhysicallyBasedMaterial()
        mat.baseColor     = .init(tint: UIColor(red: 0.35, green: 0.92, blue: 0.10, alpha: 1))
        mat.roughness     = .init(floatLiteral: 0.50)
        mat.metallic      = .init(floatLiteral: 0.0)
        mat.emissiveColor = .init(color: UIColor(red: 0.15, green: 0.38, blue: 0.03, alpha: 1))
        mat.emissiveIntensity = 0.4
        return mat
    }

    // MARK: - Band update (called every frame while dragging)

    private func updateBands() {
        alignBand(leftBandEntity,  from: SlingshotNode.leftTip,  to: pullPoint)
        alignBand(rightBandEntity, from: SlingshotNode.rightTip, to: pullPoint)
        pouchEntity.position = pullPoint
    }

    /// Scales and orients a unit-height band entity to span from `a` to `b`.
    ///
    /// The entity's mesh is a box of height 1.0 along the Y-axis.
    /// Setting scale.y = length and orienting the Y-axis toward (b-a) produces
    /// the correct visual span without requiring mesh regeneration each frame.
    private func alignBand(_ e: ModelEntity, from a: SIMD3<Float>, to b: SIMD3<Float>) {
        let diff   = b - a
        let length = simd_length(diff)
        guard length > 1e-6 else { return }

        e.position = (a + b) / 2
        e.scale    = SIMD3<Float>(1, length, 1)

        // Compute rotation from the Y-axis to the direction vector
        let dir   = diff / length
        let yAxis = SIMD3<Float>(0, 1, 0)
        let dot   = simd_dot(yAxis, dir)

        if dot > 0.9999 {
            e.orientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        } else if dot < -0.9999 {
            // Anti-parallel: rotate 180° around any perpendicular axis
            e.orientation = simd_quatf(angle: .pi, axis: SIMD3<Float>(1, 0, 0))
        } else {
            let cross = simd_cross(yAxis, dir)
            e.orientation = simd_normalize(
                simd_quatf(ix: cross.x, iy: cross.y, iz: cross.z, r: 1 + dot)
            )
        }
    }

    // MARK: - Static bar helper

    /// Creates a ModelEntity (rounded box) oriented to span from `a` to `b`.
    private func staticBar(from a: SIMD3<Float>, to b: SIMD3<Float>,
                           radius: Float, material: RealityKit.Material) -> ModelEntity {
        let diff   = b - a
        let length = simd_length(diff)
        let d      = diff / max(length, 1e-6)

        // Build a unit box, then scale Y to the desired length
        let mesh = MeshResource.generateBox(size: SIMD3<Float>(radius * 2, 1.0, radius * 2),
                                            cornerRadius: radius * 0.9)
        let e = ModelEntity(mesh: mesh, materials: [material])
        e.scale    = SIMD3<Float>(1, length, 1)
        e.position = (a + b) / 2

        // Rotate Y-axis toward direction vector
        let yAxis = SIMD3<Float>(0, 1, 0)
        let dot   = simd_dot(yAxis, d)
        if dot > 0.9999 {
            e.orientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        } else if dot < -0.9999 {
            e.orientation = simd_quatf(angle: .pi, axis: SIMD3<Float>(1, 0, 0))
        } else {
            let cross = simd_cross(yAxis, d)
            e.orientation = simd_normalize(
                simd_quatf(ix: cross.x, iy: cross.y, iz: cross.z, r: 1 + dot)
            )
        }
        return e
    }

    // MARK: - PBR material factory

    private func pbr(_ color: UIColor, roughness: Float, metalness: Float,
                     emission: UIColor = .black) -> PhysicallyBasedMaterial {
        var mat = PhysicallyBasedMaterial()
        mat.baseColor = .init(tint: color)
        mat.roughness = .init(floatLiteral: roughness)
        mat.metallic  = .init(floatLiteral: metalness)
        if emission != .black {
            mat.emissiveColor     = .init(color: emission)
            mat.emissiveIntensity = 0.4
        }
        return mat
    }
}
