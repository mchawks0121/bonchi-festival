//
//  SlingshotNode.swift
//  bonchi-festival
//
//  iOS Controller: SCNNode that renders a 3-D Y-shaped slingshot in the AR scene.
//  The node must be added as a child of `arView.pointOfView` so it stays fixed
//  in the camera's view frustum regardless of how the device moves.
//
//  Design: dark rosewood body with brushed-silver metal accents (grip rings,
//  branch collar, tine tips) and neon cyan rubber bands with emissive glow.
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
    private static let forkCenter = SCNVector3(0, -0.10, -0.27)

    // Positions relative to forkCenter (i.e. in forkRoot's local frame):
    /// Bottom of the stem (grip end).
    private static let stemBottom = SCNVector3(0, -0.060,  0)
    /// Branch point where stem meets the two tines.
    private static let branch     = SCNVector3(0,  0.010,  0)
    /// Left tine tip.
    private static let leftTip    = SCNVector3(-0.046,  0.072, 0)
    /// Right tine tip.
    private static let rightTip   = SCNVector3( 0.046,  0.072, 0)

    /// Resting pull-point position (pouch hangs just below tine level).
    private static let neutralPull = SCNVector3(0, 0.044, 0.0)

    /// Maximum pull depth toward the camera (+Z) at full drag.
    private static let maxPullDepth:   Float = 0.080
    /// Maximum lateral shift left/right at full drag.
    private static let maxPullLateral: Float = 0.022
    /// Small downward shift at full drag (adds perspective to the pull).
    private static let maxPullDown:    Float = 0.012

    // MARK: Child nodes

    private let forkRoot: SCNNode
    private let leftBandNode:  SCNNode
    private let rightBandNode: SCNNode

    /// The visible net-pouch (glowing sphere + rim) at the pull point.
    private let pouchNode: SCNNode

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
        // Dark rosewood body — polished, slightly metallic sheen
        let woodMat = pbrMat(
            UIColor(red: 0.18, green: 0.08, blue: 0.04, alpha: 1),
            roughness: 0.42, metalness: 0.14
        )
        // Brushed silver metal for accents (collar, grip rings)
        let metalMat = pbrMat(
            UIColor(red: 0.74, green: 0.78, blue: 0.84, alpha: 1),
            roughness: 0.18, metalness: 0.92
        )
        // Neon cyan glowing caps on the tine tips
        let tipMat = pbrMat(
            UIColor(red: 0.12, green: 1.0, blue: 0.78, alpha: 1),
            roughness: 0.30, metalness: 0.15,
            emission: UIColor(red: 0.05, green: 0.52, blue: 0.40, alpha: 1)
        )

        // ── Stem ──────────────────────────────────────────────────────────────
        forkRoot.addChildNode(
            cylinderBetween(SlingshotNode.stemBottom, SlingshotNode.branch,
                            radius: 0.009, material: woodMat)
        )

        // Three brushed-metal grip rings distributed along the handle
        let stemRange = SlingshotNode.branch.y - SlingshotNode.stemBottom.y
        for frac: Float in [0.20, 0.50, 0.80] {
            let y = SlingshotNode.stemBottom.y + frac * stemRange
            let gripRing = SCNNode(geometry: SCNTorus(ringRadius: 0.0115, pipeRadius: 0.0022))
            gripRing.geometry!.materials = [metalMat]
            gripRing.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
            gripRing.position    = SCNVector3(0, y, 0)
            gripRing.castsShadow = false
            forkRoot.addChildNode(gripRing)
        }

        // Metal collar where stem meets tines (structural accent)
        let collar = SCNNode(geometry: SCNTorus(ringRadius: 0.0135, pipeRadius: 0.0032))
        collar.geometry!.materials = [metalMat]
        collar.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        collar.position    = SlingshotNode.branch
        collar.castsShadow = false
        forkRoot.addChildNode(collar)

        // ── Tines ─────────────────────────────────────────────────────────────
        forkRoot.addChildNode(
            cylinderBetween(SlingshotNode.branch, SlingshotNode.leftTip,
                            radius: 0.007, material: woodMat)
        )
        forkRoot.addChildNode(
            cylinderBetween(SlingshotNode.branch, SlingshotNode.rightTip,
                            radius: 0.007, material: woodMat)
        )

        // ── Neon tip caps on each tine ─────────────────────────────────────────
        for tip in [SlingshotNode.leftTip, SlingshotNode.rightTip] {
            let cap = SCNNode(geometry: SCNSphere(radius: 0.011))
            cap.geometry!.materials = [tipMat]
            cap.castsShadow = false
            cap.position = tip
            forkRoot.addChildNode(cap)
        }
    }

    // MARK: - Private: rubber bands

    private func setupBands() {
        // Neon cyan bands with emissive glow (matches tine-tip colour)
        let bandMat = pbrMat(
            UIColor(red: 0.10, green: 0.95, blue: 0.72, alpha: 1),
            roughness: 0.55, metalness: 0.0,
            emission: UIColor(red: 0.04, green: 0.40, blue: 0.28, alpha: 1)
        )

        let geoL = SCNCylinder(radius: 0.0032, height: 0.01)
        geoL.materials = [bandMat]
        leftBandNode.geometry = geoL

        let geoR = SCNCylinder(radius: 0.0032, height: 0.01)
        geoR.materials = [bandMat]
        rightBandNode.geometry = geoR

        leftBandNode.castsShadow  = false
        rightBandNode.castsShadow = false

        forkRoot.addChildNode(leftBandNode)
        forkRoot.addChildNode(rightBandNode)
    }

    // MARK: - Private: pouch

    private func setupPouch() {
        // Glowing neon sphere + rim ring — matches band colour
        let neonMat = pbrMat(
            UIColor(red: 0.10, green: 0.92, blue: 0.68, alpha: 1),
            roughness: 0.38, metalness: 0.10,
            emission: UIColor(red: 0.04, green: 0.38, blue: 0.26, alpha: 1)
        )

        let sphere = SCNNode(geometry: SCNSphere(radius: 0.013))
        sphere.geometry!.materials = [neonMat]
        sphere.castsShadow = false
        pouchNode.addChildNode(sphere)

        let rim = SCNNode(geometry: SCNTorus(ringRadius: 0.017, pipeRadius: 0.0026))
        rim.geometry!.materials = [neonMat]
        rim.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        rim.castsShadow = false
        pouchNode.addChildNode(rim)

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
