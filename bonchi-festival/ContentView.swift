//
//  ContentView.swift
//  bonchi-festival
//
//  iOS Controller: root view that routes between Waiting, Playing, and Finished screens.
//

import SwiftUI

// MARK: - Root

struct ContentView: View {

    @StateObject private var gameManager = GameManager()

    var body: some View {
        ZStack {
            // Digital-corruption gradient: deep navy → almost-black
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.02, blue: 0.14),
                    Color(red: 0.01, green: 0.01, blue: 0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            switch gameManager.state {
            case .waiting:
                WaitingView()
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

                    Text("👾")
                        .font(.system(size: compact ? 60 : 90))
                        .padding(.top, compact ? 20 : 48)

                    Text("君は、バグハンター")
                        .font(compact ? .title2.bold() : .largeTitle.bold())
                        .foregroundColor(.white)

                    Text("バグに侵食されたワールドを救え！")
                        .font(compact ? .callout : .title3)
                        .foregroundColor(Color(red: 0.4, green: 0.9, blue: 1.0).opacity(0.85))
                        .multilineTextAlignment(.center)

                    // ── Mode selection ───────────────────────────────────────
                    VStack(spacing: 8) {
                        Text("プレイモードを選択")
                            .font(.caption.bold())
                            .foregroundColor(.white.opacity(0.55))

                        VStack(spacing: 8) {
                            ModeCard(
                                icon: "📱",
                                title: "スタンドアロン",
                                subtitle: "AR のみ（1台完結）",
                                isSelected: gameManager.gameMode == .standalone,
                                compact: compact
                            )
                            .onTapGesture { gameManager.selectMode(.standalone) }

                            ModeCard(
                                icon: "🎮",
                                title: "プロジェクター",
                                subtitle: "クライアント（コントローラー）",
                                isSelected: gameManager.gameMode == .projectorClient,
                                compact: compact
                            )
                            .onTapGesture { gameManager.selectMode(.projectorClient) }

                            ModeCard(
                                icon: "📺",
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
                                .frame(width: 12, height: 12)
                            Text(gameManager.isConnected
                                 ? "プロジェクターに接続済み"
                                 : "プロジェクターを探しています…")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.85))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                        .transition(.opacity.combined(with: .scale))
                        .animation(.easeInOut(duration: 0.25), value: gameManager.isConnected)
                    }

                    // Start button
                    Button {
                        withAnimation { gameManager.startGame() }
                    } label: {
                        Text("デバッグ開始")
                            .font(.title2.bold())
                            .foregroundColor(.black)
                            .padding(.horizontal, compact ? 36 : 52)
                            .padding(.vertical, compact ? 12 : 16)
                            .background(Color(red: 0.2, green: 1.0, blue: 0.8))
                            .clipShape(Capsule())
                            .shadow(color: Color(red: 0.2, green: 1.0, blue: 0.8).opacity(0.6), radius: 16)
                    }

                    // Bug legend card
                    VStack(spacing: compact ? 8 : 12) {
                        Text("出現バグ一覧")
                            .font(.headline.bold())
                            .foregroundColor(.white)

                        VStack(spacing: compact ? 6 : 8) {
                            ForEach(BugType.allCases, id: \.rawValue) { bug in
                                BugLegendRow(bug: bug, compact: compact)
                            }
                        }
                    }
                    .padding(compact ? 14 : 20)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(18)
                    .padding(.horizontal, 24)

                    // How to play
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ミッション").font(.headline).foregroundColor(.white)
                        Text("ワールドはバグに蝕まれている。\nスリングショットで網を飛ばし、バグを捕まえてデバッグせよ！\n制限時間は90秒。Glitchほど手強く、倒すほど価値がある。")
                            .font(compact ? .footnote : .body)
                            .foregroundColor(.white.opacity(0.75))
                            .multilineTextAlignment(.leading)
                    }
                    .padding(compact ? 14 : 20)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(18)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
                .frame(minWidth: geo.size.width)
            }
        }
    }
}

// MARK: - Mode Card

struct ModeCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let isSelected: Bool
    var compact: Bool = false

    var body: some View {
        Group {
            if compact {
                // Horizontal layout for compact screens
                HStack(spacing: 12) {
                    Text(icon).font(.system(size: 28))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.caption.bold())
                            .foregroundColor(.white)
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            } else {
                // Vertical layout for regular screens
                VStack(spacing: 6) {
                    Text(icon).font(.system(size: 36))
                    Text(title)
                        .font(.caption.bold())
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isSelected
                      ? Color(red: 0.2, green: 1.0, blue: 0.8).opacity(0.18)
                      : Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    isSelected
                        ? Color(red: 0.2, green: 1.0, blue: 0.8)
                        : Color.white.opacity(0.15),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

struct BugLegendRow: View {
    let bug: BugType
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Text(bug.emoji)
                .font(.system(size: compact ? 28 : 36))
                .frame(width: compact ? 36 : 44)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(bug.displayName)
                        .font(.caption.bold())
                        .foregroundColor(.white)
                    Text(bug.rarityLabel)
                        .font(.caption2)
                        .foregroundColor(.yellow)
                }
                Text(bug.lore)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.55))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(bug.points) pt")
                    .font(.caption.bold())
                    .foregroundColor(.yellow)
                Text(bug.speedLabel)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.vertical, compact ? 4 : 6)
        .padding(.horizontal, 8)
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
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

            Text("🔧").font(.system(size: 72))

            Text("デバッグ完了！")
                .font(.largeTitle.bold())
                .foregroundColor(Color(red: 0.2, green: 1.0, blue: 0.8))

            Text("修正したバグ").font(.title3).foregroundColor(.white.opacity(0.65))

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("\(gameManager.score)")
                    .font(.system(size: 96, weight: .black, design: .rounded))
                    .foregroundColor(.yellow)
                Text("pt")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.yellow.opacity(0.8))
            }

            Button {
                withAnimation { gameManager.resetGame() }
            } label: {
                Text("再デバッグ")
                    .font(.title2.bold())
                    .foregroundColor(.black)
                    .padding(.horizontal, 52)
                    .padding(.vertical, 16)
                    .background(Color(red: 0.2, green: 1.0, blue: 0.8))
                    .clipShape(Capsule())
                    .shadow(color: Color(red: 0.2, green: 1.0, blue: 0.8).opacity(0.5), radius: 12)
            }
        }
        .padding()
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
