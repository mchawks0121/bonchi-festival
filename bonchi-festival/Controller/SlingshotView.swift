//
//  SlingshotView.swift
//  bonchi-festival
//
//  iOS Controller: slingshot interaction UI.
//  The player drags back from the launch point to aim, then releases to fire.
//

import SwiftUI

// MARK: - SlingshotView

/// Full-screen slingshot interaction layer shown during gameplay.
struct SlingshotView: View {

    @EnvironmentObject var gameManager: GameManager

    /// Maximum drag distance (upward) mapped to power = 1.0.
    private let maxDragDistance: CGFloat = 220

    /// Fork shape dimensions. Increasing both makes the fork more prominent.
    private static let forkWidth:  CGFloat = 100
    private static let forkHeight: CGFloat = 130

    /// Fractional Y position of the slingshot fork (0 = top, 1 = bottom) of the
    /// full-screen view.  0.62 places the fork well within comfortable thumb reach
    /// (lower-middle of the screen) while leaving plenty of vertical room to pull
    /// upward.
    private static let forkYRatio: CGFloat = 0.62

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false

    // Net flight animation state
    @State private var showNet: Bool = false
    @State private var netFlightOffset: CGSize = .zero
    @State private var netScale: CGFloat = 1.0
    @State private var netOpacity: Double = 0.0
    @State private var netRotation: Double = 0.0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Transparent background — captures gestures over the whole screen
                Color.clear.contentShape(Rectangle())

                // Flying-net animation
                if showNet {
                    Text("🕸️")
                        .font(.system(size: 64))
                        .scaleEffect(netScale)
                        .rotationEffect(.degrees(netRotation))
                        .opacity(netOpacity)
                        .offset(netFlightOffset)
                }

                // Slingshot fork at 62 % down the full screen
                let forkCenter = CGPoint(x: geo.size.width / 2,
                                         y: geo.size.height * SlingshotView.forkYRatio)

                SlingshotForkShape()
                    .stroke(Color(red: 0.55, green: 0.27, blue: 0.07), lineWidth: 9)
                    .frame(width: SlingshotView.forkWidth, height: SlingshotView.forkHeight)
                    .position(forkCenter)

                // Rubber bands + pulled projectile
                if isDragging || dragOffset != .zero {
                    let leftFork  = CGPoint(x: forkCenter.x - SlingshotView.forkWidth  / 2,
                                            y: forkCenter.y - SlingshotView.forkHeight / 2)
                    let rightFork = CGPoint(x: forkCenter.x + SlingshotView.forkWidth  / 2,
                                            y: forkCenter.y - SlingshotView.forkHeight / 2)
                    let pullPoint = CGPoint(
                        x: forkCenter.x + dragOffset.width,
                        y: forkCenter.y + dragOffset.height
                    )

                    Path { p in
                        p.move(to: leftFork)
                        p.addLine(to: pullPoint)
                    }
                    .stroke(Color.orange, lineWidth: 4)

                    Path { p in
                        p.move(to: rightFork)
                        p.addLine(to: pullPoint)
                    }
                    .stroke(Color.orange, lineWidth: 4)

                    Text("🕸️")
                        .font(.system(size: 52))
                        .position(pullPoint)
                }

