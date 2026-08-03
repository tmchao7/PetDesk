import Foundation

public enum BasePetState: String, Sendable, Equatable, Codable {
  case drinkingTea
  case working
  case jogging
  case running
  case sleeping
  case focusing
}

public enum TransientPetState: Sendable, Equatable {
  case startled(NotificationSource)
  case celebrating
  case stretching
}

public enum PetEffect: String, Sendable, Hashable, Codable {
  case sweat
  case smoke
}

public enum PetBubble: Sendable, Equatable {
  case focusComplete
  case stretchReminder
  /// 状态持续时长提醒（如“你已连续专注 25 分钟”）。
  case stateDurationReminder(String)
}

public struct PetSnapshot: Sendable, Equatable {
  public var baseState: BasePetState
  public var transientState: TransientPetState?
  public var effects: Set<PetEffect>
  public var bubble: PetBubble?
  public var averageCPU: Double

  public init(
    baseState: BasePetState = .drinkingTea,
    transientState: TransientPetState? = nil,
    effects: Set<PetEffect> = [],
    bubble: PetBubble? = nil,
    averageCPU: Double = 0
  ) {
    self.baseState = baseState
    self.transientState = transientState
    self.effects = effects
    self.bubble = bubble
    self.averageCPU = averageCPU
  }

  /// 显示相关字段是否相同：baseState/transientState/effects/bubble 决定宠物
  /// 外观与气泡；averageCPU 只进诊断窗口，不参与判定。AppEnvironment 用它
  /// 做发布门控——CPU 读数每秒都在变，但宠物外观不变时无需重绘视图。
  public func displayEquals(_ other: PetSnapshot) -> Bool {
    baseState == other.baseState
      && transientState == other.transientState
      && effects == other.effects
      && bubble == other.bubble
  }
}
