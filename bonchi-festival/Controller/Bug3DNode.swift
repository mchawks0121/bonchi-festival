//
//  Bug3DNode.swift
//  bonchi-festival
//
//  iOS Controller: RealityKit Entity that visually represents one AR bug.
//
//  Implementation intent:
//    Strictly uses RealityKit (no SceneKit) for all 3-D/AR processing as required.
//    USDZ assets are loaded with Entity.load(named:), all available animations are
//    retrieved via availableAnimations and played in an infinite loop with
//    playAnimation(animation.repeat(duration: .infinity)).
//
//  3-D models are loaded from USDZ files obtained from Apple's AR Quick Look gallery:
//    https://developer.apple.com/jp/augmented-reality/quick-look/
//
//  Model mapping (download these USDZ files and add them to the Xcode project):
//    • butterfly — toy_biplane.usdz  (flying toy; represents the fast Null bug)
//    • beetle    — gramophone.usdz   (dome shell shape; represents the Virus bug)
//    • stag      — toy_drummer.usdz  (animated character; represents the Glitch bug)
//
//  If the USDZ file for a given bug type is not found in the app bundle, the class
//  falls back to procedural PBR geometry (using RealityKit primitives) so the game
//  remains fully playable during development before the assets are added.
//
//  All entities hover vertically and have per-type animations driven by Timer.
//  Calling captured() triggers a glitch-flash / fade-out dismissal sequence.
//
//  Security considerations:
//    USDZ files are loaded from the app bundle only — no arbitrary file access.
//    The preload cache is protected by NSLock to prevent data races.
//
//  Constraints:
//    SceneKit (SCNNode, SCNScene, SCNAction, etc.) must NOT be used.
//    AnchorEntity is used by callers to add this entity to AR scenes.
//

import RealityKit
import ARKit
import UIKit

// MARK: - Bug3DNode

/// RealityKit-based visual representation of one AR bug.
/// The `entity` property is the root Entity; add to an AnchorEntity to display in AR:
///   `anchorEntity.addChild(bug3D.entity)`
final class Bug3DNode {

    let bugType: BugType

    /// The root RealityKit entity for this bug.
    /// Callers add this to a RealityKit AnchorEntity: `anchor.addChild(bug3D.entity)`
    let entity: Entity

    /// True when a USDZ model was successfully loaded from the app bundle.
    private var usdzLoaded = false

    // MARK: Timers for procedural hover/rotation animations (no SceneKit actions needed)
    private var hoverTimer:    Timer?
    private var rotationTimer: Timer?
    private var wingFlapTimer: Timer?

    // Pivot entity references for butterfly wing flap animation
    private var rightWingPivot:      Entity?
    private var leftWingPivot:       Entity?
    private var lowerRightWingPivot: Entity?
    private var lowerLeftWingPivot:  Entity?
    // Baseline Y position used by the hover timer
    private var hoverBaseY: Float = 0

    // MARK: - Asset preloading (即時性)

    /// Per-type scale factors for USDZ models.
    /// Exhaustive switch ensures a new BugType causes a compile error rather than
    /// silently rendering at the wrong scale.
    private static func usdzScale(for type: BugType) -> SIMD3<Float> {
        let s: Float
        switch type {
        case .butterfly: s = 0.005   // toy_biplane — compact flying toy
        case .beetle:    s = 0.004   // gramophone  — dome-shaped object
        case .stag:      s = 0.004   // toy_drummer — animated character
        }
        return SIMD3<Float>(repeating: s)
    }

    /// Thread safety for the preload cache and in-progress tracking.
    private static let cacheLock = NSLock()
    /// Keyed by BugType.rawValue; populated by preloadAssets() before any bug spawns.
    private static var entityCache: [String: Entity] = [:]
    /// Tracks assets currently being loaded to prevent concurrent duplicate I/O.
    private static var loadingInProgress = Set<String>()

