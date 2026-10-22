import Dependencies
import Foundation
import SQLiteData

/// A dated observation about a Cat's health or behaviour, kept so it can be shown to a vet.
@Table
public nonisolated struct HealthNote: Hashable, Identifiable, Sendable {
  public let id: UUID
  public var catID: Cat.ID
  public var date: Date
  public var text: String
}

extension HealthNote {
  /// The Cat's Health Notes, newest first, as shown to the vet.
  public static func list(for catID: Cat.ID) -> some SelectStatementOf<HealthNote> {
    HealthNote.where { $0.catID.eq(catID) }.order { $0.date.desc() }
  }
}

extension Database {
  @discardableResult
  public func addHealthNote(for catID: Cat.ID, on date: Date, text: String) throws -> HealthNote {
    @Dependency(\.uuid) var uuid
    let note = HealthNote(id: uuid(), catID: catID, date: date, text: text)
    try HealthNote.insert { note }.execute(self)
    return note
  }

  /// Saves a corrected date or text.
  public func updateHealthNote(_ note: HealthNote) throws {
    try HealthNote.update(note).execute(self)
  }

  public func deleteHealthNote(_ id: HealthNote.ID) throws {
    try HealthNote.find(id).delete().execute(self)
  }
}
