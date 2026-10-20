import CatButlerCore
import PhotosUI
import SQLiteData
import SwiftUI

/// First-run step 1: the Cat.
struct FirstRunView: View {
  @Dependency(\.defaultDatabase) var database
  @State private var name = ""
  @State private var photoItem: PhotosPickerItem?
  @State private var photo: Data?
  @State private var knowsBirthday = false
  @State private var birthdate = Date()
  @State private var ageYears = 0
  @State private var ageMonths = 3
  @State private var isNeutered = false
  @State private var weight: Double?
  private let weightUnit = UnitMass.catWeight()

  var body: some View {
    NavigationStack {
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
          NumberField("Weight", value: $weight, unit: weightUnit.symbol)
        }
      }
      .navigationTitle("Your Cat")
      .toolbar {
        Button("Continue", action: save).disabled(name.isEmpty || (weight ?? 0) <= 0)
      }
      .task(id: photoItem) {
        guard let data = try? await photoItem?.loadTransferable(type: Data.self) else { return }
        photo = downscaled(data)
      }
    }
  }

  private func save() {
    guard let weight else { return }
    let birthdate = knowsBirthday ? birthdate : Cat.birthdate(aboutMonthsOld: ageYears * 12 + ageMonths)
    withErrorReporting {
      try database.write { db in
        try db.addCat(
          name: name, photo: photo, birthdate: birthdate,
          isNeutered: isNeutered, weight: Measurement(value: weight, unit: weightUnit)
        )
      }
    }
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
