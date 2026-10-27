import SwiftData
import SwiftUI

/// Compact Today's Habits on Home. Same summary and service as the Habits tab,
/// so both always agree.
struct HomeHabitsSummaryView: View {
    @Environment(\.modelContext) private var modelContext
    let summary: HabitsTodaySummary
    let onSeeHabits: () -> Void

    private let maxItems = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if summary.scheduled.isEmpty && summary.others.isEmpty {
                Text("Create your first habit in the Habits tab.")
                    .foregroundStyle(.secondary)
            } else if summary.scheduled.isEmpty {
                Text("No habits are scheduled today.")
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(summary.completedCount) of \(summary.scheduledCount) done")
                        .font(.headline)
                    Spacer()
                    Text(summary.progress, format: .percent.precision(.fractionLength(0)).locale(AppLocalization.selectedLocale))
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: summary.progress)
                    .tint(summary.completedCount == summary.scheduledCount ? .green : .accentColor)
                    .accessibilityHidden(true)

                // Pending first, so the quick controls show what is left.
                ForEach(Array((summary.pending + summary.completed).prefix(maxItems))) { item in
                    HabitRow(item: item) { toggle(item.habit) }
                }

                if summary.scheduledCount > maxItems {
                    Text("+ \(summary.scheduledCount - maxItems) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button("See Habits", action: onSeeHabits)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 16))
        .sensoryFeedback(.success, trigger: summary.completedCount) { old, new in new > old }
    }

    private func toggle(_ habit: Habit) {
        do {
            try HabitService.toggleCompletion(of: habit, on: summary.today, in: modelContext)
        } catch {
            modelContext.rollback()
        }
    }
}
