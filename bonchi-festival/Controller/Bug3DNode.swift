//
//  Bug3DNode.swift
//  bonchi-festival
//
//  iOS Controller: SceneKit 3-D node that visually represents one AR bug.
//
//  3-D models are loaded from USDZ files obtained from Apple's AR Quick Look gallery:
//    https://developer.apple.com/jp/augmented-reality/quick-look/
//
//  Model mapping (download these USDZ files and add them to the Xcode project):
//    • butterfly — toy_biplane.usdz  (flying toy; represents the fast Null bug)
//    • beetle    — gramophone.usdz   (dome shell shape; represents the Virus bug)
//    • stag      — toy_drummer.usdz  (animated character; represents the Glitch bug)
//
//  If the USDZ file for a given bug type is not found in the app bundle, the node
//  falls back to a procedural PBR geometry so the game remains fully playable during
//  development before the assets are added to the project.
//
//  All nodes hover vertically and have per-type animations.
//  Calling captured() triggers a glitch-flash / fade-out dismissal animation.
//

import SceneKit
import UIKit

// MARK: - Bug3DNode

final class Bug3DNode: SCNNode {

    let bugType: BugType

    /// True when a USDZ model was successfully loaded from the app bundle.
    private var usdzLoaded = false

    // MARK: - Asset preloading (immediacy 即時性)

    /// Per-type scale factors that produce a visually appropriate size at the
    /// 2 m reference distance used by ARGameView.Coordinator.
    /// Each USDZ from the Apple Quick Look gallery has a different intrinsic size, so
    /// per-type constants are needed rather than a single global value.
    /// Exhaustive switch ensures a new BugType will cause a compile error rather than
    /// silently rendering at the wrong scale.
    private static func usdzScale(for type: BugType) -> Float {
        switch type {
        case .butterfly: return 0.005   // toy_biplane — compact flying toy
        case .beetle:    return 0.004   // gramophone  — dome-shaped object
        case .stag:      return 0.004   // toy_drummer — animated character
        }
    }

    /// Thread safety for the preload cache and in-progress tracking.
    private static let cacheLock = NSLock()
    /// Keyed by BugType.rawValue; populated by preloadAssets() before any bug spawns.
    private static var sceneCache: [String: SCNScene] = [:]
    /// Tracks assets currently being loaded so concurrent callers skip duplicate I/O.
    private static var loadingInProgress = Set<String>()

    /// Loads all three USDZ scenes off the main thread so that the first bug
    /// instantiation can clone from memory rather than reading from disk.
    /// Call this once early in the app lifecycle (e.g. from ARGameView.makeUIView).
    static func preloadAssets() {
        let mapping: [(BugType, String)] = [
            (.butterfly, "toy_biplane"),
            (.beetle,    "gramophone"),
            (.stag,      "toy_drummer"),
        ]
        DispatchQueue.global(qos: .userInitiated).async {
            for (type, name) in mapping {
                // Under the lock: skip if already cached or currently loading.
                // Marking in-progress inside the lock prevents duplicate I/O.
                cacheLock.lock()
                let skip = sceneCache[type.rawValue] != nil
                              || loadingInProgress.contains(type.rawValue)
                if !skip { loadingInProgress.insert(type.rawValue) }
                cacheLock.unlock()
                guard !skip else { continue }

                guard let url = Bundle.main.url(forResource: name, withExtension: "usdz"),
                      let scene = try? SCNScene(url: url, options: [
                          SCNSceneSource.LoadingOption.animationImportPolicy:
                              SCNSceneSource.AnimationImportPolicy.playRepeatedly
                      ]) else {
                    // Load failed — clear the in-progress marker so a retry is possible.
                    cacheLock.lock()
                    loadingInProgress.remove(type.rawValue)
                    cacheLock.unlock()
                    continue
                }

                cacheLock.lock()
                sceneCache[type.rawValue] = scene
                loadingInProgress.remove(type.rawValue)
                cacheLock.unlock()
            }
        }
    }

    init(type: BugType) {
        self.bugType = type
        super.init()
        usdzLoaded = loadUSDZModel()
        if !usdzLoaded { setupGeometry() }
        startAnimations()
    }

