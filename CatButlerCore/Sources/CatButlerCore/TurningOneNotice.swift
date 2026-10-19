import Dependencies
import Foundation
import SQLiteData

/// The one-time notice on Today when a Kitten turns one and becomes an Adult, with its Calorie Target either side.
public struct TurningOneNotice: Equatable, Sendable {
  /// Nil without a Weigh-in or the owner's own target, like the Calorie Target itself.
  public var before: CalorieTarget?
  public var after: CalorieTarget?
}

extension Database {
  /// The notice, from the first birthday until the owner dismisses it. Never for a Senior: it's long out of date.
  public func turningOneNotice(for catID: Cat.ID) throws -> TurningOneNotice? {
    @Dependency(\.date.now) var now
    guard let cat = try Cat.find(catID).fetchOne(self) else { throw NotFound() }
    guard !cat.isTurningOneNoticeDone, cat.lifeStage(on: now) == .adult else { return nil }
    return TurningOneNotice(before: try calorieTarget(for: cat, as: .kitten), after: try calorieTarget(for: cat, as: .adult))
  }

  public func dismissTurningOneNotice(for catID: Cat.ID) throws {
    try Cat.find(catID).update { $0.isTurningOneNoticeDone = true }.execute(self)
  }
}
