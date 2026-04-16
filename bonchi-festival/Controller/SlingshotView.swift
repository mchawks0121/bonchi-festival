//
//  SlingshotView.swift
//  bonchi-festival
//
//  iOS Controller: slingshot interaction UI.
//  The player drags back from the launch point to aim, then releases to fire.
//
//  The slingshot fork and rubber bands are rendered as 3-D geometry in the AR scene
//  (SlingshotNode attached to the camera's pointOfView).  This view only hosts
//  the invisible gesture capture layer and the power-indicator HUD element.
//

import SwiftUI

// MARK: - SlingshotView

/// Full-screen slingshot interaction layer shown during gameplay.
struct SlingshotView: View {

    @EnvironmentObject var gameManager: GameManager

    /// Maximum drag distance (upward) mapped to power = 1.0.
    private let maxDragDistance: CGFloat = 220

    /// Fractional Y position of the slingshot fork (0 = top, 1 = bottom) of the
    /// full-screen view.  Kept for PowerIndicatorView positioning only.
    private static let forkYRatio:  CGFloat = 0.62
    private static let forkHeight:  CGFloat = 130

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool   = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Transparent background — captures gestures over the whole screen
                Color.clear.contentShape(Rectangle())

                // Power bar above the (invisible) fork position
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
                        let clampedX = max(-maxDragDistance, min(maxDragDistance, value.translation.width))
                        let clampedY = max(-maxDragDistance, min(maxDragDistance, value.translation.height))
                        dragOffset = CGSize(width: clampedX, height: clampedY)
                        // Notify 3-D slingshot node of current drag state
                        gameManager.slingshotDragUpdate?(dragOffset, true)
                    }
                    .onEnded { _ in
                        isDragging = false
                        guard dragLength > 10 else {
                            withAnimation(.spring()) { dragOffset = .zero }
                            gameManager.slingshotDragUpdate?(.zero, false)
                            return
                        }
                        fireSlingshot(sceneSize: geo.size)
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

    private func fireSlingshot(sceneSize: CGSize) {
        let power = Float(normalizedPower)
        // Pulling left launches right; pulling DOWN launches UP.
        let dx    = -dragOffset.width
        let dy    =  dragOffset.height   // intentionally NOT negated
        let angle = Float(atan2(dy, dx))

        // Notify 3-D scene to launch the flying net before resetting drag
        gameManager.onNetFired?(dragOffset, power)

        // Reset drag state
        withAnimation(.spring(response: 0.25)) { dragOffset = .zero }
        gameManager.slingshotDragUpdate?(.zero, false)

        gameManager.sendLaunch(angle: angle, power: power)
    }
}

// MARK: - PowerIndicatorView

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

