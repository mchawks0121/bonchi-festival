//
//  ForestEnvironment.swift
//  bonchi-festival
//
//  Forest background decorator for both the iOS AR scene and the projector scene.
//
//  Implementation intent:
//    Creates procedural 3-D tree entities using RealityKit primitives (generateBox /
//    generateSphere) with PhysicallyBasedMaterial so they blend naturally with the
//    PBR-lit bug entities.  Trees are purely decorative: no timers, no physics.
//
//    Two entry points exist:
//      • plantARTrees(in:origin:)      — AR (pass-through) mode; trees anchored in
//                                        world space at roughly ground level relative
//                                        to the calibration origin.
//      • plantProjectorTrees(in:)      — Projector (nonAR) mode; trees placed behind
//                                        the bug plane (Z < 0) at the edges of the
//                                        visible frustum to frame the scene.
//
//    Three tree silhouette variants are supported:
//      0 — round (single large sphere canopy)
//      1 — conical (stacked decreasing-width boxes)
//      2 — layered (three overlapping spheres at different heights)
//
//  Security considerations:
//    No file I/O; all geometry is generated from RealityKit mesh primitives.
//
//  Constraints:
//    SceneKit (SCNNode, SCNScene, etc.) must NOT be used.
//

import RealityKit
import UIKit
import ARKit

// MARK: - ForestEnvironment

/// Utility that plants static procedural tree entities in a RealityKit scene.
enum ForestEnvironment {

    // MARK: - Public API

    /// Plants background trees suited for the iOS AR (pass-through) scene.
    ///
    /// Trees are anchored in world space relative to `origin`.  A nil origin
    /// falls back to the identity transform (initial camera position).
    /// The Y offset (-1.2 m) assumes the player is standing and the origin
    /// is at approximately eye level, placing trunks at ground level.
    static func plantARTrees(in arView: ARView, origin: simd_float4x4?) {
        let base = origin ?? matrix_identity_float4x4
        for config in arTreeConfigs {
            let localPos = SIMD4<Float>(config.position.x, config.position.y,
                                       config.position.z, 1)
            let worldPos = base * localPos
            var anchorTransform = matrix_identity_float4x4
            anchorTransform.columns.3 = worldPos
            let anchor = AnchorEntity(world: anchorTransform)
            anchor.addChild(makeTree(config: config))
            arView.scene.addAnchor(anchor)
        }
    }

    /// Plants background trees suited for the projector (nonAR) scene.
    ///
    /// Trees are placed at Z < 0 (behind the bug plane at Z = 0) at the outer
    /// edges of the visible frustum so they frame the bugs without occluding them.
    /// The projector camera sits at Z = `cameraZ` looking toward Z = 0.
    static func plantProjectorTrees(in arView: ARView) {
        for config in projectorTreeConfigs {
            let anchor = AnchorEntity(world: matrix_identity_float4x4)
            anchor.position = config.position
            anchor.addChild(makeTree(config: config))
            arView.scene.addAnchor(anchor)
        }
    }

    // MARK: - Tree configuration

    /// Parameters describing a single tree instance.
    private struct TreeConfig {
        /// World-space position of the base of the trunk.
        var position: SIMD3<Float>
        /// Height of the trunk in metres.
        var trunkHeight: Float
        /// Radius of the foliage crown in metres.
        var foliageRadius: Float
        /// Silhouette variant: 0 = round, 1 = conical, 2 = layered.
        var variant: Int
    }

    // MARK: AR tree layout

