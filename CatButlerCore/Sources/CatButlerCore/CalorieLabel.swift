import SQLiteData

/// How a Food is measured out: one can, one pouch, one gram or one cup.
public enum ServingUnit: String, CaseIterable, QueryBindable, Sendable {
  case can, pouch, gram, cup
}

/// Calories as printed on a Food's label.
public enum CalorieLabel: Sendable {
  case perUnit(Double), per100g(Double), perKilogram(Double)

  /// Whether converting to kcal per `unit` needs the gram weight of one unit.
  public func needsGramsPerUnit(for unit: ServingUnit) -> Bool {
    if case .perUnit = self { return false }
    return unit != .gram
  }

  /// kcal per one `unit`, or nil when the gram weight is needed but missing.
  public func kcal(per unit: ServingUnit, gramsPerUnit: Double?) -> Double? {
    let (kcal, grams): (Double, Double)
    switch self {
    case .perUnit(let value): return value
    case .per100g(let value): (kcal, grams) = (value, 100)
    case .perKilogram(let value): (kcal, grams) = (value, 1_000)
    }
    guard let unitGrams = unit == .gram ? 1 : gramsPerUnit else { return nil }
    return kcal * unitGrams / grams
  }
}
