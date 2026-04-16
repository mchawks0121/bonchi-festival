//
//  SlingshotNode.swift
//  bonchi-festival
//
//  iOS Controller: SCNNode that renders a minimal 3-D Y-shaped slingshot in the AR scene.
//  The node must be added as a child of `arView.pointOfView` so it stays fixed
//  in the camera's view frustum regardless of how the device moves.
//
//  Design: dark anodized-metal body (near-black, high metalness) with neon cyan
//  elastic bands and glowing tip/pouch accents.  No decorative rings or collars —
//  the silhouette is the statement.
//
//  Rubber-band geometry (two SCNCylinder nodes) is updated every frame to reflect
//  the player's current drag state via `updateDrag(offset:maxDrag:)`.
//
//  All positions are in the node's local coordinate space (camera space):
//    +X right, +Y up, -Z into scene (camera looks in -Z direction).
//

import SceneKit
import UIKit

// MARK: - SlingshotNode

final class SlingshotNode: SCNNode {

    // MARK: Geometry constants (camera-local space, metres)

    /// Position of the fork's centre in camera space.
    private static let forkCenter = SCNVector3(0, -0.09, -0.26)

    // Positions in forkRoot's local frame:
    /// Bottom of the grip.
    private static let stemBottom = SCNVector3(0, -0.058, 0)
    /// Branch point where stem meets the two tines.
    private static let branch     = SCNVector3(0,  0.006, 0)
    /// Left tine tip (slight −Z offset adds depth cue).
    private static let leftTip    = SCNVector3(-0.052,  0.068, -0.005)
    /// Right tine tip.
    private static let rightTip   = SCNVector3( 0.052,  0.068, -0.005)

    /// Resting pull-point position.
    private static let neutralPull = SCNVector3(0, 0.042, 0.0)

    /// Maximum pull depth toward the camera (+Z) at full drag.
    private static let maxPullDepth:   Float = 0.080
    /// Maximum lateral shift at full drag.
    private static let maxPullLateral: Float = 0.022
    /// Small downward shift at full drag (adds perspective to the pull).
    private static let maxPullDown:    Float = 0.012

    // MARK: Child nodes

    private let forkRoot:      SCNNode
    private let leftBandNode:  SCNNode
    private let rightBandNode: SCNNode
    private let pouchNode:     SCNNode

    /// Current pull-point position in forkRoot's local frame.
    private var pullPoint: SCNVector3

    // MARK: - Init

    override init() {
        forkRoot      = SCNNode()
        leftBandNode  = SCNNode()
        rightBandNode = SCNNode()
        pouchNode     = SCNNode()
        pullPoint     = SlingshotNode.neutralPull
        super.init()

        forkRoot.position = SlingshotNode.forkCenter
        addChildNode(forkRoot)

        setupFork()
        setupBands()
        setupPouch()
        updateBands()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented for SlingshotNode") }

    // MARK: - Public API

    /// Update rubber-band and pouch position to match the current drag.
    /// - Parameters:
    ///   - offset: SwiftUI dragOffset (positive width = right, positive height = pulled down).
    ///   - maxDrag: The view's maxDragDistance (points) used for normalisation.
    func updateDrag(offset: CGSize, maxDrag: CGFloat) {
        let nx = Float(offset.width  / maxDrag)   // −1…1 lateral
        let ny = Float(offset.height / maxDrag)   // 0…1 pull-back amount

        pullPoint = SCNVector3(
             nx * SlingshotNode.maxPullLateral,
             SlingshotNode.neutralPull.y - ny * SlingshotNode.maxPullDown,
             ny * SlingshotNode.maxPullDepth          // +Z = toward camera
        )
        updateBands()
        pouchNode.isHidden = false
    }

    /// Snap rubber bands and pouch back to the neutral (un-pulled) position.
    func resetDrag() {
        pullPoint = SlingshotNode.neutralPull
        updateBands()
        pouchNode.isHidden = true
    }

    // MARK: - Private: fork geometry

    private func setupFork() {
        // Single dark anodized-metal material — near-black, high metalness, slight sheen.
        let bodyMat = pbrMat(
            UIColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1),
            roughness: 0.28, metalness: 0.85
        )
        // Neon cyan glow cap on each tine tip (accent + status indicator).
        let tipMat = pbrMat(
            UIColor(red: 0.10, green: 1.00, blue: 0.82, alpha: 1),
            roughness: 0.25, metalness: 0.10,
            emission: UIColor(red: 0.04, green: 0.48, blue: 0.36, alpha: 1)
        )

        // ── Stem ──────────────────────────────────────────────────────────────
        forkRoot.addChildNode(
            cylinderBetween(SlingshotNode.stemBottom, SlingshotNode.branch,
                            radius: 0.008, material: bodyMat)
        )

        // ── Tines ─────────────────────────────────────────────────────────────
        forkRoot.addChildNode(
            cylinderBetween(SlingshotNode.branch, SlingshotNode.leftTip,
                            radius: 0.007, material: bodyMat)
        )
        forkRoot.addChildNode(
            cylinderBetween(SlingshotNode.branch, SlingshotNode.rightTip,
                            radius: 0.007, material: bodyMat)
        )

        // ── Neon tip caps ──────────────────────────────────────────────────────
        for tip in [SlingshotNode.leftTip, SlingshotNode.rightTip] {
            let dot = SCNNode(geometry: SCNSphere(radius: 0.010))
            dot.geometry!.materials = [tipMat]
            dot.castsShadow = false
            dot.position    = tip
            forkRoot.addChildNode(dot)
        }
    }