    /// Preloads all USDZ entities off the main thread so the first instantiation
    /// clones from memory rather than reading from disk.
    /// Call this once early in the app lifecycle (e.g. from ARGameView.makeUIView
    /// and from WorldViewController.viewDidLoad for the projector path).
    static func preloadAssets() {
        let mapping: [(BugType, String)] = [
            (.butterfly, "toy_biplane"),
            (.beetle,    "gramophone"),
            (.stag,      "toy_drummer"),
        ]
        DispatchQueue.global(qos: .userInitiated).async {
            for (type, name) in mapping {
                // Under the lock: skip if already cached or currently loading.
                cacheLock.lock()
                let skip = entityCache[type.rawValue] != nil
                              || loadingInProgress.contains(type.rawValue)
                if !skip { loadingInProgress.insert(type.rawValue) }
                cacheLock.unlock()
                guard !skip else { continue }

                // Entity.load(named:) synchronously loads the USDZ from the app bundle.
                // Calling on a background thread avoids blocking the main run loop.
                guard let loaded = try? Entity.load(named: name) else {
                    cacheLock.lock()
                    loadingInProgress.remove(type.rawValue)
                    cacheLock.unlock()
                    continue
                }

                cacheLock.lock()
                entityCache[type.rawValue] = loaded
                loadingInProgress.remove(type.rawValue)
                cacheLock.unlock()
            }
        }
    }

    // MARK: - Init

    init(type: BugType) {
        self.bugType = type
        self.entity  = Entity()
        usdzLoaded   = loadUSDZModel()
        if !usdzLoaded { setupGeometry() }
        startAnimations()
    }

    // MARK: - Public API

    /// Entangle-struggle-dissolve sequence played when the bug is captured by the net.
    ///
    /// Phases:
    /// 1. Impact jolt  — sudden scale-up as the net lands.
    /// 2. Violent thrash — multi-axis tumble (bug trying to escape).
    /// 3. Net constricts — rapid scale-down as the bug is fully bound.
    /// 4. Glitch blinks  — digital corruption opacity flicker.
    /// 5. Dissolve       — final fade-out and removal from parent.
    func captured() {
        stopAllTimers()

        // 1. Impact jolt: scale up quickly
        entity.move(
            to: Transform(scale: SIMD3<Float>(repeating: 1.30),
                          rotation: entity.transform.rotation,
                          translation: entity.transform.translation),
            relativeTo: entity.parent,
            duration: 0.04,
            timingFunction: .linear
        )

        // 2. Violent thrash: combined spin and swell (starts after jolt)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            guard let self else { return }
            let thrashRot = simd_quatf(angle: .pi * 1.8,  axis: SIMD3<Float>(0, 1, 0))
                          * simd_quatf(angle: .pi * 0.55, axis: SIMD3<Float>(1, 0, 0))
            self.entity.move(
                to: Transform(scale: SIMD3<Float>(repeating: 0.78),
                              rotation: thrashRot,
                              translation: self.entity.transform.translation),
                relativeTo: self.entity.parent,
                duration: 0.22,
                timingFunction: .easeIn
            )
        }