    required init?(coder: NSCoder) { fatalError("Bug3DNode does not support NSCoding; use init(type:) instead") }

    // MARK: - Public

    /// Entangle-struggle-dissolve animation played when the bug is captured by the net.
    ///
    /// Phases:
    /// 1. **Impact jolt** — sudden scale-up as the net lands.
    /// 2. **Violent thrash** — multi-axis spin with shrink/swell cycles (trying to escape).
    /// 3. **Net constricts** — rapid shrink toward zero as the bug is bound.
    /// 4. **Glitch blinks** — digital corruption flicker.
    /// 5. **Dissolve** — final fade-out and removal.
    func captured() {
        removeAllActions()

        // 1. Impact jolt
        let impact = SCNAction.scale(to: 1.30, duration: 0.04)

        // 2. Violent thrash: multi-axis struggle (net wraps around the bug)
        let spinY1  = SCNAction.rotateBy(x: 0, y: CGFloat(.pi * 1.8), z: 0, duration: 0.10)
        let spinY2  = SCNAction.rotateBy(x: 0, y: CGFloat(-.pi * 1.2), z: 0, duration: 0.08)
        let spinY3  = SCNAction.rotateBy(x: 0, y: CGFloat(.pi * 0.7), z: 0, duration: 0.07)
        let spinX1  = SCNAction.rotateBy(x: CGFloat(.pi * 0.55), y: 0, z: 0, duration: 0.09)
        let spinX2  = SCNAction.rotateBy(x: CGFloat(-.pi * 0.40), y: 0, z: 0, duration: 0.08)
        let spinZ1  = SCNAction.rotateBy(x: 0, y: 0, z: CGFloat(.pi * 0.65), duration: 0.09)
        let spinZ2  = SCNAction.rotateBy(x: 0, y: 0, z: CGFloat(-.pi * 0.45), duration: 0.07)
        let swell1  = SCNAction.scale(to: 0.78, duration: 0.10)
        let swell2  = SCNAction.scale(to: 1.18, duration: 0.08)
        let swell3  = SCNAction.scale(to: 0.62, duration: 0.07)

        let thrash = SCNAction.group([
            SCNAction.sequence([spinY1, spinY2, spinY3]),
            SCNAction.sequence([spinX1, spinX2]),
            SCNAction.sequence([spinZ1, spinZ2]),
            SCNAction.sequence([swell1, swell2, swell3])
        ])

        // 3. Net constricts: rapid shrink-down as the bug is fully bound
        let constrict = SCNAction.scale(to: 0.22, duration: 0.26)
        constrict.timingMode = .easeIn

        // 4. Digital glitch blinks (corruption theme)
        let blinkDur: TimeInterval = 0.055
        let blink = SCNAction.sequence([
            SCNAction.fadeOpacity(to: 0.0, duration: blinkDur * 0.35),
            SCNAction.fadeOpacity(to: 0.85, duration: blinkDur * 0.25),
            SCNAction.fadeOpacity(to: 0.0, duration: blinkDur * 0.20),
            SCNAction.fadeOpacity(to: 0.70, duration: blinkDur * 0.20)
        ])

        // 5. Final dissolve
        let dissolve = SCNAction.fadeOut(duration: 0.22)
        dissolve.timingMode = .easeIn

        runAction(SCNAction.sequence([impact, thrash, constrict, blink, dissolve,
                                      SCNAction.removeFromParentNode()]))
    }

    // MARK: - Private: USDZ loading

    /// Attempts to load the USDZ model for this bug type from the preload cache.
    /// Returns `true` if a cached scene was found and cloned successfully.
    /// Returns `false` when the cache is empty (preload still in progress or asset
    /// not available); the caller then builds procedural geometry as a fallback.
    private func loadUSDZModel() -> Bool {
        Bug3DNode.cacheLock.lock()
        let cached = Bug3DNode.sceneCache[bugType.rawValue]
        Bug3DNode.cacheLock.unlock()

        guard let cachedScene = cached else { return false }

        // Clone the cached scene's root so each bug gets its own independent
        // node hierarchy and animation state.
        let modelRoot = cachedScene.rootNode.clone()
        let s = Bug3DNode.usdzScale(for: bugType)
        modelRoot.scale = SCNVector3(s, s, s)
        // Ensure all descendants cast shadows for ground contact realism.
        modelRoot.enumerateChildNodes { node, _ in
            node.castsShadow = true
        }
        addChildNode(modelRoot)
        return true
    }