    /// Trees placed around the AR spawn origin at 2–5 m distance and ground level.
    /// Y = -1.2 m represents the floor when the calibration point is at eye height.
    private static let arTreeConfigs: [TreeConfig] = [
        // Front semi-circle
        TreeConfig(position: SIMD3( 1.8, -1.2,  2.2), trunkHeight: 1.8, foliageRadius: 0.9, variant: 0),
        TreeConfig(position: SIMD3(-1.8, -1.2,  2.2), trunkHeight: 2.0, foliageRadius: 1.0, variant: 1),
        TreeConfig(position: SIMD3( 0.0, -1.2,  3.0), trunkHeight: 2.2, foliageRadius: 1.1, variant: 2),
        // Side trees
        TreeConfig(position: SIMD3( 3.0, -1.2,  0.5), trunkHeight: 1.6, foliageRadius: 0.8, variant: 1),
        TreeConfig(position: SIMD3(-3.0, -1.2,  0.5), trunkHeight: 1.9, foliageRadius: 0.9, variant: 2),
        TreeConfig(position: SIMD3( 3.5, -1.2, -0.8), trunkHeight: 2.0, foliageRadius: 1.0, variant: 0),
        TreeConfig(position: SIMD3(-3.5, -1.2, -0.8), trunkHeight: 1.7, foliageRadius: 0.8, variant: 1),
        // Back trees
        TreeConfig(position: SIMD3( 1.2, -1.2, -2.8), trunkHeight: 2.4, foliageRadius: 1.2, variant: 2),
        TreeConfig(position: SIMD3(-1.2, -1.2, -2.8), trunkHeight: 2.1, foliageRadius: 1.0, variant: 0),
        TreeConfig(position: SIMD3( 0.0, -1.2, -4.0), trunkHeight: 2.6, foliageRadius: 1.3, variant: 1),
        // Far-side accent trees
        TreeConfig(position: SIMD3( 4.5, -1.2,  1.5), trunkHeight: 1.5, foliageRadius: 0.75, variant: 0),
        TreeConfig(position: SIMD3(-4.5, -1.2,  1.5), trunkHeight: 1.5, foliageRadius: 0.75, variant: 2),
    ]

    // MARK: Projector tree layout

    /// Trees placed behind and to the sides of the bug plane (Z ≤ 0) in the
    /// projector's world space.  The camera sits at Z = 3.5; the bug plane is
    /// at Z = 0, so negative Z is further from the camera.
    ///
    /// Row depths:
    ///   - Far background: Z = -3 to -4 (distant, smaller apparent size)
    ///   - Mid background: Z = -1 to -2
    ///   - Side columns:   Z = 0 to 0.5 (screen edges, beyond the playfield)
    private static let projectorTreeConfigs: [TreeConfig] = [
        // Far background row
        TreeConfig(position: SIMD3(-4.2, -1.6, -3.5), trunkHeight: 1.2, foliageRadius: 0.90, variant: 0),
        TreeConfig(position: SIMD3(-2.0, -1.6, -4.0), trunkHeight: 1.5, foliageRadius: 1.10, variant: 1),
        TreeConfig(position: SIMD3( 0.3, -1.6, -4.2), trunkHeight: 1.3, foliageRadius: 0.95, variant: 2),
        TreeConfig(position: SIMD3( 2.5, -1.6, -3.8), trunkHeight: 1.4, foliageRadius: 1.00, variant: 0),
        TreeConfig(position: SIMD3( 4.5, -1.6, -3.2), trunkHeight: 1.1, foliageRadius: 0.85, variant: 1),
        // Mid background row
        TreeConfig(position: SIMD3(-4.5, -1.4, -1.8), trunkHeight: 1.6, foliageRadius: 1.10, variant: 2),
        TreeConfig(position: SIMD3(-2.5, -1.4, -2.0), trunkHeight: 1.8, foliageRadius: 1.25, variant: 0),
        TreeConfig(position: SIMD3(-0.5, -1.4, -1.5), trunkHeight: 1.5, foliageRadius: 1.00, variant: 1),
        TreeConfig(position: SIMD3( 1.8, -1.4, -1.8), trunkHeight: 1.7, foliageRadius: 1.15, variant: 2),
        TreeConfig(position: SIMD3( 4.0, -1.4, -1.5), trunkHeight: 1.4, foliageRadius: 1.00, variant: 0),
        // Side columns (at or just past the screen edges of the bug plane)
        TreeConfig(position: SIMD3(-5.5, -1.3,  0.2), trunkHeight: 2.0, foliageRadius: 1.30, variant: 1),
        TreeConfig(position: SIMD3(-5.0, -1.3, -0.5), trunkHeight: 1.8, foliageRadius: 1.20, variant: 2),
        TreeConfig(position: SIMD3( 5.5, -1.3,  0.2), trunkHeight: 2.0, foliageRadius: 1.30, variant: 0),
        TreeConfig(position: SIMD3( 5.0, -1.3, -0.5), trunkHeight: 1.8, foliageRadius: 1.15, variant: 1),
        // Near accent trees (Z ≈ -0.4) peeking from behind the play area
        TreeConfig(position: SIMD3(-5.8, -1.2,  0.8), trunkHeight: 2.2, foliageRadius: 1.40, variant: 2),
        TreeConfig(position: SIMD3( 5.8, -1.2,  0.8), trunkHeight: 2.2, foliageRadius: 1.40, variant: 0),
    ]

// MARK: - Procedural tree geometry

