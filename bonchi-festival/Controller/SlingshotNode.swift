//
//  SlingshotNode.swift
//  bonchi-festival
//
//  iOS Controller: SCNNode that renders a 3-D Y-shaped slingshot in the AR scene.
//  The node must be added as a child of `arView.pointOfView` so it stays fixed
//  in the camera's view frustum regardless of how the device moves.
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
    private static let forkCenter = SCNVector3(0, -0.12, -0.28)

    // Positions relative to forkCenter (i.e. in forkRoot's local frame):
    /// Bottom of the stem.
    private static let stemBottom = SCNVector3(0, -0.050, 0)
    /// Branch point where stem meets the two tines.
    private static let branch     = SCNVector3(0,  0.010, 0)
    /// Left tine tip.
    private static let leftTip    = SCNVector3(-0.035,  0.055, 0)
    /// Right tine tip.
    private static let rightTip   = SCNVector3( 0.035,  0.055, 0)

    /// Resting pull-point position (pouch hangs just below tine level).
    private static let neutralPull = SCNVector3(0, 0.042, 0.0)

    /// Maximum pull depth toward the camera (+Z) at full drag.
    private static let maxPullDepth:   Float = 0.080
    /// Maximum lateral shift left/right at full drag.
    private static let maxPullLateral: Float = 0.025
    /// Small downward shift at full drag (adds perspective to the pull).
    private static let maxPullDown:    Float = 0.014

    // MARK: Child nodes

    private let forkRoot: SCNNode
    private let leftBandNode:  SCNNode
    private let rightBandNode: SCNNode

    /// The visible net-pouch (torus ring + spokes) at the pull point.
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
        let woodMat = pbrMat(
            UIColor(red: 0.48, green: 0.24, blue: 0.05, alpha: 1),
            roughness: 0.82, metalness: 0.04
        )

        // Stem
        forkRoot.addChildNode(
            cylinderBetween(SlingshotNode.stemBottom, SlingshotNode.branch,
                            radius: 0.007, material: woodMat)
        )
        // Left tine
        forkRoot.addChildNode(
            cylinderBetween(SlingshotNode.branch, SlingshotNode.leftTip,
                            radius: 0.006, material: woodMat)
        )
        // Right tine
        forkRoot.addChildNode(
            cylinderBetween(SlingshotNode.branch, SlingshotNode.rightTip,
                            radius: 0.006, material: woodMat)
        )

        // Decorative sphere caps on each tine tip
        for tip in [SlingshotNode.leftTip, SlingshotNode.rightTip] {
            let cap = SCNNode(geometry: SCNSphere(radius: 0.009))
            cap.geometry!.materials = [woodMat]
            cap.position = tip
            forkRoot.addChildNode(cap)
        }
    }

    // MARK: - Private: rubber bands

    private func setupBands() {
        let bandMat = pbrMat(
            UIColor(red: 1.0, green: 0.50, blue: 0.0, alpha: 1),
            roughness: 0.90, metalness: 0.0
        )

        let geoL = SCNCylinder(radius: 0.003, height: 0.01)
        geoL.materials = [bandMat]
        leftBandNode.geometry = geoL

        let geoR = SCNCylinder(radius: 0.003, height: 0.01)
        geoR.materials = [bandMat]
        rightBandNode.geometry = geoR

        leftBandNode.castsShadow  = false
        rightBandNode.castsShadow = false

        forkRoot.addChildNode(leftBandNode)
        forkRoot.addChildNode(rightBandNode)
    }

    // MARK: - Private: pouch (net ball)

    private func setupPouch() {
        let rimMat = pbrMat(
            UIColor(red: 0.20, green: 0.85, blue: 0.35, alpha: 1),
            roughness: 0.65, metalness: 0.10,
            emission: UIColor(red: 0.02, green: 0.20, blue: 0.04, alpha: 1)
        )
        let meshMat = pbrMat(
            UIColor(red: 0.35, green: 0.98, blue: 0.50, alpha: 0.90),
            roughness: 0.75, metalness: 0.0
        )
        meshMat.isDoubleSided = true

        // Outer torus rim
        let torus = SCNTorus(ringRadius: 0.018, pipeRadius: 0.003)
        torus.materials = [rimMat]
        let torusNode = SCNNode(geometry: torus)
        torusNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)   // face +Z (camera forward)
        pouchNode.addChildNode(torusNode)

        // 8 radial spokes forming the net mesh
        for i in 0..<8 {
            let angle = Float(i) * .pi / 4
            let spoke = SCNNode(
                geometry: SCNBox(width: 0.034, height: 0.001, length: 0.001, chamferRadius: 0)
            )
            spoke.geometry!.materials = [meshMat]
            spoke.eulerAngles = SCNVector3(0, 0, angle)
            pouchNode.addChildNode(spoke)
        }

        // Two inner concentric rings
        for r: CGFloat in [0.008, 0.014] {
            let ring = SCNNode(geometry: SCNTorus(ringRadius: r, pipeRadius: 0.0015))
            ring.geometry!.materials = [rimMat]
            ring.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
            pouchNode.addChildNode(ring)
        }

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
