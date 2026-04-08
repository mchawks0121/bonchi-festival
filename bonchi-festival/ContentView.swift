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
            // Dark nature gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.10, blue: 0.03),
                    Color(red: 0.01, green: 0.05, blue: 0.01)
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

                Text("🦟")
                    .font(.system(size: 90))
                    .padding(.top, 48)

                Text("君は、バグハンター")
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)

                Text("You are the Bug Hunter")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.65))

                // Connection status pill
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

                // Start button — always enabled; connection is optional
                Button {
                    withAnimation { gameManager.startGame() }
                } label: {
                    Text("ゲームスタート")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 52)
                        .padding(.vertical, 16)
                        .background(Color.green)
                        .clipShape(Capsule())
                        .shadow(color: .green.opacity(0.5), radius: 12)
                }

                // Bug legend card
                VStack(spacing: 12) {
                    Text("スコア表")
                        .font(.headline.bold())
                        .foregroundColor(.white)

                    HStack(spacing: 32) {
                        BugLegendItem(emoji: "🦋", pts: 1, name: "チョウ")
                        BugLegendItem(emoji: "🐛", pts: 3, name: "カブトムシ")
                        BugLegendItem(emoji: "🪲", pts: 5, name: "クワガタ")
                    }
                }
                .padding(20)
                .background(Color.white.opacity(0.08))
                .cornerRadius(18)
                .padding(.horizontal, 24)

                // How to play
                VStack(alignment: .leading, spacing: 8) {
                    Text("遊び方").font(.headline).foregroundColor(.white)
                    Text("画面下のスリングショットを\n引っ張って網を飛ばそう！\n制限時間は90秒。たくさん捕まえてハイスコアを目指せ！")
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

            // ── HUD + slingshot overlaid on the AR scene ─────────────────
            VStack(spacing: 0) {

                // ── HUD ──────────────────────────────────────────────────
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SCORE")
                            .font(.caption2.bold())
                            .foregroundColor(.white.opacity(0.9))
                        Text("\(gameManager.score)")
                            .font(.system(size: 44, weight: .black, design: .rounded))
                            .foregroundColor(.yellow)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("TIME")
                            .font(.caption2.bold())
                            .foregroundColor(.white.opacity(0.9))
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

                // ── Slingshot area ───────────────────────────────────────
                SlingshotView()
                    .environmentObject(gameManager)
                    .frame(height: 340)
                    .background(Color.black.opacity(0.25))
            }
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

            Text("タイムアップ！").font(.largeTitle.bold()).foregroundColor(.white)

            Text("最終スコア").font(.title3).foregroundColor(.white.opacity(0.65))

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
                Text("もう一度プレイ")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 52)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .clipShape(Capsule())
                    .shadow(color: .blue.opacity(0.5), radius: 12)
            }
        }
        .padding()
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