    /// Builds a single tree entity consisting of a trunk and a foliage crown.
    private static func makeTree(config: TreeConfig) -> Entity {
        let root = Entity()

        // ── Trunk ────────────────────────────────────────────────────────────
        // Approximated as a tall rounded box with a narrow cross-section.
        let trunkMat = makePBR(
            UIColor(red: 0.32, green: 0.20, blue: 0.10, alpha: 1),
            roughness: 0.90, metalness: 0.0
        )
        // Minimum width prevents degenerate geometry on very short trunks.
        let trunkW: Float = max(trunkMinWidth, config.trunkHeight * trunkWidthRatio)
        let trunk = ModelEntity(
            mesh: .generateBox(
                size: SIMD3<Float>(trunkW, config.trunkHeight, trunkW),
                cornerRadius: trunkW * trunkCornerRadiusRatio
            ),
            materials: [trunkMat]
        )
        // Anchor position is at trunk base; shift up by half height so the base
        // sits on the anchor's Y=0 plane.
        trunk.position = SIMD3<Float>(0, config.trunkHeight * 0.5, 0)
        root.addChild(trunk)

        // ── Foliage ──────────────────────────────────────────────────────────
        let topY = config.trunkHeight
        switch config.variant % 3 {
        case 0: addRoundFoliage(to: root, topY: topY, radius: config.foliageRadius)
        case 1: addConeFoliage( to: root, topY: topY, radius: config.foliageRadius)
        default: addLayeredFoliage(to: root, topY: topY, radius: config.foliageRadius)
        }

        return root
    }

    // MARK: Geometry constants
    // These ratios control the proportions of the procedural tree geometry.

    /// Minimum trunk cross-section width (m) to prevent degenerate geometry.
    private static let trunkMinWidth:          Float = 0.06
    /// Trunk width as a fraction of trunk height (slender profile).
    private static let trunkWidthRatio:        Float = 0.11
    /// Corner radius of the trunk box as a fraction of trunk width.
    private static let trunkCornerRadiusRatio: Float = 0.35

    /// Vertical offset of the round-crown sphere centre above the trunk top,
    /// as a fraction of the foliage radius. Embeds the base of the sphere
    /// slightly into the trunk top for a natural connection.
    private static let roundFoliageVerticalOffset: Float = 0.65

    /// Height of each cone-foliage tier as a fraction of the foliage radius.
    private static let coneFoliageLayerHeightRatio: Float = 0.70
    /// Width multiplier applied to the full-radius tier of the cone crown.
    /// A value > 1 makes the widest tier broader than the foliage radius.
    private static let coneTierWidthMultiplier:     Float = 1.90
    /// Corner radius of cone foliage boxes as a fraction of their height.
    private static let foliageBoxCornerRadiusRatio: Float = 0.30
    /// Vertical half-offset applied to each successive cone tier (fraction of layerH).
    private static let tierHalfOffset:              Float = 0.5
    /// Vertical gap multiplier between consecutive cone tiers (fraction of layerH).
    private static let tierVerticalSpacing:         Float = 0.68

