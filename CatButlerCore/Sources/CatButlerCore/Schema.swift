import Dependencies
import Foundation
import SQLiteData

/// The people who share care of the same Cats. Created silently on first run.
@Table
public nonisolated struct Household: Hashable, Identifiable, Sendable {
  public let id: UUID
}

@Table
public nonisolated struct Cat: Hashable, Identifiable, Sendable {
  public let id: UUID
  public var householdID: Household.ID
  public var name: String
  public var photo: Data?
  public var birthdate: Date
  public var isNeutered: Bool

  public func lifeStage(on date: Date) -> LifeStage {
    @Dependency(\.calendar) var calendar
    return LifeStage(birthdate: birthdate, on: date, calendar: calendar)
  }

  /// Turns an approximate age ("about 5 months old") into a birthdate.
  public static func birthdate(aboutMonthsOld months: Int) -> Date {
    @Dependency(\.calendar) var calendar
    @Dependency(\.date.now) var now
    return calendar.date(byAdding: .month, value: -months, to: now) ?? now
  }
}

/// One recorded measurement of a Cat's weight. Always stored in kilograms.
@Table
public nonisolated struct WeighIn: Hashable, Identifiable, Sendable {
  public let id: UUID
  public var catID: Cat.ID
  public var date: Date
  public var kilograms: Double

  public var weight: Measurement<UnitMass> { Measurement(value: kilograms, unit: .kilograms) }
}

extension WeighIn {
  public static func latest(for catID: Cat.ID) -> some SelectStatementOf<WeighIn> {
    WeighIn.where { $0.catID.eq(catID) }.order { $0.date.desc() }.limit(1)
  }
}

extension Database {
  /// Adds a Cat to the Household (creating it on first run) and records its first Weigh-in.
  @discardableResult
  public func addCat(
    name: String,
    photo: Data?,
    birthdate: Date,
    isNeutered: Bool,
    weight: Measurement<UnitMass>
  ) throws -> Cat {
    @Dependency(\.uuid) var uuid
    @Dependency(\.date.now) var now

    let household: Household
    if let existing = try Household.all.fetchOne(self) {
      household = existing
    } else {
      household = Household(id: uuid())
      try Household.insert { household }.execute(self)
    }
    let cat = Cat(
      id: uuid(),
      householdID: household.id,
      name: name,
      photo: photo,
      birthdate: birthdate,
      isNeutered: isNeutered
    )
    try Cat.insert { cat }.execute(self)
    try WeighIn.insert { WeighIn(id: uuid(), catID: cat.id, date: now, kilograms: weight.converted(to: .kilograms).value) }
      .execute(self)
    return cat
  }
}

public func appDatabase() throws -> any DatabaseWriter {
  var configuration = Configuration()
  configuration.foreignKeysEnabled = true
  let database = try defaultDatabase(configuration: configuration)
  var migrator = DatabaseMigrator()
  #if DEBUG
    migrator.eraseDatabaseOnSchemaChange = true
  #endif
  migrator.registerMigration("Create households, cats and weigh-ins") { db in
    try #sql(
      """
      CREATE TABLE "households" (
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid())
      ) STRICT
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TABLE "cats" (
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "householdID" TEXT NOT NULL REFERENCES "households"("id") ON DELETE CASCADE,
        "name" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
        "photo" BLOB,
        "birthdate" TEXT NOT NULL,
        "isNeutered" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0
      ) STRICT
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TABLE "weighIns" (
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "catID" TEXT NOT NULL REFERENCES "cats"("id") ON DELETE CASCADE,
        "date" TEXT NOT NULL,
        "kilograms" REAL NOT NULL
      ) STRICT
      """
    )
    .execute(db)
    try #sql(#"CREATE INDEX "idx_cats_householdID" ON "cats"("householdID")"#).execute(db)
    try #sql(#"CREATE INDEX "idx_weighIns_catID" ON "weighIns"("catID")"#).execute(db)
  }
  try migrator.migrate(database)
  return database
}
