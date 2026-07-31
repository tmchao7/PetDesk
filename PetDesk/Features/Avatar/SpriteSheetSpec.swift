import CoreGraphics
import Foundation

/// 精灵图规格：8 列 × 8 行，每帧 192×208。
public enum SpriteSheetSpec {
  public static let frameWidth: CGFloat = 192
  public static let frameHeight: CGFloat = 208
  public static let columns = 8

  public static var sheetWidth: CGFloat { frameWidth * CGFloat(columns) }
  public static var sheetHeight: CGFloat { frameHeight * CGFloat(AnimationRow.allCases.count) }
}

/// 动画行映射：每种动作一行，绑定 PetDesk 宠物状态。
public enum AnimationRow: Int, CaseIterable, Sendable {
  case idle = 0
  case walking = 1
  case running = 2
  case working = 3
  case drinking = 4
  case sleeping = 5
  case happy = 6
  case surprised = 7

  /// 该行动画帧数。
  public var frameCount: Int {
    switch self {
    case .idle: 6
    case .walking: 8
    case .running: 8
    case .working: 6
    case .drinking: 6
    case .sleeping: 6
    case .happy: 5
    case .surprised: 4
    }
  }

  /// 循环方式：restart 播完跳回第 0 帧；pingpong 到头反向播放。
  public var loopsPingPong: Bool {
    switch self {
    case .idle, .drinking, .sleeping: true
    default: false
    }
  }

  /// 推荐帧率。
  public var framesPerSecond: Int {
    switch self {
    case .walking, .running: 14
    default: 10
    }
  }
}

/// 宠物当前动画状态（由 PetSnapshot 映射而来）。
public struct PetAnimState: Sendable, Equatable {
  public let row: AnimationRow

  public init(row: AnimationRow) {
    self.row = row
  }

  /// 从宠物快照的 baseState + transientState 映射动画行。
  public static func from(
    baseState: BasePetState,
    transient: TransientPetState?
  ) -> PetAnimState {
    if let transient {
      switch transient {
      case .startled: return PetAnimState(row: .surprised)
      case .celebrating: return PetAnimState(row: .happy)
      case .stretching, .greeting: return PetAnimState(row: .idle)
      }
    }
    switch baseState {
    case .drinkingTea: return PetAnimState(row: .drinking)
    case .working, .focusing: return PetAnimState(row: .working)
    case .jogging: return PetAnimState(row: .walking)
    case .running: return PetAnimState(row: .running)
    case .sleeping: return PetAnimState(row: .sleeping)
    }
  }

  /// 从精灵图中裁出该动画行的帧区域。
  public func frameRect(index: Int) -> CGRect {
    let clamped = max(0, min(index, row.frameCount - 1))
    return CGRect(
      x: CGFloat(clamped) * SpriteSheetSpec.frameWidth,
      y: CGFloat(row.rawValue) * SpriteSheetSpec.frameHeight,
      width: SpriteSheetSpec.frameWidth,
      height: SpriteSheetSpec.frameHeight
    )
  }
}
