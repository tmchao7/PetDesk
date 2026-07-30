import Foundation

public struct PetStateMachine: Sendable {
  private enum LoadBand: Sendable, Equatable {
    case cool
    case normal
    case busy
    case hot
  }

  public private(set) var snapshot: PetSnapshot

  private let policy: PetPolicy
  private var cpuSamples: [Double] = []
  private var currentBand: LoadBand = .cool
  private var candidateBand: LoadBand?
  private var candidateDuration: Duration = .zero
  private var idleDuration: Duration = .zero
  private var focusActive = false
  private var thermalLevel: ThermalLevel = .nominal
  private var transientRemaining: Duration = .zero

  public init(policy: PetPolicy = PetPolicy()) {
    self.policy = policy
    self.snapshot = PetSnapshot()
  }

  @discardableResult
  public mutating func reduce(_ event: PetEvent, elapsed: Duration) -> PetSnapshot {
    switch event {
    case .systemMetrics(let metrics):
      thermalLevel = metrics.thermalLevel
      record(cpu: metrics.cpuLoad)
      updateLoadBand(elapsed: elapsed)
    case .userIdleChanged(let duration):
      idleDuration = max(duration, .zero)
    case .notificationPulse(let source):
      snapshot.transientState = .startled(source)
      transientRemaining = policy.notificationDuration
    case .focusCommand(let command):
      handleFocus(command)
    case .tick(let duration):
      advanceTransient(by: max(duration, .zero))
    }

    refreshBaseState()
    refreshEffects()
    return snapshot
  }

  private mutating func record(cpu: Double) {
    cpuSamples.append(cpu)
    if cpuSamples.count > policy.sampleCount {
      cpuSamples.removeFirst(cpuSamples.count - policy.sampleCount)
    }
    snapshot.averageCPU = cpuSamples.reduce(0, +) / Double(cpuSamples.count)
  }

  private mutating func updateLoadBand(elapsed: Duration) {
    let target = classifiedBand(for: snapshot.averageCPU)
    guard target != currentBand else {
      candidateBand = nil
      candidateDuration = .zero
      return
    }

    if candidateBand == target {
      candidateDuration += elapsed
    } else {
      candidateBand = target
      candidateDuration = elapsed
    }

    if candidateDuration >= policy.stateDwell {
      currentBand = target
      candidateBand = nil
      candidateDuration = .zero
    }
  }

  private func classifiedBand(for cpu: Double) -> LoadBand {
    switch currentBand {
    case .cool:
      if cpu >= policy.hotThreshold + policy.hysteresis { return .hot }
      if cpu >= policy.busyThreshold + policy.hysteresis { return .busy }
      if cpu >= policy.coolThreshold + policy.hysteresis { return .normal }
      return .cool
    case .normal:
      if cpu >= policy.hotThreshold + policy.hysteresis { return .hot }
      if cpu >= policy.busyThreshold + policy.hysteresis { return .busy }
      if cpu < policy.coolThreshold - policy.hysteresis { return .cool }
      return .normal
    case .busy:
      if cpu >= policy.hotThreshold + policy.hysteresis { return .hot }
      if cpu < policy.busyThreshold - policy.hysteresis {
        return cpu < policy.coolThreshold - policy.hysteresis ? .cool : .normal
      }
      return .busy
    case .hot:
      if cpu < policy.hotThreshold - policy.hysteresis {
        if cpu < policy.coolThreshold - policy.hysteresis { return .cool }
        if cpu < policy.busyThreshold - policy.hysteresis { return .normal }
        return .busy
      }
      return .hot
    }
  }

  private mutating func handleFocus(_ command: FocusCommand) {
    switch command {
    case .start, .resume:
      focusActive = true
      snapshot.bubble = nil
    case .pause:
      focusActive = false
    case .complete:
      focusActive = false
      snapshot.transientState = .celebrating
      snapshot.bubble = .focusComplete
      transientRemaining = policy.notificationDuration
    case .cancel:
      focusActive = false
      snapshot.bubble = nil
    case .showActivityReminder:
      snapshot.transientState = .stretching
      snapshot.bubble = .stretchReminder
      transientRemaining = policy.notificationDuration
    case .snoozeActivity:
      snapshot.transientState = nil
      snapshot.bubble = nil
      transientRemaining = .zero
    }
  }

  private mutating func advanceTransient(by duration: Duration) {
    guard snapshot.transientState != nil else { return }
    transientRemaining -= duration
    if transientRemaining <= .zero {
      transientRemaining = .zero
      snapshot.transientState = nil
    }
  }

  private mutating func refreshBaseState() {
    if focusActive {
      snapshot.baseState = .focusing
    } else if idleDuration >= policy.idleSleepAfter {
      snapshot.baseState = .sleeping
    } else {
      snapshot.baseState = baseState(for: currentBand)
    }
  }

  private func baseState(for band: LoadBand) -> BasePetState {
    switch band {
    case .cool: .drinkingTea
    case .normal: .working
    case .busy: .jogging
    case .hot: .running
    }
  }

  private mutating func refreshEffects() {
    switch snapshot.baseState {
    case .drinkingTea:
      snapshot.effects = [.tea]
    case .working, .focusing:
      snapshot.effects = [.keyboard]
    case .jogging:
      snapshot.effects = []
    case .running:
      snapshot.effects = [.sweat]
    case .sleeping:
      snapshot.effects = [.zzz]
    }

    if thermalLevel == .serious || thermalLevel == .critical {
      snapshot.effects.insert(.smoke)
    }
  }
}