    // MARK: - Private: geometry

    private func setupGeometry() {
        switch bugType {
        case .butterfly: setupButterfly()
        case .beetle:    setupBeetle()
        case .stag:      setupStag()
        }
    }

    /// Butterfly (蝶) — slender abdomen, 4 translucent wings, ball-tipped antennae.
    /// Emissive tint: electric cyan-blue (Null Bug / undefined reference theme).
    private func setupButterfly() {
        // Abdomen: slender vertical capsule — faint cyan emission (null-reference glow)
        let bodyGeo = SCNCapsule(capRadius: 0.009, height: 0.048)
        bodyGeo.materials = [pbr(UIColor(red: 0.10, green: 0.05, blue: 0.01, alpha: 1),
                                  roughness: 0.65, metalness: 0.02,
                                  emission: UIColor(red: 0.0, green: 0.14, blue: 0.35, alpha: 1))]
        geometry = bodyGeo

        // Head
        addSphere(radius: 0.011,
                  at: SCNVector3(0, 0.033, 0),
                  mat: pbr(UIColor(red: 0.10, green: 0.05, blue: 0.01, alpha: 1),
                            roughness: 0.60, metalness: 0.02,
                            emission: UIColor(red: 0.0, green: 0.10, blue: 0.28, alpha: 1)))

        // Upper wings (larger, monarch orange)
        let uGeo = SCNPlane(width: 0.095, height: 0.070)
        uGeo.materials = [wingMat(UIColor(red: 0.95, green: 0.50, blue: 0.05, alpha: 0.90),
                                   emit: UIColor(red: 0.22, green: 0.08, blue: 0.0, alpha: 0.22))]
        // Lower wings (smaller, darker)
        let lGeo = SCNPlane(width: 0.065, height: 0.052)
        lGeo.materials = [wingMat(UIColor(red: 0.82, green: 0.35, blue: 0.05, alpha: 0.88),
                                   emit: UIColor(red: 0.18, green: 0.06, blue: 0.0, alpha: 0.18))]

        for sign: Float in [-1.0, 1.0] {
            // Upper wing pivot at body edge; wing extends outward
            let uPivot = SCNNode()
            uPivot.position = SCNVector3(sign * 0.009, 0.008, 0)
            uPivot.name = sign > 0 ? "uwR" : "uwL"
            let uWing = SCNNode(geometry: uGeo)
            uWing.position    = SCNVector3(sign * 0.048, 0.006, 0)
            uWing.eulerAngles = SCNVector3(0, 0, sign * Float.pi / 14)
            uPivot.addChildNode(uWing)
            addChildNode(uPivot)

            // Lower wing pivot slightly below upper
            let lPivot = SCNNode()
            lPivot.position = SCNVector3(sign * 0.007, -0.004, 0)
            lPivot.name = sign > 0 ? "lwR" : "lwL"
            let lWing = SCNNode(geometry: lGeo)
            lWing.position    = SCNVector3(sign * 0.033, -0.010, 0)
            lWing.eulerAngles = SCNVector3(0, 0, sign * Float.pi / 16)
            lPivot.addChildNode(lWing)
            addChildNode(lPivot)
        }

        // Antennae: thin shafts with ball tips
        let aMat = pbr(UIColor(red: 0.10, green: 0.05, blue: 0.01, alpha: 1),
                        roughness: 0.60, metalness: 0.02)
        for sign: Float in [-1.0, 1.0] {
            let shaft = SCNCylinder(radius: 0.0018, height: 0.036)
            shaft.materials = [aMat]
            let shaftNode = SCNNode(geometry: shaft)
            shaftNode.position    = SCNVector3(sign * 0.010, 0.051, 0)
            shaftNode.eulerAngles = SCNVector3(0, 0, sign * Float.pi / 7)
            let tipGeo = SCNSphere(radius: 0.004)
            tipGeo.materials = [aMat]
            let tip = SCNNode(geometry: tipGeo)
            tip.position = SCNVector3(0, 0.018, 0)
            shaftNode.addChildNode(tip)
            addChildNode(shaftNode)
        }
    }

