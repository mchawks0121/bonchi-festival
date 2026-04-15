//
//  ContentView.swift
//  bonchi-festival
//
//  iOS Controller: root view that routes between Waiting, Playing, and Finished screens.
//

import SwiftUI
import ARKit
import SceneKit

// MARK: - Design tokens

private let accentCyan   = Color(red: 0.2,  green: 1.0, blue: 0.8)
private let accentBlue   = Color(red: 0.4,  green: 0.9, blue: 1.0)
private let bgTop        = Color(red: 0.04, green: 0.02, blue: 0.14)
private let bgBottom     = Color(red: 0.01, green: 0.01, blue: 0.08)

// MARK: - Root

struct ContentView: View {

    @StateObject private var gameManager = GameManager()

    var body: some View {
        ZStack {
            // Digital-corruption gradient: deep navy → almost-black
            LinearGradient(
                colors: [bgTop, bgBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            switch gameManager.state {
            case .waiting:
                WaitingView()
                    .environmentObject(gameManager)
                    .transition(.opacity)
            case .calibrating:
                CalibrationView()
                    .environmentObject(gameManager)
                    .transition(.opacity)
            case .playing:
                PlayingView()
                    .environmentObject(gameManager)
                    .transition(.opacity)
            case .finished:
                FinishedView()
                    .environmentObject(gameManager)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: gameManager.state.rawValue)
    }
}

// MARK: - Waiting Screen

struct WaitingView: View {
    @EnvironmentObject var gameManager: GameManager

    var body: some View {
        GeometryReader { geo in
            // SE/mini class: height ≤ 700 pt (e.g. iPhone SE 667 pt, mini 780 pt safe-area adjusted)
            let compact = geo.size.height < 750
            ScrollView {
                VStack(spacing: compact ? 16 : 28) {

                    // ── Hero logo ────────────────────────────────────────────
                    HeroLogo(compact: compact)
                        .padding(.top, compact ? 20 : 48)

                    // ── Title ────────────────────────────────────────────────
                    VStack(spacing: compact ? 4 : 8) {
                        Text("BUG HUNTER")
                            .font(.system(
                                size: compact ? 28 : 38,
                                weight: .black,
                                design: .monospaced
                            ))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [accentCyan, accentBlue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .tracking(2)

                        Text("君は、バグハンター")
                            .font(compact ? .subheadline.bold() : .title3.bold())
                            .foregroundColor(.white.opacity(0.9))

                        Text("バグに侵食されたワールドを救え")
                            .font(compact ? .caption : .callout)
                            .foregroundColor(accentBlue.opacity(0.75))
                            .multilineTextAlignment(.center)
                    }

                    // ── Mode selection ───────────────────────────────────────
                    VStack(spacing: compact ? 6 : 10) {
                        Text("PLAY MODE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                            .tracking(3)

                        VStack(spacing: 8) {
                            ModeCard(
                                symbol: "iphone",
                                title: "スタンドアロン",
                                subtitle: "AR のみ（1台完結）",
                                isSelected: gameManager.gameMode == .standalone,
                                compact: compact
                            )
                            .onTapGesture { gameManager.selectMode(.standalone) }

                            ModeCard(
                                symbol: "gamecontroller",
                                title: "プロジェクター",
                                subtitle: "クライアント（コントローラー）",
                                isSelected: gameManager.gameMode == .projectorClient,
                                compact: compact
                            )
                            .onTapGesture { gameManager.selectMode(.projectorClient) }

                            ModeCard(
                                symbol: "tv",
                                title: "プロジェクター",
                                subtitle: "サーバー（表示デバイス）",
                                isSelected: gameManager.gameMode == .projectorServer,
                                compact: compact
                            )
                            .onTapGesture { gameManager.selectMode(.projectorServer) }
                        }
                        .padding(.horizontal, 24)
                    }

                    // Connection status pill — only in projector client mode
                    if gameManager.gameMode == .projectorClient {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(gameManager.isConnected ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(gameManager.isConnected
                                 ? "プロジェクターに接続済み"
                                 : "プロジェクターを探しています…")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.1))
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .clipShape(Capsule())
                        .transition(.opacity.combined(with: .scale))
                        .animation(.easeInOut(duration: 0.25), value: gameManager.isConnected)
                    }

                    // Start button
                    Button {
                        withAnimation { gameManager.startCalibration() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                                .font(.system(size: compact ? 14 : 16, weight: .bold))
                            Text("バグ狩り開始")
                                .font(.system(size: compact ? 16 : 18, weight: .bold, design: .default))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, compact ? 36 : 52)
                        .padding(.vertical, compact ? 13 : 17)
                        .background(accentCyan)
                        .clipShape(Capsule())
                        .shadow(color: accentCyan.opacity(0.55), radius: 20, y: 4)
                    }

                    // Bug legend card
                    VStack(spacing: compact ? 8 : 12) {
                        HStack {
                            Text("THREAT INDEX")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(accentCyan.opacity(0.8))
                                .tracking(2)
                            Spacer()
                            Text("出現バグ一覧")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.4))
                        }

                        Divider()
                            .background(Color.white.opacity(0.12))

                        VStack(spacing: compact ? 6 : 8) {
                            ForEach(BugType.allCases, id: \.rawValue) { bug in
                                BugLegendRow(bug: bug, compact: compact)
                            }
                        }
                    }
                    .padding(compact ? 14 : 20)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .padding(.horizontal, 24)

                    // Mission card
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "terminal.fill")
                                .font(.caption.bold())
                                .foregroundColor(accentCyan)
                            Text("MISSION")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(accentCyan)
                                .tracking(2)
                        }
                        Text("ワールドはバグに蝕まれている。\nスリングショットで網を飛ばし、バグを捕まえろ！\n制限時間は90秒。Glitchほど手強く、倒すほど価値がある。")
                            .font(compact ? .footnote : .body)
                            .foregroundColor(.white.opacity(0.75))
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(compact ? 14 : 20)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
                .frame(minWidth: geo.size.width)
            }
        }
    }
}

// MARK: - Hero Logo

private struct HeroLogo: View {
    let compact: Bool

