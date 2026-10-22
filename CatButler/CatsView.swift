import CatButlerCore
import PhotosUI
import SQLiteData
import SwiftUI

/// The Cats tab: every Cat, to add another or edit one and its Meals, then the Archived Cats.
struct CatsView: View {
  @FetchAll(Cat.inCare) var cats
  @FetchAll(Cat.archived) var archived
  @State private var isAdding = false

  var body: some View {
    NavigationStack {
      List {
        ForEach(cats, content: row)
        if !archived.isEmpty { Section("Archived") { ForEach(archived, content: row) } }
      }
      .navigationTitle("Cats")
      .toolbar { Button("Add Cat", systemImage: "plus") { isAdding = true } }
      .sheet(isPresented: $isAdding) { NavigationStack { CatEditor() } }
    }
  }

  private func row(_ cat: Cat) -> some View {
    NavigationLink { CatEditor(cat: cat) } label: { CatSummary(cat: cat) }
  }
}

/// Today and Care once every Cat is archived.
struct NoCatsInCare: View {
  var body: some View {
    ContentUnavailableView("No Cats in Care", systemImage: "cat", description: Text("Add a Cat, or unarchive one, in Cats."))
  }
}

/// Picks the Cat Today and Care show, once there's more than one.
struct CatSwitcher: ToolbarContent {
  let cats: [Cat]
  @Binding var catID: Cat.ID?

  var body: some ToolbarContent {
    ToolbarItem(placement: .topBarLeading) {
      if cats.count > 1, let cat = cats.selected(catID) {
        Picker("Cat", selection: Binding { cat.id } set: { catID = $0 }) {
          ForEach(cats) { Text($0.name).tag($0.id) }
        }
      }
    }
  }
}

extension [Cat] {
  /// The chosen Cat, or the first while none is chosen or the chosen one is gone.
  func selected(_ id: Cat.ID?) -> Cat? {
    first { $0.id == id } ?? first
  }
}

/// Adds a Cat, as first-run step 1 or from the Cats tab, or edits one. Its weight is asked once, as the first
/// Weigh-in; after that it's on the weight chart.
struct CatEditor: View {
  let cat: Cat?
  let isFirstRun: Bool
  @Dependency(\.defaultDatabase) var database
  @Environment(\.dismiss) private var dismiss
  @State private var name: String
  @State private var photoItem: PhotosPickerItem?
  @State private var photo: Data?
  @State private var knowsBirthday: Bool
  @State private var birthdate: Date
  @State private var ageYears = 0
  @State private var ageMonths = 3
  @State private var isNeutered: Bool
  @State private var weight: Double?
  @State private var isConfirmingDelete = false
  private let weightUnit = UnitMass.catWeight()

  init(cat: Cat? = nil, isFirstRun: Bool = false) {
    self.cat = cat
    self.isFirstRun = isFirstRun
    _name = State(initialValue: cat?.name ?? "")
    _photo = State(initialValue: cat?.photo)
    _knowsBirthday = State(initialValue: cat != nil)
    _birthdate = State(initialValue: cat?.birthdate ?? Date())
    _isNeutered = State(initialValue: cat?.isNeutered ?? false)
  }

  var body: some View {
    Form {
      Section {
        PhotosPicker(selection: $photoItem, matching: .images) {
          CatPhoto(data: photo).frame(width: 96, height: 96)
        }
        .frame(maxWidth: .infinity)
        TextField("Name", text: $name)
      }
      Section("Age") {
        Toggle("I know the exact birthday", isOn: $knowsBirthday)
        if knowsBirthday {
          DatePicker("Birthday", selection: $birthdate, in: ...Date(), displayedComponents: .date)
        } else {
          Stepper("About \(ageYears) years", value: $ageYears, in: 0...30)
          Stepper("and \(ageMonths) months old", value: $ageMonths, in: 0...11)
        }
      }
      Section {
        Toggle("Neutered", isOn: $isNeutered)
        if cat == nil { NumberField("Weight", value: $weight, unit: weightUnit.symbol) }
      }
      if let cat {
        Section {
          if cat.isArchived {
            NavigationLink("Weight Chart") { WeightView(cat: cat) }
            NavigationLink("Care") { CareList(cat: cat).navigationTitle("\(cat.name)'s Care") }
          } else {
            NavigationLink("Meals") { MealScheduleEditor(cat: cat) }
          }
        }
        Section {
          Button(cat.isArchived ? "Unarchive Cat" : "Archive Cat") { toggleArchived(cat) }
          Button("Delete Cat", role: .destructive) { isConfirmingDelete = true }
            .confirmationDialog("Delete \(cat.name)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
              Button("Delete \(cat.name) and Their History", role: .destructive) { delete(cat) }
            } message: {
              Text("Their Meals, Feedings, Weigh-ins, Care Tasks and Care Records are deleted too. Archive instead to keep them.")
            }
        } footer: {
          if !cat.isArchived {
            Text("For a Cat rehomed or passed away. An Archived Cat leaves Today and gets no reminders; its history stays here.")
          }
        }
      }
    }
    .navigationTitle(isFirstRun ? "Your Cat" : cat == nil ? "Add Cat" : "Edit Cat")
    .toolbar {
      if isFirstRun {
        ToolbarItem(placement: .primaryAction) { Button("Continue", action: save).disabled(!canSave) }
      } else {
        if cat == nil {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
        ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!canSave) }
      }
    }
    .task(id: photoItem) {
      guard let data = try? await photoItem?.loadTransferable(type: Data.self) else { return }
      photo = downscaled(data)
    }
  }

  private func toggleArchived(_ cat: Cat) {
    let archived = withErrorReporting {
      try database.write { cat.isArchived ? try $0.unarchiveCat(cat.id) : try $0.archiveCat(cat.id) }
      return true
    }
    if archived == true { dismiss() }
  }

  private func delete(_ cat: Cat) {
    let deleted = withErrorReporting {
      try database.write { try $0.deleteCat(cat.id) }
      return true
    }
    if deleted == true { dismiss() }
  }

  private var canSave: Bool {
    !name.isEmpty && (cat != nil || (weight ?? 0) > 0)
  }

  private func save() {
    let birthdate = knowsBirthday ? birthdate : Cat.birthdate(aboutMonthsOld: ageYears * 12 + ageMonths)
    let saved = withErrorReporting {
      try database.write { db in
        if var cat {
          cat.name = name
          cat.photo = photo
          cat.birthdate = birthdate
          cat.isNeutered = isNeutered
          try db.updateCat(cat)
        } else if let weight {
          try db.addCat(
            name: name, photo: photo, birthdate: birthdate,
            isNeutered: isNeutered, weight: Measurement(value: weight, unit: weightUnit)
          )
        }
      }
      return true
    }
    // On first run RootView moves on by itself.
    if saved == true, !isFirstRun { dismiss() }
  }
}

/// Keeps stored photos small: 1024 pt on the long side, JPEG.
func downscaled(_ data: Data) -> Data? {
  guard let image = UIImage(data: data) else { return nil }
  let scale = min(1, 1024 / max(image.size.width, image.size.height))
  let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
  return image.preparingThumbnail(of: size)?.jpegData(compressionQuality: 0.8)
}

struct CatPhoto: View {
  let data: Data?

  var body: some View {
    Group {
      if let data, let image = UIImage(data: data) {
        Image(uiImage: image).resizable().scaledToFill()
      } else {
        Image(systemName: "cat.fill").resizable().scaledToFit().padding(24)
          .foregroundStyle(.secondary).background(.fill.tertiary)
      }
    }
    .clipShape(.circle)
    .accessibilityLabel("Cat photo")
  }
}
