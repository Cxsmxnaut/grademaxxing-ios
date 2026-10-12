import GrademaxxingCore
import SwiftUI

struct AssignmentPlannerView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var simulation: GradeSimulation
  @State private var target = "90"
  @State private var possible = "20"
  @State private var category: String
  init(course: Course) {
    _simulation = State(initialValue: GradeSimulation(course: course))
    _category = State(
      initialValue: course.categories.first(where: { ($0.weight ?? 0) > 0 })?.name ?? course
        .assignments.first?.category ?? "Assignment")
  }
  private var categories: [String] {
    simulation.categories?.filter { ($0.weight ?? 0) > 0 }.map(\.name)
      ?? Array(Set(simulation.rows.map(\.category))).sorted()
  }
  var body: some View {
    NavigationStack {
      Form {
        Section("Local assignment estimate") {
          if let estimate = simulation.estimate {
            LabeledContent("Projected percentage") {
              Text("\(estimate.projected.formatted(.number.precision(.fractionLength(2))))%")
                .foregroundStyle(Theme.simulation).font(.title2.bold())
                .accessibilityIdentifier("simulation.projected")
            }
            LabeledContent(
              "Change",
              value:
                "\(estimate.change.formatted(.number.precision(.fractionLength(2)))) percentage points"
            )
            if estimate.partial {
              Text(
                estimate.omittedAssignments > 0
                  ? "Partial estimate: \(estimate.omittedAssignments) recorded assignments lack a supported contribution."
                  : "Partial estimate: the calculated baseline differs from the official mark."
              )
              .font(.footnote).foregroundStyle(Theme.warning)
            }
          } else {
            Text(
              "An estimate is unavailable. Check the entered points; some courses do not provide enough grading information."
            )
            .foregroundStyle(.secondary)
          }
          if let official = simulation.course.officialPercent {
            LabeledContent("Official percentage", value: "\(official.formatted())%")
          }
          Text(
            "All edits stay in this planner and are discarded when you close it. School records remain unchanged."
          )
          .font(.footnote).foregroundStyle(.secondary)
        }
        Section("Assignments") {
          ForEach($simulation.rows) { $row in
            NavigationLink {
              SimulationRowView(
                row: $row,
                issue: simulation.original.first(where: { $0.id == row.id }).flatMap {
                  simulation.issue($0)
                })
            } label: {
              VStack(alignment: .leading, spacing: 5) {
                Text(row.title).font(.headline)
                Text(
                  row.excluded
                    ? "Excluded from this estimate"
                    : "\(row.category) · \(row.earned?.formatted() ?? "—") / \(row.extraCredit ? "bonus" : row.possible?.formatted() ?? "—")"
                )
                .font(.caption).foregroundStyle(.secondary)
              }
            }.accessibilityIdentifier("simulation.assignment.\(row.id)")
              .deleteDisabled(!row.hypothetical)
          }
          .onDelete { offsets in
            for index in offsets.reversed() where simulation.rows[index].hypothetical {
              simulation.rows.remove(at: index)
            }
          }
          Button("Add hypothetical assignment", systemImage: "plus") {
            simulation.add(category: category, earned: 0, possible: 10)
          }.disabled(categories.isEmpty).accessibilityIdentifier("simulation.add")
        }
        Section("Target a new assignment") {
          Text("Calculate points needed on a new assignment after your edits.").font(.footnote)
            .foregroundStyle(.secondary)
          Picker("Category", selection: $category) {
            ForEach(categories, id: \.self) { Text($0).tag($0) }
          }
          TextField("Target percentage", text: $target).decimalInput().accessibilityLabel(
            "Target percentage")
          TextField("New assignment maximum", text: $possible).decimalInput().accessibilityLabel(
            "New assignment maximum")
          if let target = Double(target), let maximum = Double(possible),
            let needed = simulation.pointsNeeded(
              target: target, possible: maximum, category: category)
          {
            LabeledContent(
              "Points needed",
              value:
                "\(max(0, needed).formatted(.number.precision(.fractionLength(2)))) / \(maximum.formatted())"
            )
            if needed > maximum {
              Text("This requires extra credit or additional assignments.").font(.footnote)
                .foregroundStyle(Theme.warning)
            } else if needed <= 0 {
              Text("The target is already met with zero points on this new assignment.").font(
                .footnote
              ).foregroundStyle(.secondary)
            }
          } else {
            Text("Target estimate unavailable.").foregroundStyle(.secondary)
          }
        }
        Section {
          Button("Reset assignment edits", role: .destructive) { simulation.reset() }
            .accessibilityIdentifier("simulation.reset")
          Text(
            "Estimates follow the available weighted points and category totals. Teacher overrides, rounding, and grading changes may produce a different result."
          )
          .font(.footnote).foregroundStyle(.secondary)
        }
      }.navigationTitle("Assignment planner").inlineTitle()
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .privacySensitive().privacyShield()
    }
  }
}

private struct SimulationRowView: View {
  @Binding var row: SimulationRow
  let issue: String?
  @State private var earned = ""
  @State private var possible = ""
  var body: some View {
    Form {
      Section {
        Text(row.title).font(.headline)
        Text(row.category).foregroundStyle(.secondary)
        if let issue { Text(issue).font(.footnote).foregroundStyle(Theme.warning) }
      }
      Section("Local points") {
        TextField("Points earned", text: $earned).decimalInput().accessibilityLabel("Points earned")
          .accessibilityIdentifier("simulation.earned")
          .onChange(of: earned) { _, value in row.earned = Double(value) }
        TextField("Points possible", text: $possible).decimalInput().accessibilityLabel(
          "Points possible"
        )
        .accessibilityIdentifier("simulation.possible")
        .disabled(row.extraCredit).onChange(of: possible) { _, value in row.possible = Double(value)
        }
        Toggle("Extra credit", isOn: $row.extraCredit)
        Text("Blank or invalid points leave the estimate unavailable.").font(.footnote)
          .foregroundStyle(.secondary)
      }.disabled(issue != nil)
      Section { Toggle("Exclude from estimate", isOn: $row.excluded) }
    }.navigationTitle("Edit estimate").inlineTitle()
      .onAppear {
        earned = row.earned.map { String($0) } ?? ""
        possible = row.possible.map { String($0) } ?? ""
      }
  }
}
