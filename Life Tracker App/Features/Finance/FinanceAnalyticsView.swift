import SwiftData
import SwiftUI

struct FinanceAnalyticsView: View {
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]
    @Query private var recurringTransactions: [RecurringTransaction]
    @Query private var categoryBudgets: [CategoryBudget]
    @Query private var settingsRecords: [FinanceSettings]
    @Query private var fixedBillOccurrences: [FixedBillOccurrence]

    private let currencyFormat = Decimal.FormatStyle.Currency(code: "BRL")
        .locale(AppLocalization.selectedLocale)

    private var monthlyBudget: Decimal? {
        guard let budget = settingsRecords.first?.monthlySpendingBudget,
              budget > 0 else {
            return nil
        }

        return budget
    }

    private var analytics: MonthlyFinanceAnalytics {
        MonthlyFinanceAnalytics(
            transactions: transactions,
            recurringTransactions: recurringTransactions,
            fixedBillOccurrences: fixedBillOccurrences,
            categoryBudgets: categoryBudgets,
            monthlyBudget: monthlyBudget
        )
    }

    private var summaryItems: [SummaryItem] {
        [
            SummaryItem(
                title: "Income",
                amount: analytics.projection.actualIncome,
                tint: .green
            ),
            SummaryItem(
                title: "Expenses",
                amount: analytics.projection.actualExpenses,
                tint: .red
            ),
            SummaryItem(
                title: "Investments",
                amount: analytics.projection.actual.investments,
                tint: .indigo
            ),
            SummaryItem(
                title: "Projected Expenses",
                amount: analytics.projection.projectedExpenses,
                tint: .orange
            ),
            SummaryItem(
                title: "Balance",
                amount: analytics.projection.actual.balance,
                tint: analytics.projection.actual.balance < 0 ? .red : .primary
            ),
            SummaryItem(
                title: "Projected Balance",
                amount: analytics.projection.projectedBalance,
                tint: analytics.projection.projectedBalance < 0 ? .red : .primary
            )
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 140))],
                        spacing: 12
                    ) {
                        ForEach(summaryItems) { item in
                            summaryCard(item)
                        }
                    }

                    analyticsSection("Spending by Category") {
                        if analytics.categorySpending.isEmpty {
                            emptyState(
                                title: "No Expenses",
                                description: "Expense spending from the current financial cycle will appear here."
                            )
                        } else {
                            SpendingByCategoryChart(
                                categories: analytics.categorySpending,
                                totalExpenses: analytics.projection.actualExpenses
                            )
                        }
                    }

                    analyticsSection("Daily Spending") {
                        if analytics.dailySpending.isEmpty {
                            emptyState(
                                title: "No Daily Spending",
                                description: "Add an expense to see daily spending."
                            )
                        } else {
                            DailySpendingChart(
                                spending: analytics.dailySpending
                            )
                        }
                    }

                    analyticsSection("Actual vs Projected") {
                        ActualProjectedChart(
                            actualExpenses: analytics.projection.actualExpenses,
                            projectedExpenses: analytics.projection.projectedExpenses,
                            monthlyBudget: monthlyBudget
                        )
                    }

                    if analytics.projectedCategorySpending.contains(where: { $0.pendingAmount > 0 }) {
                        analyticsSection("Projected Spending by Category") {
                            VStack(spacing: 12) {
                                ForEach(analytics.projectedCategorySpending) { category in
                                    projectedCategoryRow(category)
                                }
                            }
                        }
                    }

                    analyticsSection("Spending Type") {
                        VStack(spacing: 10) {
                            LabeledContent(
                                "Fixed / Recurring",
                                value: analytics.fixedOrRecurringExpenses.formatted(currencyFormat)
                            )
                            LabeledContent(
                                "Variable",
                                value: analytics.variableExpenses.formatted(currencyFormat)
                            )
                        }
                    }

                    if !analytics.topCategories.isEmpty {
                        analyticsSection("Top Spending Categories") {
                            VStack(spacing: 12) {
                                ForEach(
                                    Array(analytics.topCategories.enumerated()),
                                    id: \.element.id
                                ) { index, category in
                                    topCategoryRow(
                                        category,
                                        rank: index + 1
                                    )
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Finance Analytics")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
#if os(macOS)
        .frame(minWidth: 720, minHeight: 720)
#endif
    }

    private func summaryCard(_ item: SummaryItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(item.amount.formatted(currencyFormat))
                .font(.headline)
                .foregroundStyle(item.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 14))
    }

    private func analyticsSection<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.bold())

            content()
                .padding()
                .background(
                    .background.secondary,
                    in: .rect(cornerRadius: 16)
                )
        }
    }

    private func emptyState(
        title: LocalizedStringKey,
        description: LocalizedStringKey
    ) -> some View {
        ContentUnavailableView(
            title,
            systemImage: "chart.bar",
            description: Text(description)
        )
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    private func topCategoryRow(
        _ category: CategorySpendingData,
        rank: Int
    ) -> some View {
        HStack(spacing: 10) {
            Text("\(rank).")
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .trailing)

            CategoryIcon(
                iconName: category.iconName,
                colorName: category.colorName,
                size: .body,
                width: 22
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(category.name)
                    .fontWeight(.medium)

                Text(budgetStatus(for: category))
                    .font(.caption)
                    .foregroundStyle(
                        category.budgetLimit == nil
                            ? Color.secondary
                            : budgetStatusTint(for: category)
                    )
            }

            Spacer()

            Text(category.amount.formatted(currencyFormat))
                .fontWeight(.semibold)
        }
    }

    private func projectedCategoryRow(
        _ category: CategorySpendingData
    ) -> some View {
        HStack(spacing: 10) {
            CategoryIcon(
                iconName: category.iconName,
                colorName: category.colorName,
                size: .body,
                width: 22
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(category.name)
                    .fontWeight(.medium)
                Text("Actual \(category.amount.formatted(currencyFormat)) • Scheduled / estimated \(category.pendingAmount.formatted(currencyFormat))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(category.projectedAmount.formatted(currencyFormat))
                .fontWeight(.semibold)
        }
    }

    private func budgetStatus(
        for category: CategorySpendingData
    ) -> LocalizedStringResource {
        guard let budget = category.budgetLimit, budget > 0 else {
            return "No budget"
        }

        if category.projectedAmount > budget {
            return "Projected over budget"
        }

        let percentage = NSDecimalNumber(
            decimal: category.amount / budget
        ).doubleValue.formatted(
            .percent.precision(.fractionLength(0)).locale(AppLocalization.selectedLocale)
        )
        return "\(percentage) of budget"
    }

    private func budgetStatusTint(
        for category: CategorySpendingData
    ) -> Color {
        guard let budget = category.budgetLimit,
              budget > 0 else {
            return .secondary
        }

        return category.projectedAmount > budget ? .red : .secondary
    }
}

private struct SummaryItem: Identifiable {
    let title: LocalizedStringKey
    let amount: Decimal
    let tint: Color

    var id: String {
        String(describing: title)
    }
}

#Preview {
    FinanceAnalyticsView()
        .modelContainer(LifeTrackerPersistence.previewContainer())
}
