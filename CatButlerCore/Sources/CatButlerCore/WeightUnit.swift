import Foundation

extension UnitMass {
  /// The unit a Cat's weight is entered and shown in on this device. Storage is always kilograms.
  public static func catWeight(for locale: Locale = .current) -> UnitMass {
    locale.measurementSystem == .us ? .pounds : .kilograms
  }
}
