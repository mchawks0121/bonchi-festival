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
        ScrollView {
            VStack(spacing: 28) {

                Text("👾")
                    .font(.system(size: 90))
                    .padding(.top, 48)

                Text("君は、バグハンター")
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)

                Text("バグに侵食されたワールドを救え！")
                    .font(.title3)
                    .foregroundColor(Color(red: 0.4, green: 0.9, blue: 1.0).opacity(0.85))
                    .multilineTextAlignment(.center)

                // ── Mode selection ───────────────────────────────────────
                VStack(spacing: 10) {
                    Text("プレイモードを選択")
                        .font(.caption.bold())
                        .foregroundColor(.white.opacity(0.55))

                    HStack(spacing: 14) {
                        ModeCard(
                            icon: "📱",
                            title: "スタンドアロン",
                            subtitle: "AR のみ",
                            isSelected: gameManager.gameMode == .standalone
                        )
                        .onTapGesture { gameManager.selectMode(.standalone) }

                        ModeCard(
                            icon: "📡",
                            title: "プロジェクター",
                            subtitle: "接続モード",
                            isSelected: gameManager.gameMode == .projector
                        )
                        .onTapGesture { gameManager.selectMode(.projector) }
                    }
                    .padding(.horizontal, 24)
                }

                // Connection status pill — only in projector mode
                if gameManager.gameMode == .projector {
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
                        .padding(.horizontal, 52)
                        .padding(.vertical, 16)
                        .background(Color(red: 0.2, green: 1.0, blue: 0.8))
                        .clipShape(Capsule())
                        .shadow(color: Color(red: 0.2, green: 1.0, blue: 0.8).opacity(0.6), radius: 16)
                }

                // Bug legend card
                VStack(spacing: 12) {
                    Text("出現バグ一覧")
                        .font(.headline.bold())
                        .foregroundColor(.white)

                    HStack(spacing: 32) {
                        BugLegendItem(emoji: "🐞", pts: 1, name: "Null")
                        BugLegendItem(emoji: "🦠", pts: 3, name: "Virus")
                        BugLegendItem(emoji: "👾", pts: 5, name: "Glitch")
                    }
                }
                .padding(20)
                .background(Color.white.opacity(0.08))
                .cornerRadius(18)
                .padding(.horizontal, 24)

                // How to play
                VStack(alignment: .leading, spacing: 8) {
                    Text("ミッション").font(.headline).foregroundColor(.white)
                    Text("ワールドはバグに蝕まれている。\nスリングショットで網を飛ばし、バグを捕まえてデバッグせよ！\n制限時間は90秒。Glitchほど手強く、倒すほど価値がある。")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.75))
                        .multilineTextAlignment(.leading)
                }
                .padding(20)
                .background(Color.white.opacity(0.08))
                .cornerRadius(18)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
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

    var body: some View {
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

struct BugLegendItem: View {
    let emoji: String
    let pts: Int
    let name: String

    var body: some View {
        VStack(spacing: 4) {
            Text(emoji).font(.system(size: 44))
            Text("\(pts) pt")
                .font(.caption.bold())
                .foregroundColor(.yellow)
            Text(name)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.7))
        }
    }
}

// MARK: - Playing Screen

struct PlayingView: View {
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
            .allowsHitTesting(false)

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
