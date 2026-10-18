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

/// A product or food a Cat eats. Retired Foods leave pickers but keep their details for past records.
@Table
public nonisolated struct Food: Hashable, Identifiable, Sendable {
  public let id: UUID
  public var householdID: Household.ID
  public var name: String
  public var servingUnit: ServingUnit
  public var kcalPerUnit: Double
  public var isTreat: Bool
  public var isFreeFed: Bool
  public var isRetired: Bool
}

extension Food {
  /// Foods the owner can still pick.
  public static let active = Food.where { !$0.isRetired }.order(by: \.name)
  public static let retired = Food.where(\.isRetired).order(by: \.name)
}

extension Database {
  /// The Household, created silently the first time it's needed.
  private func household() throws -> Household {
    @Dependency(\.uuid) var uuid
    if let existing = try Household.all.fetchOne(self) { return existing }
    let household = Household(id: uuid())
    try Household.insert { household }.execute(self)
    return household
  }

  /// Adds a Food to the Household, with calories already converted to kcal per serving unit.
  @discardableResult
  public func addFood(name: String, servingUnit: ServingUnit, kcalPerUnit: Double, isTreat: Bool, isFreeFed: Bool) throws -> Food {
    @Dependency(\.uuid) var uuid
    let food = Food(
      id: uuid(), householdID: try household().id, name: name, servingUnit: servingUnit,
      kcalPerUnit: kcalPerUnit, isTreat: isTreat, isFreeFed: isFreeFed, isRetired: false
    )
    try Food.insert { food }.execute(self)
    return food
  }

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

    let cat = Cat(
      id: uuid(),
      householdID: try household().id,
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
  migrator.registerMigration("Create foods") { db in
    try #sql(
      """
      CREATE TABLE "foods" (
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "householdID" TEXT NOT NULL REFERENCES "households"("id") ON DELETE CASCADE,
        "name" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
        "servingUnit" TEXT NOT NULL,
        "kcalPerUnit" REAL NOT NULL,
        "isTreat" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
        "isFreeFed" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
        "isRetired" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0
      ) STRICT
      """
    )
    .execute(db)
    try #sql(#"CREATE INDEX "idx_foods_householdID" ON "foods"("householdID")"#).execute(db)
  }
  try migrator.migrate(database)
  return database
}
