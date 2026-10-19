/// Calories as printed on a Food's label.
public struct CalorieLabel: Sendable {
  /// What the label's calories are counted against.
  public enum Basis: CaseIterable, Sendable {
    case unit, hundredGrams, kilogram

    var grams: Double? {
      switch self {
      case .unit: nil
      case .hundredGrams: 100
      case .kilogram: 1_000
      }
    }
  }

  public var kcal: Double
  public var basis: Basis

  public init(kcal: Double, per basis: Basis) {
    self.kcal = kcal
    self.basis = basis
  }

  /// Whether converting to kcal per `unit` needs the gram weight of one unit.
  public func needsGramsPerUnit(for unit: ServingUnit) -> Bool {
    basis != .unit && unit != .gram
  }

  /// kcal per one `unit`, or nil when the label's kcal isn't positive, or the gram weight is needed but missing or not positive.
  public func kcal(per unit: ServingUnit, gramsPerUnit: Double?) -> Double? {
    guard kcal > 0 else { return nil }
    guard let basisGrams = basis.grams else { return kcal }
    guard let unitGrams = needsGramsPerUnit(for: unit) ? gramsPerUnit : 1, unitGrams > 0 else { return nil }
    return kcal * unitGrams / basisGrams
  }
}
