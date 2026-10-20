import CatButlerCore
import PhotosUI
import SQLiteData
import SwiftUI

/// The Care tab: the Cat's Care Tasks, soonest due first, then its Care Record history.
struct CareView: View {
  // ponytail: the first Cat only, like Today; Cat switching comes with multi-Cat support.
  @FetchOne(Cat.order(by: \.name)) var cat: Cat?

  var body: some View {
    NavigationStack {
      Group {
        if let cat { CareList(cat: cat) } else { List {} }
      }
      .navigationTitle("Care")
    }
  }
}

private struct CareList: View {
  let cat: Cat
  @Dependency(\.date.now) var now
  @Fetch private var tasks: [CareTaskStatus] = []
  @FetchAll var history: [CareRecord]
  @State private var editing: CareTaskDraft?
  @State private var completing: CareTask?

  init(cat: Cat) {
    self.cat = cat
    _history = FetchAll(CareRecord.history(for: cat.id))
  }

  var body: some View {
    List {
      Section {
        ForEach(tasks) { status in
          CareTaskRow(status: status) { completing = status.task }
            .contentShape(.rect)
            .onTapGesture { editing = CareTaskDraft(status.task) }
        }
        if tasks.isEmpty { Text("No Care Tasks yet.").foregroundStyle(.secondary) }
      } header: {
        Text("Care Tasks")
      }
      Section("\(cat.name)'s History") {
        ForEach(history) { record in
          CareRecordRow(record: record, title: tasks.first { $0.id == record.careTaskID }?.task.title ?? "")
        }
        if history.isEmpty { Text("No Care Records yet.").foregroundStyle(.secondary) }
      }
    }
    .toolbar {
      Button("Add Care Task", systemImage: "plus") { editing = CareTaskDraft(catID: cat.id, dueDate: now) }
    }
    .sheet(item: $editing) { draft in
      NavigationStack { CareTaskEditor(draft: draft) }
    }
    .sheet(item: $completing) { task in
      NavigationStack { CareRecordEditor(task: task) }
    }
    .task(id: cat.id) {
      await withErrorReporting { try await $tasks.load(CareTasksRequest(catID: cat.id, refreshedAt: now)) }
    }
  }
}

private struct CareTasksRequest: FetchKeyRequest {
  let catID: Cat.ID
  /// Only here so each load is a new request.
  let refreshedAt: Date

  func fetch(_ db: Database) throws -> [CareTaskStatus] {
    try db.careTasks(for: catID)
  }
}

/// A Care Task with when it's due, an Overdue badge, and a Done button until a one-off task is done.
struct CareTaskRow: View {
  let status: CareTaskStatus
  let onDone: () -> Void

  var body: some View {
    HStack {
      VStack(alignment: .leading) {
        Text(status.task.title).font(.headline)
        Group {
          if status.state == .done {
            Text("Done")
          } else {
            Text("Due \(status.task.dueDate.formatted(date: .abbreviated, time: .omitted))")
          }
          if let interval = status.task.interval { Text(interval.text) }
        }
        .foregroundStyle(.secondary)
      }
      Spacer()
      if status.state == .overdue {
        Text("Overdue")
          .font(.caption.bold())
          .foregroundStyle(.white)
          .padding(.horizontal, 8)
          .padding(.vertical, 2)
          .background(.red, in: .capsule)
      }
      if status.state != .done {
        Button("Done", action: onDone).buttonStyle(.bordered)
          .accessibilityLabel(Text("Mark \(status.task.title) done"))
      }
    }
  }
}

private struct CareRecordRow: View {
  let record: CareRecord
  let title: String

  var body: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading) {
        LabeledContent(title) { Text(record.date.formatted(date: .abbreviated, time: .omitted)) }
        if !record.notes.isEmpty { Text(record.notes).foregroundStyle(.secondary) }
      }
      if let photo = record.photo, let image = UIImage(data: photo) {
        Image(uiImage: image).resizable().scaledToFill().frame(width: 44, height: 44).clipShape(.rect(cornerRadius: 6))
          .accessibilityLabel("Photo")
      }
    }
  }
}

/// A Care Task being added or edited.
struct CareTaskDraft: Identifiable {
  let id = UUID()
  var task: CareTask?
  var catID: Cat.ID
  var title = ""
  var dueDate: Date
  var repeats = false
  var interval = CareInterval(count: 1, unit: .month)

