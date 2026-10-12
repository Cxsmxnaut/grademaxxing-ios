import GrademaxxingCore
import SwiftUI

struct PlannerView: View {
  @Bindable var model: AppModel
  private let letters = [
    "A+", "A", "A-", "B+", "B", "B-", "C+", "C", "C-", "D+", "D", "D-", "F", "P", "CR", "NC", "NP",
  ]
  var body: some View {
    Form {
      Section("Current-course estimate") {
        let summary = GPAPlanning.summary(model.planner)
        LabeledContent("Unweighted GPA") {
          Text(GPAPlanning.displayValue(summary.unweighted)).accessibilityIdentifier(
            "planner.unweighted")
        }
        LabeledContent("Weighted GPA") {
          Text(GPAPlanning.displayValue(summary.weighted)).accessibilityIdentifier(
            "planner.weighted")
        }
        .foregroundStyle(Theme.success)
        LabeledContent("Academic weighted GPA") {
          Text(GPAPlanning.displayValue(summary.academicWeighted)).accessibilityIdentifier(
            "planner.academicWeighted")
        }
        LabeledContent("Included credits", value: summary.attemptedCredits.formatted())
        Text("\(GPAPlanning.policyLabel) · Local estimate, not a transcript GPA.")
          .font(.footnote).foregroundStyle(.secondary)
      }
      Section {
        Text(
          "Adjust course grades, credits, and rigor to explore a plan. Plus/minus grades use flat bands. AP/IB adds 1 point; Honors adds 0.5. D and failing grades receive no rigor bonus. Confirm your district's rules with a counselor."
        )
        .font(.footnote).foregroundStyle(.secondary)
        Text(
          "Grades before grade 9 and nonnumeric pass grades are excluded. Academic GPA excludes PE, driver's education, and ROTC by default. Grade level starts at 9 until you adjust it or reset from a loaded profile."
        ).font(.footnote).foregroundStyle(.secondary)
        Text(
          "Edits stay in memory. Explicit refreshes and reporting-period changes reset this planner. Automatic refreshes preserve your edits."
        )
        .font(.footnote).foregroundStyle(.secondary)
      }
      if model.planner.isEmpty {
        Section { Text("Load your grades to begin planning.").foregroundStyle(.secondary) }
      }
      ForEach($model.planner) { $entry in
        Section(entry.title) {
          Toggle("Include in estimate", isOn: $entry.included)
            .accessibilityIdentifier("planner.include.\(entry.id)")
          Toggle("Academic course", isOn: $entry.academic)
          Stepper("Grade level: \(entry.gradeLevel)", value: $entry.gradeLevel, in: 1...12)
          Picker("Letter grade", selection: $entry.letter) {
            if !letters.contains(entry.letter) {
              Text(entry.letter.isEmpty ? "Unpublished" : entry.letter).tag(entry.letter)
            }
            ForEach(letters, id: \.self) { Text($0).tag($0) }
          }.accessibilityIdentifier("planner.letter.\(entry.id)")
          Stepper(
            "Credits: \(entry.credits.formatted())", value: $entry.credits, in: 0.5...20, step: 0.5)
          Picker("Rigor", selection: $entry.bonus) {
            Text("Standard").tag(0.0)
            Text("Honors (+0.5)").tag(0.5)
            Text("AP / IB (+1)").tag(1.0)
          }
          if GPAPlanning.points(for: entry.letter) == nil {
            Text("This grade is excluded from the estimate because it has no numeric GPA value.")
              .font(.caption).foregroundStyle(.secondary)
          }
          if entry.gradeLevel < 9 {
            Text("Excluded by the provisional grade-level rule.").font(.caption).foregroundStyle(
              .secondary)
          }
        }
      }
      Section {
        Button("Reset from official grades") { model.resetPlanner() }.accessibilityIdentifier(
          "planner.reset")
      }
    }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("GPA planner")
  }
}
