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
  case greeting
}

public enum PetEffect: String, Sendable, Hashable, Codable {
  case tea
  case keyboard
  case sweat
  case smoke
  case zzz
}

public enum PetBubble: Sendable, Equatable {
  case focusInvite
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
    effects: Set<PetEffect> = [.tea],
    bubble: PetBubble? = nil,
    averageCPU: Double = 0
  ) {
    self.baseState = baseState
    self.transientState = transientState
    self.effects = effects
    self.bubble = bubble
    self.averageCPU = averageCPU
  }
}
