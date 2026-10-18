import SwiftUI

/// A labelled decimal entry with its unit after the number, e.g. "Weight  4.2 kg".
struct NumberField: View {
  let title: String
  @Binding var value: Double?
  let unit: String

  init(_ title: String, value: Binding<Double?>, unit: String) {
    self.title = title
    _value = value
    self.unit = unit
  }

  var body: some View {
    LabeledContent(title) {
      HStack {
        TextField("0", value: $value, format: .number)
          .keyboardType(.decimalPad)
          .multilineTextAlignment(.trailing)
        Text(unit)
      }
    }
  }
}
