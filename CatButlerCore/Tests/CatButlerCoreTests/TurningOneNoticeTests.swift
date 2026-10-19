import CatButlerCore
import Dependencies
import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing

@Suite(
  .dependency(\.date.now, instant("2026-10-19T12:00:00-04:00")),
  .dependency(\.uuid, .incrementing),
  .dependency(\.calendar, calendar(in: "America/New_York")),
  .dependencies { $0.defaultDatabase = try appDatabase() }
)
struct TurningOneNoticeTests {
  @Dependency(\.defaultDatabase) var database

  /// A 4 kg neutered Cat born on 25 October 2025 in the afternoon, as the birthday picker keeps the time of day.
  func addKitten(born birthdate: String = "2025-10-25T15:00:00-04:00") throws -> Cat {
    try database.write { db in
      try db.addCat(
        name: "Miso", photo: nil, birthdate: instant(birthdate), isNeutered: true,
        weight: Measurement(value: 4, unit: .kilograms)
      )
    }
  }

  func turningOneNotice(_ cat: Cat, at iso8601: String) throws -> TurningOneNotice? {
    try withDependencies { $0.date.now = instant(iso8601) } operation: {
      try database.read { try $0.turningOneNotice(for: cat.id) }
    }
  }

  @Test func theNoticeAppearsFromTheFirstBirthdayUntilDismissed() throws {
    let cat = try addKitten()
    #expect(try turningOneNotice(cat, at: "2026-10-24T23:59:00-04:00") == nil)
    // From the start of the birthday, not the time of day it was entered.
    let notice = try #require(try turningOneNotice(cat, at: "2026-10-25T00:00:00-04:00"))
    // 70 × 4^0.75 × 2.5, then × 1.2
    #expect(notice.before?.kcal.rounded() == 495)
    #expect(notice.after?.kcal.rounded() == 238)
    #expect(try turningOneNotice(cat, at: "2026-10-28T09:00:00-04:00") == notice)

    try withDependencies { $0.date.now = instant("2026-10-28T09:00:00-04:00") } operation: {
      try database.write { try $0.dismissTurningOneNotice(for: cat.id) }
    }
    #expect(try turningOneNotice(cat, at: "2026-10-28T09:01:00-04:00") == nil)
    #expect(try turningOneNotice(cat, at: "2026-11-30T09:00:00-05:00") == nil)
  }

  @Test func aCatAddedAsAnAdultNeverGetsTheNotice() throws {
    let cat = try addKitten(born: "2020-05-01T00:00:00-04:00")
    #expect(try turningOneNotice(cat, at: "2026-10-19T12:00:00-04:00") == nil)
  }

  @Test func theOwnersOwnTargetStaysTheSameEitherSide() throws {
    let cat = try addKitten()
    try database.write { try $0.overrideCalorieTarget(210, for: cat.id) }
    let notice = try #require(try turningOneNotice(cat, at: "2026-10-26T09:00:00-04:00"))
    #expect(notice.before == CalorieTarget(kcal: 210, isOverride: true))
    #expect(notice.after == CalorieTarget(kcal: 210, isOverride: true))
  }

  @Test func aSeniorDoesNotGetTheNoticeItNeverDismissed() throws {
    let cat = try addKitten()
    #expect(try turningOneNotice(cat, at: "2035-10-25T09:00:00-04:00") == nil)
  }
}
