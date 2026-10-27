import SwiftData
import SwiftUI

struct HabitDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let habit: Habit

    @State private var month = HabitDay(year: 0, month: 0, day: 1)
    @State private var showsEdit = false
    @State private var showsArchiveConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        let today = HabitDay(.now)
        let snapshot = HabitSnapshot(habit)
        let statistics = HabitStatistics(snapshot, today: today)

        List {
            Section {
                HStack(spacing: 14) {
                    CategoryIcon(iconName: habit.iconName, colorName: habit.colorName, size: .largeTitle, width: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(habit.name)
                            .font(.title2.bold())
                        Text(HabitFormatting.summary(habit.schedule))
                            .foregroundStyle(.secondary)
                        if habit.isArchived {
                            Label("Archived", systemImage: "archivebox")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if !habit.notes.isEmpty {
                    Text(habit.notes)
                        .foregroundStyle(.secondary)
                }
                todayStatus(statistics, today: today)
            }

            Section("Statistics") {
                LabeledContent("Current Streak") { Text("\(statistics.currentStreak) days") }
                LabeledContent("Best Streak") { Text("\(statistics.bestStreak) days") }
                LabeledContent("Completion Rate") {
                    if let rate = statistics.completionRate {
                        Text("\(rate.formatted(.percent.precision(.fractionLength(0)).locale(AppLocalization.selectedLocale))) (\(statistics.last30Completed) of \(statistics.last30Scheduled))")
                    } else {
                        Text("—")
                    }
                }
                LabeledContent("This Week") { Text("\(statistics.weekCompleted) of \(statistics.weekScheduled)") }
                LabeledContent("Total Completed") { Text("\(statistics.totalCompletions) days") }
            }

            Section {
                HabitCalendarView(
                    month: $month,
                    habit: snapshot,
                    today: today,
                    colorName: habit.colorName,
                    canEdit: !habit.isArchived
                ) { day in
                    toggle(day)
                }
            } header: {
                Text("History")
            } footer: {
                Text("Completion rate counts only scheduled days in the last 30 days. Days without the habit scheduled never count as missed.")
            }

            Section {
                Button("Edit Habit", systemImage: "pencil") { showsEdit = true }
                if habit.isArchived {
                    Button("Reactivate Habit", systemImage: "arrow.uturn.backward") { reactivate() }
                } else {
                    Button("Archive Habit", systemImage: "archivebox", role: .destructive) {
                        showsArchiveConfirmation = true
                    }
                }
            }
        }
        .navigationTitle(habit.name)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .onAppear {
            if month.year == 0 {
                month = HabitDay(year: today.year, month: today.month, day: 1)
            }
        }
        .sheet(isPresented: $showsEdit) {
            AddEditHabitView(habit: habit)
        }
        .confirmationDialog("Archive this habit?", isPresented: $showsArchiveConfirmation, titleVisibility: .visible) {
            Button("Archive Habit", role: .destructive) { archive() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It leaves your daily list. Its history is kept and you can reactivate it later.")
        }
        .sensoryFeedback(.selection, trigger: habit.completions.count)
        .alert("Unable to Update Habit", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func todayStatus(_ statistics: HabitStatistics, today: HabitDay) -> some View {
        if habit.isArchived {
            EmptyView()
        } else if statistics.isScheduledToday {
            Button {
                toggle(today)
            } label: {
                Label(
                    statistics.isCompletedToday ? "Done today" : "Mark as done today",
                    systemImage: statistics.isCompletedToday ? "checkmark.circle.fill" : "circle"
                )
            }
        } else {
            Label("Not scheduled today", systemImage: "moon.zzz")
                .foregroundStyle(.secondary)
        }
    }

    private func toggle(_ day: HabitDay) {
        do {
            try HabitService.toggleCompletion(of: habit, on: day, in: modelContext)
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private func archive() {
        do {
            try HabitService.archive(habit, in: modelContext)
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private func reactivate() {
        do {
            try HabitService.reactivate(habit, in: modelContext)
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

/// Month grid of completed, missed, unscheduled and future days.
/// Each state has its own shape, not just a color.
struct HabitCalendarView: View {
    @Binding var month: HabitDay
    let habit: HabitSnapshot
    let today: HabitDay
    let colorName: String
    let canEdit: Bool
    let onToggle: (HabitDay) -> Void

    private var calendar: Calendar { HabitFormatting.calendar }

    var body: some View {
        let days = HabitCalendar.days(inMonthOf: month, habit: habit, today: today)
        let blanks = HabitCalendar.leadingBlanks(forMonthOf: month, calendar: calendar)
        let isCurrentMonth = month.year == today.year && month.month == today.month

        VStack(spacing: 12) {
            HStack {
                Button("Previous Month", systemImage: "chevron.left") { shift(-1) }
                    .labelStyle(.iconOnly)
                Spacer()
                Text(HabitFormatting.monthTitle(month))
                    .font(.headline)
                Spacer()
                Button("Next Month", systemImage: "chevron.right") { shift(1) }
                    .labelStyle(.iconOnly)
                    .disabled(isCurrentMonth)
            }
            .buttonStyle(.borderless)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8) {
                ForEach(HabitFormatting.orderedWeekdays(), id: \.self) { weekday in
                    Text(HabitFormatting.veryShortName(weekday))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                ForEach(0..<blanks, id: \.self) { _ in
                    Color.clear.frame(height: 36)
                }
                ForEach(days) { cell in
                    dayCell(cell)
                }
            }

            legend
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func dayCell(_ cell: HabitCalendarDay) -> some View {
        let color = Color.category(named: colorName)
        let content = ZStack {
            switch cell.status {
            case .completed:
                Circle().fill(color)
            case .missed:
                Circle().strokeBorder(Color.red.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
            case .pending:
                Circle().strokeBorder(color, lineWidth: 1.5)
            case .notScheduled, .beforeStart, .future:
                EmptyView()
            }
            Text("\(cell.day.day)")
                .font(.callout.weight(cell.day == today ? .bold : .regular))
                .foregroundStyle(foreground(for: cell.status))
        }
        .frame(height: 36)

        if canEdit && cell.canToggle {
            Button { onToggle(cell.day) } label: { content }
                .buttonStyle(.borderless)
                .accessibilityLabel(accessibilityText(cell))
                .accessibilityHint(cell.status == .completed ? Text("Double-tap to unmark") : Text("Double-tap to mark as done"))
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityText(cell))
        }
    }

    private func foreground(for status: HabitCalendarDay.Status) -> Color {
        switch status {
        case .completed: .white
        case .missed, .pending: .primary
        case .notScheduled: .secondary
        case .beforeStart, .future: Color.secondary.opacity(0.5)
        }
    }

    private func accessibilityText(_ cell: HabitCalendarDay) -> Text {
        let day = HabitFormatting.dayText(cell.day)
        return switch cell.status {
        case .completed: Text("\(day), completed")
        case .missed: Text("\(day), missed")
        case .pending: Text("\(day), not done yet")
        case .notScheduled: Text("\(day), not scheduled")
        case .beforeStart: Text("\(day), before the habit started")
        case .future: Text("\(day), upcoming")
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(Circle().fill(Color.category(named: colorName)), "Completed")
            legendItem(Circle().strokeBorder(Color.red.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])), "Missed")
            legendItem(Circle().strokeBorder(Color.category(named: colorName), lineWidth: 1.5), "Today")
            legendItem(Circle().fill(Color.clear), "Not scheduled")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    private func legendItem(_ shape: some View, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            shape.frame(width: 10, height: 10)
            Text(title)
        }
    }

    private func shift(_ months: Int) {
        guard let date = calendar.date(byAdding: .month, value: months, to: month.date(in: calendar)) else { return }
        let shifted = HabitDay(date, calendar: calendar)
        month = HabitDay(year: shifted.year, month: shifted.month, day: 1)
    }
}

struct ArchivedHabitsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Habit> { $0.isArchived }, sort: \Habit.sortOrder) private var habits: [Habit]

    var body: some View {
        List {
            if habits.isEmpty {
                ContentUnavailableView(
                    "No Archived Habits",
                    systemImage: "archivebox",
                    description: Text("Archived habits keep their history and can be reactivated.")
                )
            }
            ForEach(habits) { habit in
                NavigationLink {
                    HabitDetailView(habit: habit)
                } label: {
                    HStack(spacing: 12) {
                        CategoryIcon(iconName: habit.iconName, colorName: habit.colorName)
                        VStack(alignment: .leading) {
                            Text(habit.name)
                            Text(HabitFormatting.summary(habit.schedule))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .swipeActions {
                    Button("Reactivate Habit", systemImage: "arrow.uturn.backward") {
                        try? HabitService.reactivate(habit, in: modelContext)
                    }
                    .tint(.green)
                }
            }
        }
        .navigationTitle("Archived Habits")
    }
}
