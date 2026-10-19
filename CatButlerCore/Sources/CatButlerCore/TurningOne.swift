import Dependencies
import Foundation
import SQLiteData

/// The one-time notice on Today when a Kitten turns one and becomes an Adult, with its Calorie Target either side.
public struct TurningOne: Equatable, Sendable {
  /// Nil without a Weigh-in or the owner's own target, like the Calorie Target itself.
  public var before: CalorieTarget?
  public var after: CalorieTarget?
}

extension Database {
  /// The notice, from the first birthday until the owner dismisses it. Never for a Senior: it's long out of date.
  public func turningOne(for catID: Cat.ID) throws -> TurningOne? {
    @Dependency(\.date.now) var now
    guard let cat = try Cat.find(catID).fetchOne(self) else { throw NotFound() }
    guard !cat.isTurningOneDismissed, cat.lifeStage(on: now) == .adult else { return nil }
    return TurningOne(before: try calorieTarget(for: cat, as: .kitten), after: try calorieTarget(for: cat, as: .adult))
  }

  public func dismissTurningOne(for catID: Cat.ID) throws {
    try Cat.find(catID).update { $0.isTurningOneDismissed = true }.execute(self)
  }
}