    /// Vertical offset of each layered sphere centre above trunk top,
    /// as a fraction of the sphere radius. Mirrors roundFoliageVerticalOffset.
    private static let layeredFoliageBaseOffset:    Float = 0.70

    // MARK: Foliage variants

    /// Single large sphere canopy (variant 0).
    private static func addRoundFoliage(to parent: Entity, topY: Float, radius: Float) {
        let mat  = foliageMaterial(shade: 0)
        let node = ModelEntity(mesh: .generateSphere(radius: radius), materials: [mat])
        node.position = SIMD3<Float>(0, topY + radius * roundFoliageVerticalOffset, 0)
        parent.addChild(node)
    }

    /// Three stacked decreasing-width boxes approximating a conical crown (variant 1).
    private static func addConeFoliage(to parent: Entity, topY: Float, radius: Float) {
        let layerH = radius * coneFoliageLayerHeightRatio
        // Tier widths: 100 % → 65 % → 35 %
        let tiers: [(widthScale: Float, shade: Int)] = [(1.0, 0), (0.65, 1), (0.35, 2)]
        for (i, tier) in tiers.enumerated() {
            let mat = foliageMaterial(shade: tier.shade)
            let w   = radius * tier.widthScale * coneTierWidthMultiplier
            let box = ModelEntity(
                mesh: .generateBox(
                    size: SIMD3<Float>(w, layerH, w),
                    cornerRadius: layerH * foliageBoxCornerRadiusRatio
                ),
                materials: [mat]
            )
            box.position = SIMD3<Float>(0,
                topY + layerH * tierHalfOffset + Float(i) * layerH * tierVerticalSpacing, 0)
            parent.addChild(box)
        }
    }

    /// Three overlapping spheres at ascending heights (variant 2).
    private static func addLayeredFoliage(to parent: Entity, topY: Float, radius: Float) {
        let layers: [(yOffset: Float, scaleFactor: Float, shade: Int)] = [
            (0.00, 1.00, 0),
            (0.50, 0.80, 1),
            (1.00, 0.55, 2),
        ]
        for layer in layers {
            let mat = foliageMaterial(shade: layer.shade)
            let r   = radius * layer.scaleFactor
            let sphere = ModelEntity(mesh: .generateSphere(radius: r), materials: [mat])
            sphere.position = SIMD3<Float>(0, topY + r * layeredFoliageBaseOffset + layer.yOffset * radius, 0)
            parent.addChild(sphere)
        }
    }

    // MARK: - Material helpers

    /// Returns a foliage PBR material in one of three forest-green shades.
    ///
    /// - shade 0: dark forest green (lower canopy, less light)
    /// - shade 1: medium green
    /// - shade 2: lighter green (upper canopy, more exposed)
    private static func foliageMaterial(shade: Int) -> PhysicallyBasedMaterial {
        let greens: [(r: Float, g: Float, b: Float)] = [
            (0.07, 0.30, 0.07),   // shade 0 — dark forest green
            (0.10, 0.40, 0.09),   // shade 1 — mid green
            (0.16, 0.50, 0.13),   // shade 2 — lighter canopy green
        ]
        let c = greens[shade % greens.count]
        return makePBR(
            UIColor(red: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: 1),
            roughness: 0.88, metalness: 0.0
        )
    }

    /// Creates a PhysicallyBasedMaterial, mirroring the helper in Bug3DNode.
    private static func makePBR(_ diffuse: UIColor,
                                roughness: Float,
                                metalness: Float) -> PhysicallyBasedMaterial {
        var mat = PhysicallyBasedMaterial()
        mat.baseColor = .init(tint: diffuse)
        mat.roughness = .init(floatLiteral: roughness)
        mat.metallic  = .init(floatLiteral: metalness)
        return mat
    }
}
