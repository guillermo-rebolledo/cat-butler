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

public struct InvalidHealthNote: Error {}

extension HealthNote {
  /// The Cat's Health Notes, newest first, as shown to the vet.
  public static func history(for catID: Cat.ID) -> some SelectStatementOf<HealthNote> {
    HealthNote.where { $0.catID.eq(catID) }.order { $0.date.desc() }
  }

  /// The text as kept: without surrounding blank space, and never empty.
  static func validated(_ text: String) throws -> String {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { throw InvalidHealthNote() }
    return text
  }
}

extension Database {
  /// Writes down a Health Note, dated now or backdated.
  @discardableResult
  public func addHealthNote(for catID: Cat.ID, on date: Date, text: String) throws -> HealthNote {
    @Dependency(\.uuid) var uuid
    let note = HealthNote(id: uuid(), catID: catID, date: date, text: try HealthNote.validated(text))
    try HealthNote.insert { note }.execute(self)
    return note
  }

  /// Saves a corrected date or text.
  public func updateHealthNote(_ note: HealthNote) throws {
    var note = note
    note.text = try HealthNote.validated(note.text)
    try HealthNote.update(note).execute(self)
  }

  public func deleteHealthNote(_ id: HealthNote.ID) throws {
    try HealthNote.find(id).delete().execute(self)
  }
}
