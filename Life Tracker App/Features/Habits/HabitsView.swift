import SwiftData
import SwiftUI

/// Today's habits: one tap marks a habit done, another tap undoes it.
struct HabitsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Habit.sortOrder) private var habits: [Habit]

    @State private var showsAddHabit = false
    @State private var errorMessage: String?

    var body: some View {
        let summary = HabitsTodaySummary(habits: habits)

        NavigationStack {
            List {
                if summary.scheduled.isEmpty && summary.others.isEmpty {
                    ContentUnavailableView {
                        Label("No Habits Yet", systemImage: "checkmark.circle")
                    } description: {
                        Text("Create a habit to track it every day and build a streak.")
                    } actions: {
                        Button("Add Habit") { showsAddHabit = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    Section {
                        HabitsProgressView(summary: summary)
                    }

                    if summary.scheduled.isEmpty {
                        Section {
                            Text("No habits are scheduled today. Enjoy the rest day.")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !summary.pending.isEmpty {
                        Section("To Do") {
                            ForEach(summary.pending) { item in
                                habitLink(item, today: summary.today)
                            }
                        }
                    }

                    if !summary.completed.isEmpty {
                        Section("Completed") {
                            ForEach(summary.completed) { item in
                                habitLink(item, today: summary.today)
                            }
                        }
                    }

                    if !summary.others.isEmpty {
                        Section("Not Scheduled Today") {
                            ForEach(summary.others) { item in
                                NavigationLink {
                                    HabitDetailView(habit: item.habit)
                                } label: {
                                    HabitRow(item: item, showsToggle: false) {}
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Habits")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    NavigationLink {
                        ArchivedHabitsView()
                    } label: {
                        Label("Archived Habits", systemImage: "archivebox")
                    }

                    Button("Add Habit", systemImage: "plus") {
                        showsAddHabit = true
                    }
                }
            }
            .sheet(isPresented: $showsAddHabit) {
                AddEditHabitView()
            }
            .sensoryFeedback(.success, trigger: summary.completedCount) { old, new in new > old }
            .sensoryFeedback(.selection, trigger: summary.completedCount) { old, new in new < old }
            .alert("Unable to Update Habit", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func habitLink(_ item: HabitsTodaySummary.Item, today: HabitDay) -> some View {
        NavigationLink {
            HabitDetailView(habit: item.habit)
        } label: {
            HabitRow(item: item) {
                toggle(item.habit, on: today)
            }
        }
    }

    private func toggle(_ habit: Habit, on day: HabitDay) {
        do {
            try HabitService.toggleCompletion(of: habit, on: day, in: modelContext)
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

/// Date and completed / scheduled progress for today.
struct HabitsProgressView: View {
    let summary: HabitsTodaySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(summary.today.date(), format: .dateTime.weekday(.wide).day().month(.wide).locale(AppLocalization.selectedLocale))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if summary.scheduledCount > 0 {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(summary.completedCount) of \(summary.scheduledCount) done")
                        .font(.title2.bold())
                    Spacer()
                    Text(summary.progress, format: .percent.precision(.fractionLength(0)).locale(AppLocalization.selectedLocale))
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: summary.progress)
                    .tint(summary.completedCount == summary.scheduledCount ? .green : .accentColor)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// A habit with its one-tap completion control.
struct HabitRow: View {
    let item: HabitsTodaySummary.Item
    var showsToggle = true
    let onToggle: () -> Void

    private var habit: Habit { item.habit }

    var body: some View {
        HStack(spacing: 12) {
            if showsToggle {
                Button(action: onToggle) {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title)
                        .foregroundStyle(item.isCompleted ? Color.category(named: habit.colorName) : .secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(item.isCompleted ? Text("Mark \(habit.name) as not done") : Text("Mark \(habit.name) as done"))
            }

            CategoryIcon(iconName: habit.iconName, colorName: habit.colorName)

            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name)
                    .font(.headline)
                    .strikethrough(item.isCompleted && showsToggle, color: .secondary)
                HStack(spacing: 6) {
                    Text(HabitFormatting.summary(habit.schedule))
                    if item.statistics.currentStreak > 0 {
                        Text("• \(Text("\(item.statistics.currentStreak) in a row"))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