        // 3. Net constricts: scale toward zero (starts after jolt + thrash)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.29) { [weak self] in
            guard let self else { return }
            self.entity.move(
                to: Transform(scale: SIMD3<Float>(repeating: 0.22),
                              rotation: self.entity.transform.rotation,
                              translation: self.entity.transform.translation),
                relativeTo: self.entity.parent,
                duration: 0.26,
                timingFunction: .easeIn
            )
        }

        // 4. Glitch blink opacity flicker (starts at ~0.55 s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            self?.runGlitchBlink()
        }

        // 5. Dissolve then remove (starts at ~0.77 s, ends ~0.99 s, entity removed ~1.2 s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.77) { [weak self] in
            self?.runFadeOut(duration: 0.22) { [weak self] in
                self?.entity.removeFromParent()
            }
        }
    }

    // MARK: - Private: USDZ loading

    /// Attempts to load the USDZ model for this bug type from the preload cache.
    /// Returns true if successful, false when the cache is empty (preload still
    /// in-progress or asset not bundled). The caller then builds procedural geometry.
    private func loadUSDZModel() -> Bool {
        cacheLock.lock()
        let cached = Bug3DNode.entityCache[bugType.rawValue]
        cacheLock.unlock()
        guard let cached else { return false }

        // Clone the cached entity so each bug has its own independent transform/animation.
        let model = cached.clone(recursive: true)
        model.scale = Bug3DNode.usdzScale(for: bugType)
        entity.addChild(model)

        // Retrieve all animations embedded in the USDZ and play each in an infinite loop.
        // availableAnimations returns every AnimationResource baked into the file.
        // repeat(duration: .infinity) wraps the resource so it plays forever.
        for animation in model.availableAnimations {
            model.playAnimation(
                animation.repeat(duration: .infinity),
                transitionDuration: 0,
                startsPaused: false
            )
        }

        // Recursively play animations on child entities (some USDZ embed them in children).
        playAnimationsRecursively(on: model)

        return true
    }

    /// Recursively plays all availableAnimations on an entity and its descendants.
    private func playAnimationsRecursively(on root: Entity) {
        for child in root.children {
            for animation in child.availableAnimations {
                child.playAnimation(
                    animation.repeat(duration: .infinity),
                    transitionDuration: 0,
                    startsPaused: false
                )
            }
            playAnimationsRecursively(on: child)
        }
    }

    // MARK: - Private: Procedural geometry (fallback when USDZ not bundled)

    /// Creates procedural geometry using RealityKit primitives (generateSphere, generateBox).
    /// This fallback ensures the game remains playable during development before
    /// USDZ assets are added to the Xcode project.
    private func setupGeometry() {
        switch bugType {
        case .butterfly: setupButterfly()
        case .beetle:    setupBeetle()
        case .stag:      setupStag()
        }
    }

    // MARK: Butterfly — orange/tinted body, 4 wing slabs, antennae

    private func setupButterfly() {
        let bodyMat = pbr(UIColor(red: 0.10, green: 0.05, blue: 0.01, alpha: 1),
                          roughness: 0.65, metalness: 0.02,
                          emission: UIColor(red: 0.0, green: 0.14, blue: 0.35, alpha: 1))

        // Abdomen: capsule approximated as cylinder-like rounded box + head sphere
        let body = makeCapsule(capRadius: 0.009, height: 0.048, material: bodyMat)
        entity.addChild(body)

        let head = ModelEntity(mesh: .generateSphere(radius: 0.011), materials: [bodyMat])
        head.position = SIMD3<Float>(0, 0.033, 0)
        entity.addChild(head)

        // Wings: thin box slabs (readable shape at AR scale without double-sided material)
        let upperWingMat = pbr(UIColor(red: 0.95, green: 0.50, blue: 0.05, alpha: 0.90),
                               roughness: 0.70, metalness: 0.0,
                               emission: UIColor(red: 0.22, green: 0.08, blue: 0.0, alpha: 0.22))
        let lowerWingMat = pbr(UIColor(red: 0.82, green: 0.35, blue: 0.05, alpha: 0.88),
                               roughness: 0.70, metalness: 0.0,
                               emission: UIColor(red: 0.18, green: 0.06, blue: 0.0, alpha: 0.18))

        for sign: Float in [-1.0, 1.0] {
            // Upper wing pivot (animated during wing flap)
            let uPivot = Entity()
            uPivot.position = SIMD3<Float>(sign * 0.009, 0.008, 0)
            let uWing = ModelEntity(
                mesh: .generateBox(size: SIMD3<Float>(0.095, 0.070, 0.002)),
                materials: [upperWingMat]
            )
            uWing.position    = SIMD3<Float>(sign * 0.048, 0.006, 0)
            uWing.orientation = simd_quatf(angle: sign * Float.pi / 14,
                                           axis: SIMD3<Float>(0, 0, 1))
            uPivot.addChild(uWing)
            entity.addChild(uPivot)

            // Lower wing pivot
            let lPivot = Entity()
            lPivot.position = SIMD3<Float>(sign * 0.007, -0.004, 0)
            let lWing = ModelEntity(
                mesh: .generateBox(size: SIMD3<Float>(0.065, 0.052, 0.002)),
                materials: [lowerWingMat]
            )
            lWing.position    = SIMD3<Float>(sign * 0.033, -0.010, 0)
            lWing.orientation = simd_quatf(angle: sign * Float.pi / 16,
                                           axis: SIMD3<Float>(0, 0, 1))
            lPivot.addChild(lWing)
            entity.addChild(lPivot)

            // Cache pivot references for the flap timer
            if sign > 0 { rightWingPivot = uPivot; lowerRightWingPivot = lPivot }
            else         { leftWingPivot  = uPivot; lowerLeftWingPivot  = lPivot }
        }

        // Antennae: thin rounded-box shafts with sphere tips
        let aMat = pbr(UIColor(red: 0.10, green: 0.05, blue: 0.01, alpha: 1),
                       roughness: 0.60, metalness: 0.02)
        for sign: Float in [-1.0, 1.0] {
            let shaft = ModelEntity(
                mesh: .generateBox(size: SIMD3<Float>(0.0036, 0.036, 0.0036),
                                   cornerRadius: 0.0018),
                materials: [aMat]
            )
            shaft.position    = SIMD3<Float>(sign * 0.010, 0.051, 0)
            shaft.orientation = simd_quatf(angle: sign * Float.pi / 7,
                                           axis: SIMD3<Float>(0, 0, 1))
            let tip = ModelEntity(mesh: .generateSphere(radius: 0.004), materials: [aMat])
            tip.position = SIMD3<Float>(0, 0.018, 0)
            shaft.addChild(tip)
            entity.addChild(shaft)
        }
    }

    // MARK: Beetle — glossy elytra dome, suture, eyes, legs

    private func setupBeetle() {
        let shellMat = pbr(UIColor(red: 0.55, green: 0.08, blue: 0.08, alpha: 1),
                           roughness: 0.14, metalness: 0.62,
                           emission: UIColor(red: 0.0, green: 0.18, blue: 0.04, alpha: 1))

        // Main body: flattened rounded box approximating an elytra dome
        let body = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(0.084, 0.054, 0.098),
                               cornerRadius: 0.020),
            materials: [shellMat]
        )
        entity.addChild(body)

        // Suture line down the back
        let sutMat = pbr(UIColor(red: 0.18, green: 0.02, blue: 0.02, alpha: 1),
                         roughness: 0.08, metalness: 0.72)
        let suture = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(0.0056, 0.074, 0.0056),
                               cornerRadius: 0.0028),
            materials: [sutMat]
        )
        suture.position = SIMD3<Float>(0, 0.022, 0)
        entity.addChild(suture)

        addSphere(radius: 0.022, at: SIMD3<Float>(0, 0.006, -0.052),
                  mat: pbr(UIColor(red: 0.40, green: 0.05, blue: 0.05, alpha: 1),
                           roughness: 0.20, metalness: 0.55))

        addSphere(radius: 0.018, at: SIMD3<Float>(0, 0.002, -0.076),
                  mat: pbr(UIColor(red: 0.30, green: 0.04, blue: 0.04, alpha: 1),
                           roughness: 0.28, metalness: 0.45))

        let eyeMat = pbr(UIColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1),
                         roughness: 0.04, metalness: 0.08)
        for sign: Float in [-1.0, 1.0] {
            addSphere(radius: 0.007, at: SIMD3<Float>(sign * 0.015, 0.010, -0.080), mat: eyeMat)
        }

        let legMat = pbr(UIColor(red: 0.22, green: 0.04, blue: 0.04, alpha: 1),
                         roughness: 0.40, metalness: 0.28)
        for legZ: Float in [0.010, -0.025, -0.052] {
            for sign: Float in [-1.0, 1.0] {
                addLeg(at: SIMD3<Float>(sign * 0.042, -0.012, legZ),
                       sign: sign, mat: legMat, outAngle: Float.pi / 2.2)
            }
        }
    }

    // MARK: Stag beetle — dark metallic body, mandibles, legs

    private func setupStag() {
        let darkMat = pbr(UIColor(red: 0.14, green: 0.08, blue: 0.02, alpha: 1),
                          roughness: 0.20, metalness: 0.65,
                          emission: UIColor(red: 0.28, green: 0.05, blue: 0.0, alpha: 1))

        let body = makeCapsule(capRadius: 0.028, height: 0.068, material: darkMat)
        entity.addChild(body)

        addSphere(radius: 0.024, at: SIMD3<Float>(0, 0.050, 0),
                  mat: pbr(UIColor(red: 0.16, green: 0.09, blue: 0.02, alpha: 1),
                           roughness: 0.18, metalness: 0.62))

        let headMat = pbr(UIColor(red: 0.18, green: 0.10, blue: 0.02, alpha: 1),
                          roughness: 0.22, metalness: 0.58)
        addSphere(radius: 0.022, at: SIMD3<Float>(0, 0.082, 0), mat: headMat)

        let eyeMat = pbr(UIColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1),
                         roughness: 0.04, metalness: 0.08)
        for sign: Float in [-1.0, 1.0] {
            addSphere(radius: 0.006, at: SIMD3<Float>(sign * 0.018, 0.090, 0.014), mat: eyeMat)
        }

        // Mandibles (大顎) — characteristic stag beetle feature
        let mandMat = pbr(UIColor(red: 0.22, green: 0.12, blue: 0.03, alpha: 1),
                          roughness: 0.25, metalness: 0.50)
        for sign: Float in [-1.0, 1.0] {
            let mand = makeCapsule(capRadius: 0.005, height: 0.052, material: mandMat)
            mand.position    = SIMD3<Float>(sign * 0.022, 0.106, 0.010)
            mand.orientation = simd_quatf(angle: sign * Float.pi / 8,
                                          axis: SIMD3<Float>(0, 0, 1))
                             * simd_quatf(angle: Float.pi / 2.2,
                                          axis: SIMD3<Float>(1, 0, 0))
            entity.addChild(mand)
        }

        let legMat = pbr(UIColor(red: 0.12, green: 0.07, blue: 0.02, alpha: 1),
                         roughness: 0.35, metalness: 0.35)
        for legY: Float in [0.038, 0.008, -0.024] {
            for sign: Float in [-1.0, 1.0] {
                addLeg(at: SIMD3<Float>(sign * 0.030, legY, 0),
                       sign: sign, mat: legMat, outAngle: Float.pi / 2.6)
            }
        }
    }

    // MARK: - Procedural geometry helpers

    /// Capsule approximation: a cylinder-like rounded box body with sphere caps at each end.
    private func makeCapsule(capRadius r: Float, height h: Float,
                              material: RealityKit.Material) -> Entity {
        let e        = Entity()
        let cylH     = max(0.001, h - 2 * r)
        let diameter = r * 2

        // Central body — rounded box approximating a cylinder cross-section.
        // cornerRadius must be <= 0.5 * min(size dimension), so we use r * 0.9 to be safe.
        let body = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(diameter, cylH, diameter),
                               cornerRadius: r * 0.9),
            materials: [material]
        )
        e.addChild(body)

        let top = ModelEntity(mesh: .generateSphere(radius: r), materials: [material])
        top.position = SIMD3<Float>(0,  cylH / 2, 0)
        e.addChild(top)

        let bot = ModelEntity(mesh: .generateSphere(radius: r), materials: [material])
        bot.position = SIMD3<Float>(0, -cylH / 2, 0)
        e.addChild(bot)

        return e
    }

    @discardableResult
    private func addSphere(radius: Float, at pos: SIMD3<Float>,
                           mat: RealityKit.Material) -> ModelEntity {
        let e = ModelEntity(mesh: .generateSphere(radius: radius), materials: [mat])
        e.position = pos
        entity.addChild(e)
        return e
    }

    /// Adds a two-segment leg (upper + lower box shaft) at the given attachment point.
    private func addLeg(at origin: SIMD3<Float>, sign: Float,
                        mat: RealityKit.Material, outAngle: Float) {
        let upperLen: Float = 0.026
        let lowerLen: Float = 0.022
        let lowerAngle      = outAngle + Float.pi / 6

        let upper = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(0.008, upperLen, 0.008),
                               cornerRadius: 0.003),
            materials: [mat]
        )
        upper.position    = origin
        upper.orientation = simd_quatf(angle: sign * outAngle, axis: SIMD3<Float>(0, 0, 1))

        let kneeX = origin.x + sign * upperLen * sin(outAngle)
        let kneeY = origin.y - upperLen * cos(outAngle)
        let lower = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(0.006, lowerLen, 0.006),
                               cornerRadius: 0.002),
            materials: [mat]
        )
        lower.position = SIMD3<Float>(
            kneeX + sign * (lowerLen / 2) * sin(lowerAngle),
            kneeY - (lowerLen / 2) * cos(lowerAngle),
            origin.z
        )
        lower.orientation = simd_quatf(angle: sign * lowerAngle, axis: SIMD3<Float>(0, 0, 1))

        entity.addChild(upper)
        entity.addChild(lower)
    }

    // MARK: - Animation control

    private func startAnimations() {
        // Start invisible; fade in for immediate visual presence (即時性).
        entity.components.set(OpacityComponent(opacity: 0))
        runFadeIn(duration: 0.25)

        if usdzLoaded {
            // USDZ animations are already started in loadUSDZModel() via availableAnimations.
            // Add a slow Y-rotation so the player can see all model sides.
            let period: Double
            switch bugType {
            case .butterfly: period = 9.0
            case .beetle:    period = 5.5
            case .stag:      period = 7.5
            }
            startRotation(period: period)
        } else {
            switch bugType {
            case .butterfly:
                startWingFlap()
                startRotation(period: 9.0)
            case .beetle:
                startRock()   // startRock() also handles rotation internally
            case .stag:
                startRotation(period: 7.5)
            }
        }

        // Vertical hover: sinusoidal ±1.8 cm (applied to both USDZ and procedural).
        startHover()
    }

    private func stopAllTimers() {
        hoverTimer?.invalidate();    hoverTimer    = nil
        rotationTimer?.invalidate(); rotationTimer = nil
        wingFlapTimer?.invalidate(); wingFlapTimer = nil
    }

    // MARK: Per-type animation timers

    /// Sinusoidal vertical hover via a 60 fps Timer.
    private func startHover() {
        let amplitude: Float = 0.018
        let period = Float.random(in: 1.30...1.70)
        let start  = Date()
        hoverBaseY = entity.position.y

        hoverTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            let t = Float(Date().timeIntervalSince(start))
            self.entity.position.y = self.hoverBaseY + amplitude * sin(2 * Float.pi * t / period)
        }
    }

    /// Continuous Y-axis rotation via a 60 fps Timer.
    private func startRotation(period: Double) {
        let speed = Float(2 * Double.pi / period)
        let start = Date()
        rotationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            let t = Float(Date().timeIntervalSince(start))
            self.entity.orientation = simd_quatf(angle: speed * t, axis: SIMD3<Float>(0, 1, 0))
        }
    }

    /// Side-to-side roll for beetle (crawling gait simulation).
    /// Handles both rotation and rock using the wingFlapTimer slot (beetle has no wings).
    private func startRock() {
        let rotSpeed: Float  = Float(2 * Double.pi / 5.5)
        let rockAmp:  Float  = .pi / 18
        let rockPer:  Float  = 0.76
        let start = Date()
        wingFlapTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            let t    = Float(Date().timeIntervalSince(start))
            let yRot = simd_quatf(angle: rotSpeed * t, axis: SIMD3<Float>(0, 1, 0))
            let roll = rockAmp * sin(2 * Float.pi * t / rockPer)
            let zRot = simd_quatf(angle: roll, axis: SIMD3<Float>(0, 0, 1))
            self.entity.orientation = yRot * zRot
        }
    }

    /// Sinusoidal wing flap for butterfly.
    private func startWingFlap() {
        let period: Float = Float.random(in: 0.24...0.32)
        let angle:  Float = .pi / 2.0
        let start = Date()
        wingFlapTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            let t = Float(Date().timeIntervalSince(start))
            let a = angle * sin(2 * Float.pi * t / period)
            self.rightWingPivot?.orientation      = simd_quatf(angle:  a,        axis: SIMD3<Float>(0, 0, 1))
            self.leftWingPivot?.orientation       = simd_quatf(angle: -a,        axis: SIMD3<Float>(0, 0, 1))
            self.lowerRightWingPivot?.orientation = simd_quatf(angle:  a * 0.75, axis: SIMD3<Float>(0, 0, 1))
            self.lowerLeftWingPivot?.orientation  = simd_quatf(angle: -a * 0.75, axis: SIMD3<Float>(0, 0, 1))
        }
    }

    // MARK: - Opacity helpers

    /// Fades the entity in over `duration` seconds by stepping OpacityComponent values.
    private func runFadeIn(duration: TimeInterval) {
        let steps = 20
        let dt    = duration / Double(steps)
        for i in 0...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * dt) { [weak self] in
                self?.entity.components.set(OpacityComponent(opacity: Float(i) / Float(steps)))
            }
        }
    }

    /// Fades the entity out over `duration` seconds, then calls `completion`.
    private func runFadeOut(duration: TimeInterval, completion: (() -> Void)? = nil) {
        let steps = 20
        let dt    = duration / Double(steps)
        for i in 0...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * dt) { [weak self] in
                guard let self else { return }
                self.entity.components.set(OpacityComponent(opacity: 1.0 - Float(i) / Float(steps)))
                if i == steps { completion?() }
            }
        }
    }

    /// Rapid opacity flicker simulating digital glitch / corruption flash.
    private func runGlitchBlink() {
        let dur: TimeInterval = 0.055
        let pattern: [(Float, TimeInterval)] = [
            (0.0,  0),
            (0.85, dur * 0.35),
            (0.0,  dur * 0.60),
            (0.70, dur * 0.80),
        ]
        for (opacity, delay) in pattern {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.entity.components.set(OpacityComponent(opacity: opacity))
            }
        }
    }

    // MARK: - PBR material factory

    /// Creates a PhysicallyBasedMaterial for procedural bug geometry.
    /// The optional emission colour adds a faint self-glow to convey the
    /// digital-corruption theme (リアルさ).
    private func pbr(_ diffuse: UIColor, roughness: Float, metalness: Float,
                     emission: UIColor = .black) -> PhysicallyBasedMaterial {
        var mat = PhysicallyBasedMaterial()
        mat.baseColor = .init(tint: diffuse)
        mat.roughness = .init(floatLiteral: roughness)
        mat.metallic  = .init(floatLiteral: metalness)
        if emission != .black {
            mat.emissiveColor     = .init(color: emission)
            mat.emissiveIntensity = 0.4
        }
        return mat
    }
}
