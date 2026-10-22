import CatButlerCore
import Dependencies
import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing

/// Miso and Tofu. Now is 12:00.
@Suite(
  .dependency(\.date.now, instant("2026-10-19T12:00:00-04:00")),
  .dependency(\.uuid, .incrementing),
  .dependency(\.calendar, calendar(in: "America/New_York")),
  .dependencies { $0.defaultDatabase = try appDatabase() }
)
struct HealthNoteTests {
  @Dependency(\.defaultDatabase) var database
  let miso: Cat
  let tofu: Cat

  init() throws {
    @Dependency(\.defaultDatabase) var database
    (miso, tofu) = try database.write { db in
      (
        try db.addCat(name: "Miso", photo: nil, birthdate: instant("2026-06-01T00:00:00-04:00"), isNeutered: false, weight: Measurement(value: 2, unit: .kilograms)),
        try db.addCat(name: "Tofu", photo: nil, birthdate: instant("2020-01-01T00:00:00-05:00"), isNeutered: true, weight: Measurement(value: 4.5, unit: .kilograms))
      )
    }
  }

  func notes(of cat: Cat) throws -> [String] {
    try database.read { try HealthNote.list(for: cat.id).fetchAll($0) }.map(\.text)
  }

  @Test func eachCatListsItsOwnHealthNotesNewestFirst() throws {
    try database.write { db in
      try db.addHealthNote(for: miso.id, on: instant("2026-10-19T09:00:00-04:00"), text: "Vomited after breakfast")
      // Backdated: noticed last week, written down today.
      try db.addHealthNote(for: miso.id, on: instant("2026-10-12T20:00:00-04:00"), text: "Not using the litter box")
      try db.addHealthNote(for: tofu.id, on: instant("2026-10-18T10:00:00-04:00"), text: "Sneezing")
    }

    #expect(try notes(of: miso) == ["Vomited after breakfast", "Not using the litter box"])
    #expect(try notes(of: tofu) == ["Sneezing"])
  }

  @Test func aHealthNoteCanBeCorrectedOrDeleted() throws {
    var note = try database.write { db in
      try db.addHealthNote(for: miso.id, on: instant("2026-10-19T09:00:00-04:00"), text: "Vomted")
    }
    try database.write { try $0.addHealthNote(for: miso.id, on: instant("2026-10-15T09:00:00-04:00"), text: "Limping") }

    // Meant last week, before the limp.
    note.text = "Vomited"
    note.date = instant("2026-10-14T09:00:00-04:00")
    try database.write { try $0.updateHealthNote(note) }
    #expect(try notes(of: miso) == ["Limping", "Vomited"])

    try database.write { try $0.deleteHealthNote(note.id) }
    #expect(try notes(of: miso) == ["Limping"])
  }

  @Test func deletingACatDeletesItsHealthNotes() throws {
    try database.write { db in
      try db.addHealthNote(for: miso.id, on: instant("2026-10-19T09:00:00-04:00"), text: "Vomited")
      try db.addHealthNote(for: tofu.id, on: instant("2026-10-19T09:00:00-04:00"), text: "Sneezing")
    }

    try database.write { try $0.deleteCat(tofu.id) }

    #expect(try database.read { try HealthNote.all.fetchAll($0) }.map(\.text) == ["Vomited"])
  }
}
