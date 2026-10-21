import CatButlerCore
import PhotosUI
import SQLiteData
import SwiftUI

/// The Cats tab: every Cat, to add another or edit one and its Meals.
struct CatsView: View {
  @FetchAll(Cat.order(by: \.name)) var cats
  @State private var isAdding = false

  var body: some View {
    NavigationStack {
      List(cats) { cat in
        NavigationLink { CatEditor(cat: cat) } label: { CatSummary(cat: cat) }
      }
      .navigationTitle("Cats")
      .toolbar { Button("Add Cat", systemImage: "plus") { isAdding = true } }
      .sheet(isPresented: $isAdding) { NavigationStack { CatEditor() } }
    }
  }
}

/// Adds a Cat, as first-run step 1 or from the Cats tab, or edits one. Its weight is asked once, as the first
/// Weigh-in; after that it's on the weight chart.
struct CatEditor: View {
  let cat: Cat?
  var isFirstRun = false
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
        Section { NavigationLink("Meals") { MealScheduleEditor(cat: cat) } }
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