                // Power bar
                if isDragging {
                    PowerIndicatorView(power: normalizedPower)
                        .position(x: geo.size.width / 2,
                                  y: geo.size.height * SlingshotView.forkYRatio
                                   - SlingshotView.forkHeight / 2 - 24)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        isDragging = true
                        // Allow pulling in any direction (up, down, left, right)
                        let clampedX = max(-maxDragDistance, min(maxDragDistance, value.translation.width))
                        let clampedY = max(-maxDragDistance, min(maxDragDistance, value.translation.height))
                        dragOffset = CGSize(width: clampedX, height: clampedY)
                    }
                    .onEnded { _ in
                        isDragging = false
                        guard dragLength > 10 else {
                            withAnimation(.spring()) { dragOffset = .zero }
                            return
                        }
                        fireSlingshot(forkCenter: CGPoint(x: geo.size.width / 2,
                                                          y: geo.size.height * SlingshotView.forkYRatio),
                                      sceneSize: geo.size)
                    }
            )
        }
    }

    // MARK: - Helpers

    private var dragLength: CGFloat {
        sqrt(dragOffset.width * dragOffset.width + dragOffset.height * dragOffset.height)
    }

    private var normalizedPower: CGFloat {
        min(dragLength / maxDragDistance, 1.0)
    }

    private func fireSlingshot(forkCenter: CGPoint, sceneSize: CGSize) {
        let power  = Float(normalizedPower)
        // Pulling left launches right; pulling DOWN launches UP.
        // SwiftUI Y increases downward, SpriteKit Y increases upward, so
        // dragOffset.height > 0 (pulled down) must produce a positive dy (up in SpriteKit).
        let dx     = -dragOffset.width
        let dy     =  dragOffset.height   // intentionally NOT negated
        let angle  = Float(atan2(dy, dx))

        gameManager.sendLaunch(angle: angle, power: power)

        // Animate net flying in the launch direction
        let flyDx  = dragOffset.width  == 0 ? 0.0 : -(dragOffset.width  / dragLength) * 260
        let flyDy  = dragOffset.height == 0 ? -260 : -(dragOffset.height / dragLength) * 260

        withAnimation(.spring(response: 0.25)) {
            dragOffset = .zero
        }

        // Net starts at the fork, not the screen centre
        let startY = sceneSize.height * (SlingshotView.forkYRatio - 0.5)
        netFlightOffset = CGSize(width: 0, height: startY)
        netScale    = 0.3   // starts compact (net is folded before it opens)
        netOpacity  = 1.0
        netRotation = 0
        showNet     = true

        // Spin amount: 270°–810° (0.75–2.25 full turns) based on power
        let minSpinDegrees: Double  = 270   // minimum rotation at zero power
        let powerSpinRange: Double  = 540   // additional rotation at full power
        let spinDegrees = Double(normalizedPower) * powerSpinRange + minSpinDegrees

        withAnimation(.easeOut(duration: 0.55)) {
            netFlightOffset = CGSize(width: flyDx * 2.5, height: startY + flyDy * 2.5)
            netScale    = 1.8   // expands as the net opens in flight
            netOpacity  = 0
            netRotation = spinDegrees
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            showNet = false
            netFlightOffset = .zero
            netScale = 1.0
            netRotation = 0
        }
    }
}

// MARK: - Supporting Views

/// Y-shaped slingshot fork.
struct SlingshotForkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midX   = rect.midX
        let bottom = rect.maxY
        let mid    = rect.midY
        let top    = rect.minY

        // Stem
        path.move(to: CGPoint(x: midX, y: bottom))
        path.addLine(to: CGPoint(x: midX, y: mid))

        // Left fork
        path.move(to: CGPoint(x: midX, y: mid))
        path.addLine(to: CGPoint(x: rect.minX, y: top))

        // Right fork
        path.move(to: CGPoint(x: midX, y: mid))
        path.addLine(to: CGPoint(x: rect.maxX, y: top))

        return path
    }
}

/// Horizontal power bar shown while pulling the slingshot.
struct PowerIndicatorView: View {
    let power: CGFloat

    var body: some View {
        VStack(spacing: 4) {
            Text("Power")
                .font(.caption2.bold())
                .foregroundColor(.white)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 90, height: 10)
                RoundedRectangle(cornerRadius: 4)
                    .fill(barColor)
                    .frame(width: 90 * power, height: 10)
                    .animation(.linear(duration: 0.05), value: power)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.4))
        .cornerRadius(8)
    }

    private var barColor: Color {
        switch power {
        case ..<0.4: return .green
        case ..<0.7: return .yellow
        default:     return .red
        }
    }
}
