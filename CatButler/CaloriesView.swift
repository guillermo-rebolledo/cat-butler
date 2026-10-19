import CatButlerCore
import SQLiteData
import SwiftUI

/// Today's Intake against the Calorie Target, with treats as their own segment.
struct IntakeSummary: View {
  let intake: Intake
  let target: CalorieTarget?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      LabeledContent("Intake") {
        if let target {
          Text("\(kcalText(intake.kcal)) of \(target.text)")
        } else {
          Text("\(kcalText(intake.kcal)) kcal")
        }
      }
      if let target {
        IntakeBar(intake: intake, target: target)
      } else {
        Text("Set a Calorie Target to compare against.").font(.subheadline).foregroundStyle(.secondary)
      }
      if intake.treatKcal > 0 {
        HStack(spacing: 6) {
          Circle().fill(.orange).frame(width: 8, height: 8)
          Text("Treats \(kcalText(intake.treatKcal)) kcal")
        }
        .font(.subheadline).foregroundStyle(.secondary)
      }
      if intake.isApproximate {
        Text("Approximate: includes free-fed Food").font(.subheadline).foregroundStyle(.secondary)
      }
    }
  }
}

/// Feedings other than treats, then treats, across the Target. Fills up when Intake reaches the Target.
private struct IntakeBar: View {
  let intake: Intake
  let target: CalorieTarget

  var body: some View {
    let scale = max(target.kcal, intake.kcal)
    GeometryReader { geometry in
      if scale > 0 {
        HStack(spacing: 0) {
          Rectangle().fill(.tint).frame(width: geometry.size.width * (intake.kcal - intake.treatKcal) / scale)
          Rectangle().fill(.orange).frame(width: geometry.size.width * intake.treatKcal / scale)
        }
      }
    }
    .frame(height: 8)
    .background(.fill.tertiary)
    .clipShape(.capsule)
    // The text above says the same.
    .accessibilityHidden(true)
  }
}

/// The Calorie Target, the owner's own target, and how much of each Food meets it.
struct CalorieTargetView: View {
  let cat: Cat
  let target: CalorieTarget?
  @Dependency(\.defaultDatabase) var database
  @Environment(\.dismiss) private var dismiss
  @FetchAll(Food.active) var foods
  @State private var ownTarget: Double?

  init(cat: Cat, target: CalorieTarget?) {
    self.cat = cat
    self.target = target
    _ownTarget = State(initialValue: cat.calorieTargetOverride)
  }

  var body: some View {
    Form {
      Section {
        LabeledContent("Calorie Target") { Text(target?.text ?? String(localized: "Unknown")) }
      } footer: {
        if target?.isOverride == true {
          Text("Set by you. Individual cats vary: adjust it based on the weight trend and your vet.")
        } else {
          Text(
            "An estimate from \(cat.name)'s latest Weigh-in, Life Stage and neuter status. Individual cats vary by as much as 30–50%, so adjust it based on the weight trend and your vet."
          )
        }
      }
      Section {
        NumberField("Your target", value: $ownTarget, unit: "kcal")
      } footer: {
        Text("For example, your vet's number. Leave it empty to use the estimate.")
      }
      if let target {
        Section {
          ForEach(foods) { food in
            LabeledContent(food.name) {
              Text("\(food.dailyAmount(toMeet: target).formatted(.number.precision(.significantDigits(1...3)))) \(food.servingUnit.title)")
            }
          }
        } header: {
          Text("Converter")
        } footer: {
          Text("How much of each Food alone meets \(target.text).")
        }
      }
    }
    .navigationTitle("Calorie Target")
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Save", action: save)
          .disabled(ownTarget == cat.calorieTargetOverride || ownTarget.map { !CalorieTarget.isValid($0) } == true)
      }
    }
  }

  private func save() {
    let saved = withErrorReporting {
      try database.write { try $0.overrideCalorieTarget(ownTarget, for: cat.id) }
      return true
    }
    if saved == true { dismiss() }
  }
}

extension CalorieTarget {
  /// "about 238 kcal/day": always shown as an estimate.
  var text: String {
    String(localized: "about \(kcalText(kcal)) kcal/day")
  }
}

/// "238". Whole kcal for daily totals; per-unit kcal keep a decimal (`ServingUnit.kcalText`).
private func kcalText(_ kcal: Double) -> String {
  kcal.formatted(.number.precision(.fractionLength(0)))
}
