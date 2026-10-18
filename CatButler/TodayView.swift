import CatButlerCore
import SQLiteData
import SwiftUI

struct TodayView: View {
  // ponytail: shows the first Cat only; Cat switching comes with multi-Cat support.
  @FetchOne(Cat.order(by: \.name)) var cat: Cat?

  var body: some View {
    NavigationStack {
      List {
        if let cat { CatSummary(cat: cat) }
      }
      .navigationTitle("Today")
    }
  }
}

struct CatSummary: View {
  let cat: Cat
  @FetchOne var latestWeighIn: WeighIn?
  @Dependency(\.date.now) var now

  init(cat: Cat) {
    self.cat = cat
    _latestWeighIn = FetchOne(wrappedValue: nil, WeighIn.latest(for: cat.id))
  }

  var body: some View {
    HStack(spacing: 16) {
      CatPhoto(data: cat.photo).frame(width: 64, height: 64)
      VStack(alignment: .leading) {
        Text(cat.name).font(.title2.bold())
        Text(cat.lifeStage(on: now).title).foregroundStyle(.secondary)
        if let latestWeighIn {
          Text(
            latestWeighIn.weight.converted(to: .catWeight())
              .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1))))
          )
          .foregroundStyle(.secondary)
        }
      }
    }
  }
}

extension LifeStage {
  var title: LocalizedStringKey {
    switch self {
    case .kitten: "Kitten"
    case .adult: "Adult"
    case .senior: "Senior"
    }
  }
}
