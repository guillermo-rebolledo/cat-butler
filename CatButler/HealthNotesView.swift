import CatButlerCore
import SQLiteData
import SwiftUI

/// A Cat's Health Notes, newest first, to show the vet.
struct HealthNotesView: View {
  let cat: Cat
  @FetchAll var notes: [HealthNote]
  @Dependency(\.defaultDatabase) var database
  @State private var editing: HealthNote?
  @State private var isAdding = false

  init(cat: Cat) {
    self.cat = cat
    _notes = FetchAll(HealthNote.list(for: cat.id))
  }

  var body: some View {
    List {
      ForEach(notes) { note in
        Button { editing = note } label: {
          VStack(alignment: .leading) {
            Text(note.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
            Text(note.text)
          }
        }
        .tint(.primary)
        .swipeActions { Button("Delete", role: .destructive) { delete(note) } }
      }
      if notes.isEmpty { Text("No Health Notes yet.").foregroundStyle(.secondary) }
    }
    .navigationTitle("\(cat.name)'s Health Notes")
    .toolbar { Button("Add Health Note", systemImage: "plus") { isAdding = true } }
    .sheet(isPresented: $isAdding) { NavigationStack { HealthNoteEditor(catID: cat.id) } }
    .sheet(item: $editing) { note in NavigationStack { HealthNoteEditor(catID: cat.id, note: note) } }
  }

  private func delete(_ note: HealthNote) {
    withErrorReporting { try database.write { try $0.deleteHealthNote(note.id) } }
  }
}

/// Writes down a Health Note, dated now unless backdated, or corrects one when `note` is given.
struct HealthNoteEditor: View {
  let catID: Cat.ID
  var note: HealthNote?
  @Dependency(\.defaultDatabase) var database
  @Dependency(\.date.now) var now
  @Environment(\.dismiss) private var dismiss
  @State private var text: String
  @State private var date: Date

  init(catID: Cat.ID, note: HealthNote? = nil) {
    @Dependency(\.date.now) var now
    self.catID = catID
    self.note = note
    _text = State(initialValue: note?.text ?? "")
    _date = State(initialValue: note?.date ?? now)
  }

  var body: some View {
    Form {
      Section {
        TextField("What did you notice?", text: $text, axis: .vertical).lineLimit(3...)
        DatePicker("Date", selection: $date, in: ...now)
      }
      if note != nil {
        Section { Button("Delete Health Note", role: .destructive, action: delete) }
      }
    }
    .navigationTitle(note == nil ? "Add Health Note" : "Edit Health Note")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(trimmed.isEmpty) }
    }
  }

  private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

  private func save() {
    let saved = withErrorReporting {
      try database.write { db in
        if var note {
          note.text = trimmed
          note.date = date
          try db.updateHealthNote(note)
        } else {
          try db.addHealthNote(for: catID, on: date, text: trimmed)
        }
      }
      return true
    }
    if saved == true { dismiss() }
  }

  private func delete() {
    guard let note else { return }
    let deleted = withErrorReporting {
      try database.write { try $0.deleteHealthNote(note.id) }
      return true
    }
    if deleted == true { dismiss() }
  }
}