    /// Beetle (甲虫) — glossy dome elytra, suture, compound eyes, 6 segmented legs.
    /// Emissive tint: toxic green (Virus Bug / self-replicating runtime error theme).
    private func setupBeetle() {
        let shellMat = pbr(UIColor(red: 0.55, green: 0.08, blue: 0.08, alpha: 1),
                            roughness: 0.14, metalness: 0.62,
                            emission: UIColor(red: 0.0, green: 0.18, blue: 0.04, alpha: 1))

        // Main body: sphere shaped into a flattened dome
        let bodyGeo = SCNSphere(radius: 0.040)
        bodyGeo.materials = [shellMat]
        let bodyNode = SCNNode(geometry: bodyGeo)
        bodyNode.scale = SCNVector3(1.05, 0.68, 1.22)   // flatten Y, elongate Z
        addChildNode(bodyNode)

        // Elytra suture (centre split line down the back)
        let sutGeo = SCNCylinder(radius: 0.0028, height: 0.074)
        sutGeo.materials = [pbr(UIColor(red: 0.18, green: 0.02, blue: 0.02, alpha: 1),
                                  roughness: 0.08, metalness: 0.72)]
        let suture = SCNNode(geometry: sutGeo)
        suture.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        suture.position    = SCNVector3(0, 0.022, 0)
        addChildNode(suture)

        // Thorax
        addSphere(radius: 0.022,
                  at: SCNVector3(0, 0.006, -0.052),
                  mat: pbr(UIColor(red: 0.40, green: 0.05, blue: 0.05, alpha: 1),
                            roughness: 0.20, metalness: 0.55))

        // Head
        addSphere(radius: 0.018,
                  at: SCNVector3(0, 0.002, -0.076),
                  mat: pbr(UIColor(red: 0.30, green: 0.04, blue: 0.04, alpha: 1),
                            roughness: 0.28, metalness: 0.45))

        // Compound eyes
        let eyeMat = pbr(UIColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1),
                          roughness: 0.04, metalness: 0.08)
        for sign: Float in [-1.0, 1.0] {
            addSphere(radius: 0.007, at: SCNVector3(sign * 0.015, 0.010, -0.080), mat: eyeMat)
        }

        // 6 legs (3 pairs: front, middle, rear)
        let legMat = pbr(UIColor(red: 0.22, green: 0.04, blue: 0.04, alpha: 1),
                          roughness: 0.40, metalness: 0.28)
        for (legZ, angle): (Float, Float) in
                [(0.010, Float.pi / 2.2), (-0.025, Float.pi / 2.5), (-0.052, Float.pi / 2.3)] {
            for sign: Float in [-1.0, 1.0] {
                addLeg(at: SCNVector3(sign * 0.042, -0.012, legZ),
                       sign: sign, mat: legMat, outAngle: angle)
            }
        }