    // MARK: - Private: rubber bands

    private func setupBands() {
        // Slim neon cyan elastic band with soft emissive glow.
        let bandMat = pbrMat(
            UIColor(red: 0.08, green: 0.92, blue: 0.70, alpha: 1),
            roughness: 0.50, metalness: 0.0,
            emission: UIColor(red: 0.03, green: 0.38, blue: 0.26, alpha: 1)
        )

        let geoL = SCNCylinder(radius: 0.0028, height: 0.01)
        geoL.materials = [bandMat]
        leftBandNode.geometry = geoL

        let geoR = SCNCylinder(radius: 0.0028, height: 0.01)
        geoR.materials = [bandMat]
        rightBandNode.geometry = geoR

        leftBandNode.castsShadow  = false
        rightBandNode.castsShadow = false

        forkRoot.addChildNode(leftBandNode)
        forkRoot.addChildNode(rightBandNode)
    }

    // MARK: - Private: pouch

    private func setupPouch() {
        // Single glowing neon sphere — minimal and clean.
        let neonMat = pbrMat(
            UIColor(red: 0.08, green: 0.90, blue: 0.66, alpha: 1),
            roughness: 0.30, metalness: 0.08,
            emission: UIColor(red: 0.03, green: 0.36, blue: 0.24, alpha: 1)
        )

        let sphere = SCNNode(geometry: SCNSphere(radius: 0.012))
        sphere.geometry!.materials = [neonMat]
        sphere.castsShadow = false
        pouchNode.addChildNode(sphere)

        pouchNode.castsShadow = false
        pouchNode.isHidden    = true    // shown only while dragging
        pouchNode.position    = SlingshotNode.neutralPull
        forkRoot.addChildNode(pouchNode)
    }

    // MARK: - Private: band update

    private func updateBands() {
        alignCylinder(leftBandNode,  from: SlingshotNode.leftTip,  to: pullPoint)
        alignCylinder(rightBandNode, from: SlingshotNode.rightTip, to: pullPoint)
        pouchNode.position = pullPoint
    }

    // MARK: - Geometry helpers

    /// Build a cylinder SCNNode oriented and scaled to span two local points.
    private func cylinderBetween(_ a: SCNVector3, _ b: SCNVector3,
                                  radius: CGFloat, material: SCNMaterial) -> SCNNode {
        let node = SCNNode()
        node.geometry = SCNCylinder(radius: radius, height: 0.01)
        node.geometry!.materials = [material]
        alignCylinder(node, from: a, to: b)
        return node
    }

    /// Reposition and reorient `node` (SCNCylinder) so it spans `from → to` in local space.
    private func alignCylinder(_ node: SCNNode, from a: SCNVector3, to b: SCNVector3) {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let dz = b.z - a.z
        let len = sqrt(dx*dx + dy*dy + dz*dz)
        guard len > 1e-6 else { return }

        // Height
        if let cyl = node.geometry as? SCNCylinder {
            cyl.height = CGFloat(len)
        }

        // Midpoint
        node.position = SCNVector3((a.x + b.x) * 0.5,
                                   (a.y + b.y) * 0.5,
                                   (a.z + b.z) * 0.5)

        // Rotation: align cylinder's Y-axis to the direction vector.
        let dir = SCNVector3(dx/len, dy/len, dz/len)
        let yAxis = SCNVector3(0, 1, 0)
        let cross = SCNVector3(
            yAxis.y * dir.z - yAxis.z * dir.y,
            yAxis.z * dir.x - yAxis.x * dir.z,
            yAxis.x * dir.y - yAxis.y * dir.x
        )
        let dot      = yAxis.x * dir.x + yAxis.y * dir.y + yAxis.z * dir.z
        let angle    = acos(max(-1, min(1, dot)))
        let crossLen = sqrt(cross.x*cross.x + cross.y*cross.y + cross.z*cross.z)

        if crossLen > 1e-6 {
            node.rotation = SCNVector4(cross.x/crossLen, cross.y/crossLen, cross.z/crossLen, angle)
        } else if dot < 0 {
            // Anti-parallel: 180° flip around any perpendicular axis.
            node.rotation = SCNVector4(1, 0, 0, Float.pi)
        }
    }

    /// Physically-based material helper.
    private func pbrMat(_ color: UIColor, roughness: Float, metalness: Float,
                        emission: UIColor = .black) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents   = color
        m.roughness.contents = NSNumber(value: roughness)
        m.metalness.contents = NSNumber(value: metalness)
        m.emission.contents  = emission
        m.lightingModel      = .physicallyBased
        return m
    }
}
