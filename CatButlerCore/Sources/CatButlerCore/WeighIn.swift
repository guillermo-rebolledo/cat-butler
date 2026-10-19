import Dependencies
import Foundation
import SQLiteData

public struct InvalidWeight: Error {}

extension WeighIn {
  /// Whether a weight, in any unit, can be recorded: a positive number.
  public static func isValid(_ value: Double) -> Bool {
    value.isFinite && value > 0
  }

  /// Days from one Weigh-in to the next: every 2 weeks for a growing Kitten, monthly after that.
  static func daysBetween(for lifeStage: LifeStage) -> Int {
    switch lifeStage {
    case .kitten: 14
    case .adult, .senior: 30
    }
  }
}

extension Database {
  /// Records a Weigh-in, stored in kilograms whatever unit it was entered in.
  @discardableResult
  public func recordWeighIn(_ weight: Measurement<UnitMass>, for catID: Cat.ID, on date: Date) throws -> WeighIn {
    @Dependency(\.uuid) var uuid
    guard WeighIn.isValid(weight.value) else { throw InvalidWeight() }
    var weighIn = WeighIn(id: uuid(), catID: catID, date: date, kilograms: 0)
    weighIn.weight = weight
    try WeighIn.insert { weighIn }.execute(self)
    return weighIn
  }

  /// Saves a corrected weight or date.
  public func updateWeighIn(_ weighIn: WeighIn) throws {
    guard WeighIn.isValid(weighIn.kilograms) else { throw InvalidWeight() }
    try WeighIn.update(weighIn).execute(self)
  }

  public func deleteWeighIn(_ id: WeighIn.ID) throws {
    try WeighIn.find(id).delete().execute(self)
  }

  /// Whether the Today view should prompt for a Weigh-in: from the start of the local day 14 days (Kitten) or
  /// 30 days (Adult or Senior) after the last one. Due straight away for a Cat never weighed.
  public func isWeighInDue(for catID: Cat.ID) throws -> Bool {
    @Dependency(\.calendar) var calendar
    @Dependency(\.date.now) var now
    guard let cat = try Cat.find(catID).fetchOne(self) else { throw NotFound() }
    guard let last = try WeighIn.latest(for: catID).fetchOne(self) else { return true }
    let day = calendar.startOfDay(for: last.date)
    let due = { (lifeStage: LifeStage) in calendar.date(byAdding: .day, value: WeighIn.daysBetween(for: lifeStage), to: day)! }
    // The Life Stage on a Kitten's due date, so a Weigh-in already due stays due after the first birthday.
    return now >= due(cat.lifeStage(on: due(.kitten)))
  }
}