        // Short antennae
        let aMat = pbr(UIColor(red: 0.18, green: 0.03, blue: 0.03, alpha: 1),
                        roughness: 0.50, metalness: 0.20)
        for sign: Float in [-1.0, 1.0] {
            let shaft = SCNCylinder(radius: 0.0016, height: 0.028)
            shaft.materials = [aMat]
            let shaftNode = SCNNode(geometry: shaft)
            shaftNode.position    = SCNVector3(sign * 0.010, 0.008, -0.080)
            shaftNode.eulerAngles = SCNVector3(-Float.pi / 8, 0, sign * Float.pi / 6)
            let tipGeo = SCNSphere(radius: 0.003)
            tipGeo.materials = [aMat]
            let tip = SCNNode(geometry: tipGeo)
            tip.position = SCNVector3(0, 0.014, 0)
            shaftNode.addChildNode(tip)
            addChildNode(shaftNode)
        }
    }

    /// Stag beetle (クワガタ) — dark metallic body, prominent mandibles (大顎), 6 legs.
    /// Emissive tint: hot red/orange (Glitch Bug / critical data corruption theme).
    private func setupStag() {
        let darkMat = pbr(UIColor(red: 0.14, green: 0.08, blue: 0.02, alpha: 1),
                           roughness: 0.20, metalness: 0.65,
                           emission: UIColor(red: 0.28, green: 0.05, blue: 0.0, alpha: 1))

        // Abdomen: vertical capsule
        let bodyGeo = SCNCapsule(capRadius: 0.028, height: 0.068)
        bodyGeo.materials = [darkMat]
        geometry = bodyGeo

        // Thorax (pronotum)
        addSphere(radius: 0.024,
                  at: SCNVector3(0, 0.050, 0),
                  mat: pbr(UIColor(red: 0.16, green: 0.09, blue: 0.02, alpha: 1),
                            roughness: 0.18, metalness: 0.62))

        // Head
        let headMat = pbr(UIColor(red: 0.18, green: 0.10, blue: 0.02, alpha: 1),
                           roughness: 0.22, metalness: 0.58)
        addSphere(radius: 0.022, at: SCNVector3(0, 0.082, 0), mat: headMat)

        // Eyes
        let eyeMat = pbr(UIColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1),
                          roughness: 0.04, metalness: 0.08)
        for sign: Float in [-1.0, 1.0] {
            addSphere(radius: 0.006, at: SCNVector3(sign * 0.018, 0.090, 0.014), mat: eyeMat)
        }

        // Mandibles (大顎) — the defining stag beetle feature
        let mandMat = pbr(UIColor(red: 0.22, green: 0.12, blue: 0.03, alpha: 1),
                           roughness: 0.25, metalness: 0.50)
        let mandGeo = SCNCapsule(capRadius: 0.005, height: 0.052)
        mandGeo.materials = [mandMat]
        let toothGeo = SCNCone(topRadius: 0, bottomRadius: 0.005, height: 0.013)
        toothGeo.materials = [mandMat]
        for sign: Float in [-1.0, 1.0] {
            let mand = SCNNode(geometry: mandGeo)
            mand.position    = SCNVector3(sign * 0.022, 0.106, 0.010)
            mand.eulerAngles = SCNVector3(Float.pi / 2.2, 0, sign * Float.pi / 8)
            addChildNode(mand)
            // Inner tooth on each mandible
            let tooth = SCNNode(geometry: toothGeo)
            tooth.position    = SCNVector3(sign * 0.006, 0, -0.012)
            tooth.eulerAngles = SCNVector3(-Float.pi / 3, 0, 0)
            mand.addChildNode(tooth)
        }

        // 6 legs (along vertical body Y axis: upper, mid, lower)
        let legMat = pbr(UIColor(red: 0.12, green: 0.07, blue: 0.02, alpha: 1),
                          roughness: 0.35, metalness: 0.35)
        for (legY, angle): (Float, Float) in
                [(0.038, Float.pi / 2.6), (0.008, Float.pi / 2.5), (-0.024, Float.pi / 2.4)] {
            for sign: Float in [-1.0, 1.0] {
                addLeg(at: SCNVector3(sign * 0.030, legY, 0),
                       sign: sign, mat: legMat, outAngle: angle)
            }
        }

        // Elbowed antennae characteristic of stag beetles
        let aMat = pbr(UIColor(red: 0.16, green: 0.08, blue: 0.02, alpha: 1),
                        roughness: 0.55, metalness: 0.20)
        for sign: Float in [-1.0, 1.0] {
            let shaft = SCNCylinder(radius: 0.0018, height: 0.030)
            shaft.materials = [aMat]
            let shaftNode = SCNNode(geometry: shaft)
            shaftNode.position    = SCNVector3(sign * 0.015, 0.090, 0.012)
            shaftNode.eulerAngles = SCNVector3(-Float.pi / 5, 0, sign * Float.pi / 5)
            let tipGeo = SCNSphere(radius: 0.003)
            tipGeo.materials = [aMat]
            let tip = SCNNode(geometry: tipGeo)
            tip.position = SCNVector3(0, 0.015, 0)
            shaftNode.addChildNode(tip)
            addChildNode(shaftNode)
        }
    }

    // MARK: - Shared geometry helpers

    @discardableResult
    private func addSphere(radius: CGFloat, at pos: SCNVector3, mat: SCNMaterial) -> SCNNode {
        let geo = SCNSphere(radius: radius)
        geo.materials = [mat]
        let node = SCNNode(geometry: geo)
        node.position = pos
        addChildNode(node)
        return node
    }

    /// Adds a two-segment leg (upper + lower) at the given attachment point.
    /// `sign` is ±1 for right/left; `outAngle` is the Z-axis splay angle.
    private func addLeg(at origin: SCNVector3, sign: Float, mat: SCNMaterial, outAngle: Float) {
        let upperLen: Float = 0.026
        let lowerLen: Float = 0.022
        let lowerAngle = outAngle + Float.pi / 6

        // Upper segment centered at origin, tilted outward/downward
        let upperGeo = SCNCylinder(radius: 0.0040, height: CGFloat(upperLen))
        upperGeo.materials = [mat]
        let upper = SCNNode(geometry: upperGeo)
        upper.position    = origin
        upper.eulerAngles = SCNVector3(0, 0, sign * outAngle)

        // Lower (shin) segment starts at the knee (end of upper segment)
        let kneeX = origin.x + sign * upperLen * sin(outAngle)
        let kneeY = origin.y - upperLen * cos(outAngle)
        let lowerGeo = SCNCylinder(radius: 0.0030, height: CGFloat(lowerLen))
        lowerGeo.materials = [mat]
        let lower = SCNNode(geometry: lowerGeo)
        lower.position    = SCNVector3(kneeX + sign * (lowerLen / 2) * sin(lowerAngle),
                                       kneeY - (lowerLen / 2) * cos(lowerAngle),
                                       origin.z)
        lower.eulerAngles = SCNVector3(0, 0, sign * lowerAngle)

        addChildNode(upper)
        addChildNode(lower)
    }

    // MARK: - Private: animations

    private func startAnimations() {
        // Start invisible; fade in quickly for immediate presence (即時性).
        opacity = 0
        runAction(SCNAction.fadeIn(duration: 0.25))

        if usdzLoaded {
            // Play all animation tracks baked into the USDZ file.
            enumerateChildNodes { node, _ in
                for key in node.animationKeys {
                    node.animationPlayer(forKey: key)?.play()
                }
            }
            // Slow Y-rotation so the player can see all sides of the model.
            let rotateDuration: Double
            switch bugType {
            case .butterfly: rotateDuration = 9.0
            case .beetle:    rotateDuration = 5.5
            case .stag:      rotateDuration = 7.5
            }
            runAction(SCNAction.repeatForever(
                SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: rotateDuration)
            ), forKey: "rotate")
        } else {
            switch bugType {
            case .butterfly: startButterflyAnimations()
            case .beetle:    startBeetleAnimations()
            case .stag:      startStagAnimations()
            }
        }

        // Primary hover: vertical sine with easeInEaseOut (±1.8 cm, random period).
        let hovDur = Double.random(in: 0.65...0.85)
        let up   = SCNAction.moveBy(x: 0, y: 0.018, z: 0, duration: hovDur)
        let down = SCNAction.moveBy(x: 0, y: -0.018, z: 0, duration: hovDur)
        up.timingMode   = .easeInEaseOut
        down.timingMode = .easeInEaseOut
        runAction(SCNAction.repeatForever(SCNAction.sequence([up, down])), forKey: "hover")

        // Secondary drift: slow square orbit in the horizontal plane adds organic
        // depth and prevents the bug from feeling "glued" to one spot (快適性).
        // The four steps trace a closed square: (+X) → (-Z) → (-X) → (+Z) = origin.
        //   After +X: (R, 0)  → after -Z: (R,-R) → after -X: (0,-R) → after +Z: (0, 0) ✓
        let driftR: CGFloat = 0.010       // 1 cm half-side
        let driftDur = Double.random(in: 6.5...8.5)
        let driftPX = SCNAction.moveBy(x:  driftR, y: 0, z: 0,     duration: driftDur / 4)
        let driftNZ = SCNAction.moveBy(x: 0,     y: 0, z: -driftR, duration: driftDur / 4)
        let driftNX = SCNAction.moveBy(x: -driftR, y: 0, z: 0,     duration: driftDur / 4)
        let driftPZ = SCNAction.moveBy(x: 0,     y: 0, z:  driftR, duration: driftDur / 4)
        for a in [driftPX, driftNZ, driftNX, driftPZ] { a.timingMode = .easeInEaseOut }
        runAction(SCNAction.repeatForever(
            SCNAction.sequence([driftPX, driftNZ, driftNX, driftPZ])
        ), forKey: "drift")
    }

    private func startButterflyAnimations() {
        // Wing flapping: rotate pivot nodes around Z axis (wings sweep up/down).
        // For right wing (dir=+1): rotate +angle lifts the wing upward.
        // For left wing  (dir=−1): rotate −angle lifts the wing upward.
        let flapDur: Double = Double.random(in: 0.12...0.16)
        let angle: CGFloat  = .pi / 2.0

        let wingPairs: [(String, String, CGFloat)] = [("uwR", "lwR", 1.0), ("uwL", "lwL", -1.0)]
        for (uName, lName, dir) in wingPairs {
            if let piv = childNode(withName: uName, recursively: false) {
                let close = SCNAction.rotateBy(x: 0, y: 0, z:  dir * angle, duration: flapDur)
                let open  = SCNAction.rotateBy(x: 0, y: 0, z: -dir * angle, duration: flapDur)
                close.timingMode = .easeInEaseOut
                open.timingMode  = .easeInEaseOut
                piv.runAction(SCNAction.repeatForever(.sequence([close, open])), forKey: "flap")
            }
            if let piv = childNode(withName: lName, recursively: false) {
                let close = SCNAction.rotateBy(x: 0, y: 0, z:  dir * angle * 0.75, duration: flapDur * 1.06)
                let open  = SCNAction.rotateBy(x: 0, y: 0, z: -dir * angle * 0.75, duration: flapDur * 1.06)
                close.timingMode = .easeInEaseOut
                open.timingMode  = .easeInEaseOut
                piv.runAction(SCNAction.repeatForever(.sequence([close, open])), forKey: "flap")
            }
        }

        // Slow body drift so the player sees both wing surfaces
        runAction(SCNAction.repeatForever(
            SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 9.0)
        ), forKey: "drift")
    }

    private func startBeetleAnimations() {
        // Moderate Y-rotation
        runAction(SCNAction.repeatForever(
            SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 5.5)
        ), forKey: "rotate")

        // Side-to-side rock imitating a crawling gait
        let r = SCNAction.rotateBy(x: 0, y: 0, z:  CGFloat.pi / 18, duration: 0.38)
        let l = SCNAction.rotateBy(x: 0, y: 0, z: -CGFloat.pi / 18, duration: 0.38)
        r.timingMode = .easeInEaseOut
        l.timingMode = .easeInEaseOut
        runAction(SCNAction.repeatForever(.sequence([r, l])), forKey: "rock")
    }

    private func startStagAnimations() {
        // Slow, heavy Y-rotation
        runAction(SCNAction.repeatForever(
            SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 7.5)
        ), forKey: "rotate")

        // Slow nod — threat display with mandibles
        let nod  = SCNAction.rotateBy(x:  CGFloat.pi / 22, y: 0, z: 0, duration: 1.4)
        let lift = SCNAction.rotateBy(x: -CGFloat.pi / 22, y: 0, z: 0, duration: 1.4)
        nod.timingMode  = .easeInEaseOut
        lift.timingMode = .easeInEaseOut
        runAction(SCNAction.repeatForever(.sequence([nod, lift])), forKey: "nod")
    }

    // MARK: - PBR material factories

    /// Creates a physically-based material.
    /// The optional `emission` colour adds a faint self-glow, used to convey the
    /// digital-corruption theme on procedural bug bodies (リアルさ).
    private func pbr(_ diffuse: UIColor, roughness: Double, metalness: Double,
                     emission: UIColor = .black) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents   = diffuse
        m.roughness.contents = NSNumber(value: roughness)
        m.metalness.contents = NSNumber(value: metalness)
        m.emission.contents  = emission
        m.lightingModel      = .physicallyBased
        return m
    }

    private func wingMat(_ color: UIColor, emit: UIColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents   = color
        m.emission.contents  = emit
        m.roughness.contents = NSNumber(value: 0.70)
        m.metalness.contents = NSNumber(value: 0.0)
        m.lightingModel      = .physicallyBased
        m.isDoubleSided      = true
        m.transparency       = 0.08
        return m
    }
}
