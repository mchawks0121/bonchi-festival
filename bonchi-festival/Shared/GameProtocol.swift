//
//  GameProtocol.swift
//  bonchi-festival
//
//  Shared message types exchanged between the iOS Controller and the Projector World
//  via Multipeer Connectivity.
//

import Foundation
import CoreGraphics

// MARK: - Message envelope

/// All message types that can be sent between devices.
enum MessageType: String, Codable {
    case launch       // iOS → Projector: slingshot launch
    case gameState    // Projector → iOS: game state update
    case startGame    // iOS → Projector: start the game
    case resetGame    // iOS → Projector: reset to waiting screen
}

/// Top-level wrapper for every Multipeer message.
struct GameMessage: Codable {
    let type: MessageType
    let launchPayload: LaunchPayload?
    let gameStatePayload: GameStatePayload?

    static func launch(_ payload: LaunchPayload) -> GameMessage {
        GameMessage(type: .launch, launchPayload: payload, gameStatePayload: nil)
    }

    static func gameState(_ payload: GameStatePayload) -> GameMessage {
        GameMessage(type: .gameState, launchPayload: nil, gameStatePayload: payload)
    }

    static func startGame() -> GameMessage {
        GameMessage(type: .startGame, launchPayload: nil, gameStatePayload: nil)
    }

    static func resetGame() -> GameMessage {
        GameMessage(type: .resetGame, launchPayload: nil, gameStatePayload: nil)
    }
}

// MARK: - Payloads

/// Sent when the iOS player fires the slingshot.
struct LaunchPayload: Codable {
    /// Launch angle in radians (0 = right, π/2 = up).
    let angle: Float
    /// Normalised launch strength (0.0 – 1.0).
    let power: Float
    /// Unix timestamp for latency compensation.
    let timestamp: Double
}

/// Sent from the Projector to iOS to keep the controller HUD in sync.
struct GameStatePayload: Codable {
    /// "waiting" | "playing" | "finished"
    let state: String
    let score: Int
    let timeRemaining: Double
}

// MARK: - Bug types

/// The three classes of bugs that infect the world.
/// Lore: these are digital anomalies corrupting the world's code.
/// Bug hunters must net them all to restore the world to a clean state.
enum BugType: String, CaseIterable {
    case butterfly = "butterfly"   // 1 pt – fastest of the three  (Null Bug  — minor undefined reference)
    case beetle    = "beetle"      // 3 pt – medium speed          (Virus Bug — self-replicating runtime error)
    case stag      = "stag"        // 5 pt – slowest, largest      (Glitch    — critical corruption, hard to catch)

    var points: Int {
        switch self {
        case .butterfly: return 1
        case .beetle:    return 3
        case .stag:      return 5
        }
    }

    var emoji: String {
        switch self {
        case .butterfly: return "🐞"   // Null Bug
        case .beetle:    return "🦠"   // Virus Bug
        case .stag:      return "👾"   // Glitch
        }
    }

    /// Display name shown in the bug legend.
    var displayName: String {
        switch self {
        case .butterfly: return "Null"
        case .beetle:    return "Virus"
        case .stag:      return "Glitch"
        }
    }

    /// Base movement speed in scene units per second.
    var speed: CGFloat {
        switch self {
        case .butterfly: return 110
        case .beetle:    return 70
        case .stag:      return 45
        }
    }

    /// Diameter of the emoji label (font size).
    var size: CGFloat {
        switch self {
        case .butterfly: return 40
        case .beetle:    return 55
        case .stag:      return 70
        }
    }

    /// Human-readable speed label for the bug legend.
    /// Corresponds to `speed` values: butterfly=110, beetle=70, stag=45.
    var speedLabel: String {
        switch self {
        case .butterfly: return "速い"
        case .beetle:    return "普通"
        case .stag:      return "遅い"
        }
    }

    /// Human-readable rarity label (based on spawn probability).
    /// butterfly 60 %, beetle 30 %, stag 10 %.
    var rarityLabel: String {
        switch self {
        case .butterfly: return "★☆☆"
        case .beetle:    return "★★☆"
        case .stag:      return "★★★"
        }
    }

    /// Short lore description for the bug legend.
    var lore: String {
        switch self {
        case .butterfly: return "軽微な未定義参照エラー"
        case .beetle:    return "自己増殖型ランタイムエラー"
        case .stag:      return "致命的なデータ破壊バグ"
        }
    }
}

// MARK: - Physics categories (used by both BugSpawner and NetProjectile)

enum PhysicsCategory {
    static let none: UInt32 = 0
    static let bug:  UInt32 = 0x1 << 0
    static let net:  UInt32 = 0x1 << 1
}
