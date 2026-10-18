import CatButlerCore
import Testing

struct CalorieLabelTests {
  @Test func kcalPerUnitIsTakenAsIs() {
    #expect(CalorieLabel.perUnit(85).kcal(per: .can, gramsPerUnit: nil) == 85)
    #expect(CalorieLabel.perUnit(380).kcal(per: .cup, gramsPerUnit: nil) == 380)
  }

  @Test func per100gUsesTheGramWeightOfACanOrPouch() {
    #expect(CalorieLabel.per100g(90).kcal(per: .can, gramsPerUnit: 85) == 76.5)
    #expect(CalorieLabel.per100g(80).kcal(per: .pouch, gramsPerUnit: nil) == nil)
  }

  @Test func perKgConvertsToGrams() {
    #expect(CalorieLabel.perKilogram(3_800).kcal(per: .gram, gramsPerUnit: nil) == 3.8)
    #expect(CalorieLabel.perKilogram(3_600).kcal(per: .cup, gramsPerUnit: 110) == 396)
  }

  @Test func gramWeightIsAskedForOnlyWhenNeeded() {
    #expect(CalorieLabel.per100g(90).needsGramsPerUnit(for: .can))
    #expect(CalorieLabel.perKilogram(3_800).needsGramsPerUnit(for: .cup))
    #expect(!CalorieLabel.perKilogram(3_800).needsGramsPerUnit(for: .gram))
    #expect(!CalorieLabel.perUnit(85).needsGramsPerUnit(for: .pouch))
  }
}
