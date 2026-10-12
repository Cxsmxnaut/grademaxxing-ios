import GrademaxxingCore
import SwiftUI

struct SchoolCalendarView: View {
  @Bindable var model: AppModel
  @State private var month = SchoolMonth.current
  @State private var selected: SchoolDate?
  private var requestKey: String { "\(model.schoolSessionKey)|\(month.year)|\(month.month)" }
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Button {
          changeMonth(-1)
        } label: {
          Label("Previous month", systemImage: "chevron.left").labelStyle(.iconOnly).frame(
            minWidth: 44, minHeight: 44)
        }
        .disabled(month.offset(-1) == nil).accessibilityIdentifier("calendar.previousMonth")
        Spacer()
        Text(month.firstDay.localDate.formatted(.dateTime.month(.wide).year())).font(.headline)
          .multilineTextAlignment(.center).accessibilityIdentifier("calendar.month")
        Spacer()
        Button {
          changeMonth(1)
        } label: {
          Label("Next month", systemImage: "chevron.right").labelStyle(.iconOnly).frame(
            minWidth: 44, minHeight: 44)
        }
        .disabled(month.offset(1) == nil).accessibilityIdentifier("calendar.nextMonth")
      }.padding(.horizontal, 12)
      RecordScreen(
        model: model, store: model.calendar, emptyTitle: "Calendar could not load",
        reload: { await model.loadCalendar(month: month, force: true) }
      ) { book in
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            monthGrid(book)
            HStack {
              Text(
                selected.map { $0.localDate.formatted(date: .abbreviated, time: .omitted) }
                  ?? "This month's events"
              ).font(.headline)
              Spacer()
              if selected != nil { Button("All events") { selected = nil } }
            }
            let events = book.events.filter { selected == nil || $0.date == selected }
            if events.isEmpty {
              Text("No events are listed for this selection.").foregroundStyle(.secondary)
            }
            ForEach(events) { event in
              NavigationLink {
                CalendarEventView(event: event)
              } label: {
                VStack(alignment: .leading, spacing: 8) {
                  Text(event.title.isEmpty ? "School event" : event.title).font(.headline)
                    .foregroundStyle(.primary)
                  Text(
                    [
                      event.date.localDate.formatted(date: .abbreviated, time: .omitted),
                      event.time, event.type,
                    ].filter { !$0.isEmpty }.joined(separator: " · ")
                  )
                  .font(.caption).foregroundStyle(.secondary)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                  .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
              }.buttonStyle(.plain)
            }
            if let start = book.startDate, let end = book.endDate {
              Text(
                "StudentVUE calendar range: \(start.localDate.formatted(date: .abbreviated, time: .omitted)) – \(end.localDate.formatted(date: .abbreviated, time: .omitted))"
              )
              .font(.caption).foregroundStyle(.secondary)
            }
          }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
      }
    }.background(Theme.background).navigationTitle("Calendar").inlineTitle()
      .task(id: requestKey) { await model.loadCalendar(month: month) }
  }

  private func changeMonth(_ amount: Int) {
    if let next = month.offset(amount) {
      month = next
      selected = nil
    }
  }
  private func monthGrid(_ book: SchoolCalendar) -> some View {
    let calendar = Calendar(identifier: .gregorian)
    let offset =
      (calendar.component(.weekday, from: month.firstDay.localDate) - calendar.firstWeekday + 7) % 7
    let cells: [SchoolDate?] = Array(repeating: nil, count: offset) + month.days.map(Optional.some)
    let symbols = calendar.veryShortStandaloneWeekdaySymbols
    return LazyVGrid(
      columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8
    ) {
      ForEach(0..<7, id: \.self) { index in
        Text(symbols[(calendar.firstWeekday - 1 + index) % 7]).font(.caption).foregroundStyle(
          .secondary
        ).accessibilityHidden(true)
      }
      ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
        if let date {
          let count = book.events.filter { $0.date == date }.count
          Button {
            selected = selected == date ? nil : date
          } label: {
            VStack(spacing: 4) {
              Text(String(date.day)).font(.body.monospacedDigit())
              Circle().fill(count > 0 ? Theme.success : .clear).frame(width: 5, height: 5)
            }.frame(maxWidth: .infinity, minHeight: 44)
              .background(
                selected == date ? Theme.accent.opacity(0.25) : .clear,
                in: RoundedRectangle(cornerRadius: 8))
          }.buttonStyle(.plain)
            .accessibilityLabel(
              "\(date.localDate.formatted(date: .complete, time: .omitted)), \(count) events"
            )
            .accessibilityAddTraits(selected == date ? [.isSelected] : [])
        } else {
          Color.clear.frame(height: 44).accessibilityHidden(true)
        }
      }
    }
  }
}

private struct CalendarEventView: View {
  let event: CalendarEvent
  var body: some View {
    Form {
      Section {
        Text(event.title.isEmpty ? "School event" : event.title).font(.title2.bold())
        LabeledContent(
          "Date", value: event.date.localDate.formatted(date: .complete, time: .omitted))
        if !event.time.isEmpty { LabeledContent("Time", value: event.time) }
        if !event.type.isEmpty { LabeledContent("Type", value: event.type) }
      }
      if !event.description.isEmpty { Section("Description") { Text(event.description) } }
      if !event.details.isEmpty { Section("Details") { Text(event.details) } }
    }.navigationTitle("Calendar event").inlineTitle()
  }
}
