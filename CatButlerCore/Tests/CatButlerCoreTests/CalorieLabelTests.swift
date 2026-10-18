import CatButlerCore
import Testing

struct CalorieLabelTests {
  @Test func kcalPerUnitIsTakenAsIs() {
    #expect(CalorieLabel(kcal: 85, per: .unit).kcal(per: .can, gramsPerUnit: nil) == 85)
    #expect(CalorieLabel(kcal: 380, per: .unit).kcal(per: .cup, gramsPerUnit: nil) == 380)
  }

  @Test func per100gUsesTheGramWeightOfACanOrPouch() {
    #expect(CalorieLabel(kcal: 90, per: .hundredGrams).kcal(per: .can, gramsPerUnit: 85) == 76.5)
    #expect(CalorieLabel(kcal: 80, per: .hundredGrams).kcal(per: .pouch, gramsPerUnit: nil) == nil)
  }

  @Test func perKgConvertsToGrams() {
    #expect(CalorieLabel(kcal: 3_800, per: .kilogram).kcal(per: .gram, gramsPerUnit: nil) == 3.8)
    #expect(CalorieLabel(kcal: 3_600, per: .kilogram).kcal(per: .cup, gramsPerUnit: 110) == 396)
  }

  @Test func aGramWeightOfZeroOrLessIsNoWeight() {
    #expect(CalorieLabel(kcal: 90, per: .hundredGrams).kcal(per: .can, gramsPerUnit: 0) == nil)
    #expect(CalorieLabel(kcal: 90, per: .hundredGrams).kcal(per: .can, gramsPerUnit: -85) == nil)
  }

  @Test func aLabelOfZeroOrLessKcalConvertsToNothing() {
    #expect(CalorieLabel(kcal: 0, per: .unit).kcal(per: .can, gramsPerUnit: nil) == nil)
    #expect(CalorieLabel(kcal: -90, per: .hundredGrams).kcal(per: .can, gramsPerUnit: 85) == nil)
  }

  @Test func gramWeightIsAskedForOnlyWhenNeeded() {
    #expect(CalorieLabel(kcal: 90, per: .hundredGrams).needsGramsPerUnit(for: .can))
    #expect(CalorieLabel(kcal: 3_800, per: .kilogram).needsGramsPerUnit(for: .cup))
    #expect(!CalorieLabel(kcal: 3_800, per: .kilogram).needsGramsPerUnit(for: .gram))
    #expect(!CalorieLabel(kcal: 85, per: .unit).needsGramsPerUnit(for: .pouch))
  }
}