    private let outerSize: CGFloat
    private let innerSize: CGFloat
    private let iconSize: CGFloat

    init(compact: Bool) {
        self.compact = compact
        self.outerSize = compact ? 88 : 118
        self.innerSize = compact ? 66 : 90
        self.iconSize  = compact ? 32 : 44
    }

    var body: some View {
        ZStack {
            // Outer glow ring
            Circle()
                .stroke(accentCyan.opacity(0.18), lineWidth: 1)
                .frame(width: outerSize, height: outerSize)
            // Inner filled circle
            Circle()
                .fill(accentCyan.opacity(0.08))
                .frame(width: innerSize, height: innerSize)
            Circle()
                .stroke(accentCyan.opacity(0.35), lineWidth: 1.5)
                .frame(width: innerSize, height: innerSize)
            // Icon
            Image(systemName: "ant.fill")
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(accentCyan)
        }
    }
}

// MARK: - Mode Card

struct ModeCard: View {
    let symbol: String
    let title: String
    let subtitle: String
    let isSelected: Bool
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: compact ? 20 : 24, weight: .medium))
                .foregroundStyle(isSelected ? accentCyan : .white.opacity(0.55))
                .frame(width: compact ? 28 : 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: compact ? 13 : 15, weight: .semibold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: compact ? 10 : 12))
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(accentCyan)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, compact ? 12 : 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isSelected
                      ? accentCyan.opacity(0.12)
                      : Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    isSelected ? accentCyan : Color.white.opacity(0.12),
                    lineWidth: isSelected ? 1.5 : 1
                )
        )
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Bug Legend Row

private extension BugType {
    var symbolName: String {
        switch self {
        case .butterfly: return "exclamationmark.circle.fill"
        case .beetle:    return "xmark.octagon.fill"
        case .stag:      return "bolt.fill"
        }
    }
    var symbolColor: Color {
        switch self {
        case .butterfly: return Color(red: 0.3, green: 0.9, blue: 1.0)
        case .beetle:    return Color(red: 1.0, green: 0.6, blue: 0.2)
        case .stag:      return Color(red: 1.0, green: 0.3, blue: 0.5)
        }
    }
}

struct BugLegendRow: View {
    let bug: BugType
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Threat icon badge
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(bug.symbolColor.opacity(0.12))
                    .frame(width: compact ? 34 : 42, height: compact ? 34 : 42)
                Image(systemName: bug.symbolName)
                    .font(.system(size: compact ? 16 : 20, weight: .semibold))
                    .foregroundStyle(bug.symbolColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(bug.displayName)
                        .font(.system(size: compact ? 11 : 13, weight: .bold))
                        .foregroundColor(.white)
                    Text(bug.rarityLabel)
                        .font(.system(size: compact ? 9 : 11))
                        .foregroundColor(.yellow.opacity(0.85))
                }
                Text(bug.lore)
                    .font(.system(size: compact ? 9 : 11))
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(bug.points) pt")
                    .font(.system(size: compact ? 11 : 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.yellow)
                Text(bug.speedLabel)
                    .font(.system(size: compact ? 9 : 11))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(.vertical, compact ? 4 : 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.04))
        )
    }
}

// MARK: - Calibration Screen

/// Full-screen AR view shown before the game starts.
/// The player points the camera at the desired centre of the play area and
/// taps "この位置を基準点に設定" to lock in that position as the world origin
/// for bug spawning.
struct CalibrationView: UIViewRepresentable {
    @EnvironmentObject var gameManager: GameManager

