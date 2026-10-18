import CatButlerCore
import Foundation
import Testing

@Test func weightsUsePoundsOnlyWhereTheDeviceUsesUSUnits() {
  #expect(UnitMass.catWeight(for: Locale(identifier: "en_US")) == .pounds)
  #expect(UnitMass.catWeight(for: Locale(identifier: "es_MX")) == .kilograms)
  #expect(UnitMass.catWeight(for: Locale(identifier: "en_GB")) == .kilograms)
}
