import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case home
    case finance
    case habits
    case assistant
}

struct AppTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Binding var selection: AppTab

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house", value: .home) {
                HomeView(
                    onSeeFinance: { selection = .finance },
                    onSeeHabits: { selection = .habits }
                )
            }

            Tab("Finance", systemImage: "chart.pie", value: .finance) {
                FinanceView()
            }

            Tab("Habits", systemImage: "checkmark.circle", value: .habits) {
                HabitsView()
            }

            Tab("Assistant", systemImage: "bubble.left.and.bubble.right", value: .assistant) {
                AssistantView()
            }
        }
        .task {
            generateDueFinancialItems()
        }
        .onChange(of: scenePhase) {
            guard scenePhase == .active else {
                return
            }

            generateDueFinancialItems()
        }
    }

    private func generateDueFinancialItems() {
        try? RecurringTransactionGenerator.generateDueTransactions(
            in: modelContext
        )
        try? FixedBillOccurrenceGenerator.generateRelevantOccurrences(
            in: modelContext
        )
    }
}

#Preview {
    AppTabView(selection: .constant(.home))
        .modelContainer(LifeTrackerPersistence.previewContainer())
}