  init(_ task: CareTask) {
    self.task = task
    catID = task.catID
    title = task.title
    dueDate = task.dueDate
    repeats = task.interval != nil
    interval = task.interval ?? interval
  }

  init(catID: Cat.ID, dueDate: Date) {
    self.catID = catID
    self.dueDate = dueDate
  }

  var isValid: Bool {
    !title.trimmingCharacters(in: .whitespaces).isEmpty && (!repeats || interval.count > 0)
  }
}

struct CareTaskEditor: View {
  @State var draft: CareTaskDraft
  @Dependency(\.defaultDatabase) var database
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    Form {
      if draft.task == nil {
        Section {
          ForEach(CareTask.presets, id: \.self) { preset in
            Button {
              draft.title = preset.title
              draft.repeats = true
              draft.interval = preset.interval
            } label: {
              LabeledContent(preset.title) { Text(preset.interval.text) }
            }
            .accessibilityLabel(preset.title)
          }
        } header: {
          Text("Suggestions")
        } footer: {
          Text("Suggested intervals are a starting point. Follow your vet's schedule.")
        }
      }
      Section {
        TextField("Title", text: $draft.title)
        // Any date: the vet card's booster date may be months away.
        DatePicker("Due", selection: $draft.dueDate, displayedComponents: .date)
        Toggle("Repeats", isOn: $draft.repeats)
        if draft.repeats {
          Stepper(value: $draft.interval.count, in: 1...99) { Text(draft.interval.text) }
          Picker("Every", selection: $draft.interval.unit) {
            Text("Weeks").tag(CareInterval.Unit.week)
            Text("Months").tag(CareInterval.Unit.month)
            Text("Years").tag(CareInterval.Unit.year)
          }
        }
      } footer: {
        if draft.repeats { Text("Once done, it's next due one interval after the day it was done.") }
      }
      if draft.task != nil {
        Section { Button("Delete Care Task", role: .destructive, action: delete) }
      }
    }
    .navigationTitle(draft.task == nil ? "Add Care Task" : "Edit Care Task")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!draft.isValid) }
    }
  }

  private func save() {
    let interval = draft.repeats ? draft.interval : nil
    let saved = withErrorReporting {
      try database.write { db in
        if var task = draft.task {
          task.title = draft.title
          task.dueDate = draft.dueDate
          task.interval = interval
          try db.updateCareTask(task)
        } else {
          try db.addCareTask(for: draft.catID, title: draft.title, dueDate: draft.dueDate, interval: interval)
        }
      }
      return true
    }
    if saved == true { dismiss() }
  }

  private func delete() {
    guard let task = draft.task else { return }
    let deleted = withErrorReporting {
      try database.write { try $0.deleteCareTask(task.id) }
      return true
    }
    if deleted == true { dismiss() }
  }
}

/// Marks a Care Task done with a Care Record, dated today or backdated.
struct CareRecordEditor: View {
  let task: CareTask
  @Dependency(\.defaultDatabase) var database
  @Dependency(\.date.now) var now
  @Environment(\.dismiss) private var dismiss
  @State private var date: Date
  @State private var notes = ""
  @State private var photoItem: PhotosPickerItem?
  @State private var photo: Data?

  init(task: CareTask) {
    @Dependency(\.date.now) var now
    self.task = task
    _date = State(initialValue: now)
  }

  var body: some View {
    Form {
      Section {
        DatePicker("Date", selection: $date, in: ...now, displayedComponents: .date)
        TextField("Notes", text: $notes, axis: .vertical)
      }
      Section {
        PhotosPicker(selection: $photoItem, matching: .images) {
          if let photo, let image = UIImage(data: photo) {
            Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 200)
          } else {
            Label("Add Photo", systemImage: "photo")
          }
        }
      }
    }
    .navigationTitle(task.title)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
    }
    .task(id: photoItem) {
      guard let data = try? await photoItem?.loadTransferable(type: Data.self) else { return }
      photo = downscaled(data)
    }
  }

  private func save() {
    let saved = withErrorReporting {
      try database.write { try $0.completeCareTask(task.id, on: date, notes: notes, photo: photo) }
      return true
    }
    if saved == true { dismiss() }
  }
}

extension CareInterval {
  var text: LocalizedStringKey {
    switch unit {
    case .week: "Every ^[\(count) week](inflect: true)"
    case .month: "Every ^[\(count) month](inflect: true)"
    case .year: "Every ^[\(count) year](inflect: true)"
    }
  }
}