    func makeCoordinator() -> CalibrationCoordinator { CalibrationCoordinator() }

    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: UIScreen.main.bounds)

        // ── AR camera view ────────────────────────────────────────────────
        let arView = ARSCNView(frame: container.bounds)
        arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        arView.scene = SCNScene()
        container.addSubview(arView)
        context.coordinator.arView = arView

        let config = ARWorldTrackingConfiguration()
        arView.session.run(config)

        // ── Overlay: reticle + instruction + confirm button ───────────────
        let overlay = UIView(frame: container.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.isUserInteractionEnabled = false
        container.addSubview(overlay)

        // Cross-hair reticle: a fixed-size view centred with Auto Layout so it
        // adapts correctly to all device sizes including those with Dynamic Island.
        let reticleView = UIView()
        reticleView.translatesAutoresizingMaskIntoConstraints = false
        reticleView.isUserInteractionEnabled = false
        container.addSubview(reticleView)
        NSLayoutConstraint.activate([
            reticleView.widthAnchor.constraint(equalToConstant: 80),
            reticleView.heightAnchor.constraint(equalToConstant: 80),
            reticleView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            reticleView.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        let reticle = CAShapeLayer()
        reticle.frame = CGRect(x: 0, y: 0, width: 80, height: 80)
        let cx: CGFloat = 40, cy: CGFloat = 40, armLen: CGFloat = 28
        let path = UIBezierPath()
        path.move(to: CGPoint(x: cx - armLen, y: cy))
        path.addLine(to: CGPoint(x: cx + armLen, y: cy))
        path.move(to: CGPoint(x: cx, y: cy - armLen))
        path.addLine(to: CGPoint(x: cx, y: cy + armLen))
        path.move(to: CGPoint(x: cx + 10, y: cy))
        path.addArc(withCenter: CGPoint(x: cx, y: cy), radius: 10,
                    startAngle: 0, endAngle: .pi * 2, clockwise: true)
        reticle.path = path.cgPath
        reticle.strokeColor = UIColor(red: 0.2, green: 1.0, blue: 0.8, alpha: 0.9).cgColor
        reticle.fillColor = UIColor.clear.cgColor
        reticle.lineWidth = 1.8
        reticleView.layer.addSublayer(reticle)

        // Instruction label
        let label = UILabel()
        label.text = "カメラをゲームの中心にしたい場所に向け、\nボタンを押してください"
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = UIColor.white.withAlphaComponent(0.9)
        label.textAlignment = .center
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOpacity = 0.8
        label.layer.shadowRadius = 4
        label.layer.shadowOffset = .zero
        container.addSubview(label)

        // Confirm button — user-interactive so it must be on the container, not overlay
        let button = UIButton(type: .system)
        button.setTitle("この位置を基準点に設定", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        button.setTitleColor(.black, for: .normal)
        button.backgroundColor = UIColor(red: 0.2, green: 1.0, blue: 0.8, alpha: 1.0)
        button.layer.cornerRadius = 26
        button.contentEdgeInsets = UIEdgeInsets(top: 14, left: 32, bottom: 14, right: 32)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(context.coordinator,
                         action: #selector(CalibrationCoordinator.confirmTapped(_:)),
                         for: .touchUpInside)
        container.addSubview(button)

        // Back button (top-left)
        let backButton = UIButton(type: .system)
        backButton.setTitle("← 戻る", for: .normal)
        backButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        backButton.setTitleColor(.white, for: .normal)
        backButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        backButton.layer.cornerRadius = 16
        backButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.addTarget(context.coordinator,
                             action: #selector(CalibrationCoordinator.backTapped(_:)),
                             for: .touchUpInside)
        container.addSubview(backButton)

        // Layout
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.bottomAnchor.constraint(equalTo: button.topAnchor, constant: -20),

            button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            button.bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.bottomAnchor, constant: -36),

            backButton.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 16),
            backButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20)
        ])

        context.coordinator.onConfirm = { [weak gameManager] transform in
            DispatchQueue.main.async { gameManager?.setWorldOrigin(transform: transform) }
        }
        context.coordinator.onBack = { [weak gameManager] in
            DispatchQueue.main.async {
                withAnimation { gameManager?.resetGame() }
            }
        }

        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    /// Called when the view is removed from the hierarchy.
    /// Pauses the AR session to release the camera and free GPU/CPU resources.
    static func dismantleUIView(_ uiView: UIView, coordinator: CalibrationCoordinator) {
        coordinator.arView?.session.pause()
    }
}

final class CalibrationCoordinator: NSObject {
    weak var arView: ARSCNView?
    var onConfirm: ((simd_float4x4) -> Void)?
    var onBack: (() -> Void)?

