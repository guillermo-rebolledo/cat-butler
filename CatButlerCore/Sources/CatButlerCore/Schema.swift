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
  /// The owner's own daily Calorie Target, e.g. from the vet, replacing the calculated one.
  public var calorieTargetOverride: Double?

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

/// How a Food is measured out: one can, one pouch, one gram or one cup.
public enum ServingUnit: String, CaseIterable, QueryBindable, Sendable {
  case can, pouch, gram, cup
}

/// A specific food a Cat eats. Retired Foods leave pickers but keep their details for past Feedings.
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
  // ponytail: NOCASE folds ASCII only, so "Éclair" sorts after "Zebra"; switch to a Unicode collation if that shows up.
  public static let active = Food.where { !$0.isRetired }.order { $0.name.collate(.nocase) }
  public static let retired = Food.where(\.isRetired).order { $0.name.collate(.nocase) }
}

extension Database {
  /// The Household, created silently the first time it's needed.
  // ponytail: assumes one Household per database; look it up by the signed-in member once Household sharing lands.
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
      isNeutered: isNeutered,
      calorieTargetOverride: nil
    )
    try Cat.insert { cat }.execute(self)
    try recordWeighIn(weight, for: cat.id, on: now)
    return cat
  }

  /// Records a Weigh-in, stored in kilograms whatever unit it was entered in.
  public func recordWeighIn(_ weight: Measurement<UnitMass>, for catID: Cat.ID, on date: Date) throws {
    @Dependency(\.uuid) var uuid
    try WeighIn.insert { WeighIn(id: uuid(), catID: catID, date: date, kilograms: weight.converted(to: .kilograms).value) }
      .execute(self)
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
  // Only "catID" is a foreign key: SQLiteData shares a record with the Household only when it has a single
  // foreign key, so the Food and Meal links are plain columns kept up by the app.
  migrator.registerMigration("Create meals and feedings") { db in
    try #sql(
      """
      CREATE TABLE "meals" (
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "catID" TEXT NOT NULL REFERENCES "cats"("id") ON DELETE CASCADE,
        "minuteOfDay" INTEGER NOT NULL,
        "foodID" TEXT NOT NULL,
        "amount" REAL NOT NULL,
        "startsAt" TEXT NOT NULL
      ) STRICT
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TABLE "feedings" (
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "catID" TEXT NOT NULL REFERENCES "cats"("id") ON DELETE CASCADE,
        "foodID" TEXT NOT NULL,
        "amount" REAL NOT NULL,
        "date" TEXT NOT NULL,
        "mealID" TEXT,
        "kcal" REAL NOT NULL
      ) STRICT
      """
    )
    .execute(db)
    try #sql(#"CREATE INDEX "idx_meals_catID" ON "meals"("catID")"#).execute(db)
    try #sql(#"CREATE INDEX "idx_meals_foodID" ON "meals"("foodID")"#).execute(db)
    try #sql(#"CREATE INDEX "idx_feedings_catID_date" ON "feedings"("catID", "date")"#).execute(db)
    try #sql(#"CREATE INDEX "idx_feedings_foodID" ON "feedings"("foodID")"#).execute(db)
    try #sql(#"CREATE INDEX "idx_feedings_mealID" ON "feedings"("mealID")"#).execute(db)
  }
  // Nullable, so records synced from an older build still fit.
  migrator.registerMigration("Add Calorie Target overrides and eaten fractions") { db in
    try #sql(#"ALTER TABLE "cats" ADD COLUMN "calorieTargetOverride" REAL"#).execute(db)
    try #sql(#"ALTER TABLE "feedings" ADD COLUMN "eatenFraction" REAL"#).execute(db)
  }
  try migrator.migrate(database)
  return database
}
