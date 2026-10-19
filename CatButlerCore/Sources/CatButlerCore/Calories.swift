import Dependencies
import Foundation
import SQLiteData

/// The daily calories a Cat should eat. An estimate: individual Cats vary by 30–50%.
public struct CalorieTarget: Equatable, Sendable {
  public var kcal: Double
  /// The owner set it, e.g. to the vet's number, rather than it being calculated.
  public var isOverride: Bool

  public init(kcal: Double, isOverride: Bool) {
    self.kcal = kcal
    self.isOverride = isOverride
  }
}

public struct InvalidCalorieTarget: Error {}

/// The calories a Cat received in a day.
public struct Intake: Equatable, Sendable {
  /// Everything, treats included.
  public var kcal: Double
  public var treatKcal: Double
  public var isApproximate: Bool

  public init(kcal: Double = 0, treatKcal: Double = 0, isApproximate: Bool = false) {
    self.kcal = kcal
    self.treatKcal = treatKcal
    self.isApproximate = isApproximate
  }
}

extension CalorieTarget {
  /// Resting energy requirement, 70 × kg^0.75, times the factor for the Life Stage and neuter status.
  /// Sources: docs/research/cat-calorie-factors.md. The linear 30 × kg + 70 is wrong below 2 kg, so it's never used.
  static func kcal(kilograms: Double, lifeStage: LifeStage, isNeutered: Bool) -> Double {
    let factor =
      switch lifeStage {
      case .kitten: 2.5
      case .adult: isNeutered ? 1.2 : 1.4
      case .senior: 1.2
      }
    return 70 * pow(kilograms, 0.75) * factor
  }
}

extension Database {
  /// From the latest Weigh-in and today's Life Stage, so it follows every new Weigh-in and birthday.
  public func calorieTarget(for catID: Cat.ID) throws -> CalorieTarget? {
    @Dependency(\.date.now) var now
    guard let cat = try Cat.find(catID).fetchOne(self) else { throw NotFound() }
    if let kcal = cat.calorieTargetOverride { return CalorieTarget(kcal: kcal, isOverride: true) }
    guard let weighIn = try WeighIn.latest(for: catID).fetchOne(self) else { return nil }
    let kcal = CalorieTarget.kcal(kilograms: weighIn.kilograms, lifeStage: cat.lifeStage(on: now), isNeutered: cat.isNeutered)
    return CalorieTarget(kcal: kcal, isOverride: false)
  }

  /// Sets the Cat's own Calorie Target, or clears it with nil to go back to the calculated one.
  public func overrideCalorieTarget(_ kcal: Double?, for catID: Cat.ID) throws {
    if let kcal, !(kcal.isFinite && kcal > 0) { throw InvalidCalorieTarget() }
    try Cat.find(catID).update { $0.calorieTargetOverride = #bind(kcal) }.execute(self)
  }
}

extension Food {
  /// How much of this Food, in its serving unit, would on its own meet `target` in a day.
  public func dailyAmount(toMeet target: CalorieTarget) -> Double {
    target.kcal / kcalPerUnit
  }
}