    @objc func confirmTapped(_ sender: UIButton) {
        guard let frame = arView?.session.currentFrame else { return }
        onConfirm?(frame.camera.transform)
    }

    @objc func backTapped(_ sender: UIButton) {
        onBack?()
    }
}

// MARK: - Playing Screen

struct PlayingView: View {
    @EnvironmentObject var gameManager: GameManager

    var body: some View {
        if gameManager.gameMode == .projectorServer {
            ProjectorServerView()
                .environmentObject(gameManager)
        } else {
            ARPlayingView()
                .environmentObject(gameManager)
        }
    }
}

// MARK: - AR Playing Screen (standalone / projectorClient)

struct ARPlayingView: View {
    @EnvironmentObject var gameManager: GameManager

    var body: some View {
        ZStack {
            // ── AR camera + SpriteKit bug world (full screen) ────────────
            ARGameView()
                .environmentObject(gameManager)
                .ignoresSafeArea()

            // ── HUD pinned to the top ─────────────────────────────────────
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BUGS FIXED")
                            .font(.caption2.bold())
                            .foregroundColor(.white.opacity(0.6))
                        Text("\(gameManager.score)")
                            .font(.system(size: 44, weight: .black, design: .rounded))
                            .foregroundColor(Color(red: 0.2, green: 1.0, blue: 0.8))
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("TIME")
                            .font(.caption2.bold())
                            .foregroundColor(.white.opacity(0.6))
                        Text(String(format: "%.1f", gameManager.timeRemaining))
                            .font(.system(size: 44, weight: .black, design: .rounded))
                            .foregroundColor(gameManager.timeRemaining < 10 ? .red : .white)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 12)
                .background(Color.black.opacity(0.35))

                // Timer bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.18))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(timerBarColor)
                            .frame(width: geo.size.width * CGFloat(gameManager.timeRemaining / 90.0))
                            .animation(.linear(duration: 0.1), value: gameManager.timeRemaining)
                    }
                    .frame(height: 7)
                }
                .frame(height: 7)
                .padding(.horizontal, 28)
                .padding(.top, 2)

                Spacer()
            }
            .allowsHitTesting(false)  // gestures pass through to the slingshot layer below

            // ── Slingshot — full-screen overlay ──────────────────────────
            SlingshotView()
                .environmentObject(gameManager)
        }
    }

    private var timerBarColor: Color {
        switch gameManager.timeRemaining {
        case 30...: return .green
        case 10...: return .yellow
        default:    return .red
        }
    }
}

// MARK: - Projector Server Playing Screen

/// Wraps WorldViewController as a full-screen SwiftUI view for projector-server mode.
/// WorldViewController manages all game scenes internally; we just add a back button.
struct ProjectorServerView: View {
    @EnvironmentObject var gameManager: GameManager

    var body: some View {
        ZStack(alignment: .topLeading) {
            WorldViewControllerWrapper()
                .ignoresSafeArea()

            Button {
                withAnimation { gameManager.resetGame() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("モード選択に戻る")
                        .font(.caption.bold())
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.55))
                .clipShape(Capsule())
            }
            .padding(.top, 56)
            .padding(.leading, 20)
        }
    }
}

// MARK: - WorldViewController wrapper

struct WorldViewControllerWrapper: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> WorldViewController {
        WorldViewController()
    }
    func updateUIViewController(_ uiViewController: WorldViewController, context: Context) {}
}

// MARK: - Finished Screen

struct FinishedView: View {
    @EnvironmentObject var gameManager: GameManager

    var body: some View {
        VStack(spacing: 30) {

            // Result badge
            ZStack {
                Circle()
                    .stroke(accentCyan.opacity(0.25), lineWidth: 1)
                    .frame(width: 110, height: 110)
                Circle()
                    .fill(accentCyan.opacity(0.08))
                    .frame(width: 88, height: 88)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(accentCyan)
            }

            VStack(spacing: 6) {
                Text("MISSION CLEAR")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(accentCyan.opacity(0.8))
                    .tracking(3)
                Text("ミッション完了")
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)
            }

            VStack(spacing: 4) {
                Text("捕まえたバグ")
                    .font(.caption.bold())
                    .foregroundColor(.white.opacity(0.5))
                    .tracking(1)

                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text("\(gameManager.score)")
                        .font(.system(size: 88, weight: .black, design: .rounded))
                        .foregroundColor(.yellow)
                    Text("pt")
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundColor(.yellow.opacity(0.7))
                }
            }

            Button {
                withAnimation { gameManager.resetGame() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 15, weight: .bold))
                    Text("もう一度")
                        .font(.system(size: 17, weight: .bold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 52)
                .padding(.vertical, 16)
                .background(accentCyan)
                .clipShape(Capsule())
                .shadow(color: accentCyan.opacity(0.5), radius: 16, y: 4)
            }
        }
        .padding()
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
