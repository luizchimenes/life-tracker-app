import Charts
import SwiftData
import SwiftUI

struct FinancialCycleReportView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var transactions: [Transaction]
    @Query private var categoryBudgets: [CategoryBudget]
    @Query private var settingsRecords: [FinanceSettings]
    @Query private var fixedBillOccurrences: [FixedBillOccurrence]
    @Query private var creditCardInvoices: [CreditCardInvoice]
    @Query private var recurringTransactions: [RecurringTransaction]

    @State private var cycleOffset = 0
#if canImport(UIKit)
    @State private var export = FinancialReportExportViewModel()
#endif

    private let currencyFormat = Decimal.FormatStyle.Currency(code: "BRL")
        .locale(AppLocalization.selectedLocale)

    private var currentCycle: FinancialCycle? {
        FinancialCycle(containing: .now)
    }

    private var selectedCycle: FinancialCycle? {
        currentCycle?.shifted(byMonths: cycleOffset)
    }

    private var monthlyBudget: Decimal? {
        settingsRecords.first?.monthlySpendingBudget
    }

    private var report: FinancialCycleReport? {
        guard let selectedCycle else { return nil }
        return FinancialCycleReport(
            cycle: selectedCycle,
            transactions: transactions,
            categoryBudgets: categoryBudgets,
            monthlyBudget: monthlyBudget,
            fixedBillOccurrences: fixedBillOccurrences
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let report {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        cycleNavigation(report)
                        summarySection(report)
                        categorySection(report)
                        fixedCommitmentsSection(report)
                        fixedBillHistorySection(report)
                        spendingTypeSection(report)
                        automaticRecurringSection(report)
                        paymentMethodSection(report)
                        creditCardSection(report)
                        topExpensesSection(report)
                        budgetPerformanceSection(report)
                        comparisonSection(report)
                        insightsSection(report)
                    }
                    .padding()
                } else {
                    ContentUnavailableView(
                        "Report Unavailable",
                        systemImage: "doc.text.magnifyingglass"
                    )
                }
            }
            .navigationTitle("Financial Report")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
#if canImport(UIKit)
                ToolbarItem(placement: .primaryAction) {
                    if export.isExporting {
                        ProgressView()
                            .accessibilityLabel("Generating PDF")
                    } else {
                        Button("Export PDF", systemImage: "square.and.arrow.up") {
                            exportSelectedCycle()
                        }
                        .disabled(selectedCycle == nil)
                    }
                }
#endif
            }
#if canImport(UIKit)
            .sheet(item: $export.exportedFile, onDismiss: export.finishSharing) { file in
                ShareSheet(url: file.url, onComplete: export.finishSharing)
                    .ignoresSafeArea()
            }
            .alert(
                "Unable to Export PDF",
                isPresented: Binding(get: { export.errorMessage != nil }, set: { if !$0 { export.errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(export.errorMessage ?? "")
            }
#endif
        }
#if os(macOS)
        .frame(minWidth: 760, minHeight: 760)
#endif
    }

#if canImport(UIKit)
    /// Exports the cycle currently shown, including past cycles.
    private func exportSelectedCycle() {
        guard let cycle = selectedCycle else { return }
        Task {
            await export.export {
                FinancialReportPDFContent.make(
                    cycle: cycle,
                    transactions: transactions,
                    categoryBudgets: categoryBudgets,
                    monthlyBudget: monthlyBudget,
                    fixedBillOccurrences: fixedBillOccurrences,
                    creditCardInvoices: creditCardInvoices,
                    recurringTransactions: recurringTransactions
                )
            }
        }
    }
#endif

    private func cycleNavigation(_ report: FinancialCycleReport) -> some View {
        HStack {
            Button("Previous Cycle", systemImage: "chevron.left") {
                cycleOffset -= 1
            }
            .labelStyle(.iconOnly)

            Spacer()

            VStack(spacing: 3) {
                Text("Financial Cycle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(cycleLabel(report.cycle))
                    .font(.headline)
            }

            Spacer()

            Button("Next Cycle", systemImage: "chevron.right") {
                cycleOffset = min(cycleOffset + 1, 0)
            }
            .labelStyle(.iconOnly)
            .disabled(cycleOffset == 0)
        }
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 16))
    }

    private func summarySection(_ report: FinancialCycleReport) -> some View {
        reportSection("Summary") {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 145))],
                spacing: 12
            ) {
                reportMetric("Income", amount: report.snapshot.income, tint: .green)
                reportMetric("Expenses", amount: report.snapshot.expenses, tint: .red)
                reportMetric("Investments", amount: report.snapshot.investments, tint: .indigo)
                reportMetric(
                    "Balance",
                    amount: report.snapshot.balance,
                    tint: report.snapshot.balance < 0 ? .red : .primary
                )
            }

            if let percentage = report.investmentPercentageOfIncome {
                LabeledContent("Investment Percentage of Income") {
                    Text(
                        percentage,
                        format: .percent.precision(.fractionLength(1))
                    )
                }
            }

            if let budget = report.monthlyBudget {
                Divider()
                budgetSummary(spent: report.snapshot.expenses, budget: budget)
            }

            Divider()
            Text("Expenses compared with previous cycle")
                .font(.subheadline.bold())
            ChangeSummaryView(change: report.expenseChange)
        }
    }

    private func categorySection(_ report: FinancialCycleReport) -> some View {
        reportSection("Spending by Category") {
            if report.categoryReports.isEmpty {
                emptyText("No expense spending in this cycle.")
            } else {
                CategoryReportChart(categories: report.categoryReports)

                ForEach(report.categoryReports) { category in
                    DisclosureGroup {
                        categoryDetails(category)
                            .padding(.top, 8)
                    } label: {
                        HStack(spacing: 10) {
                            CategoryIcon(
                                iconName: category.iconName,
                                colorName: category.colorName,
                                size: .body,
                                width: 24
                            )
                            Text(category.name)
                            Spacer()
                            Text(category.amount.formatted(currencyFormat))
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
        }
    }

    private func categoryDetails(_ category: CategoryCycleReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(category.totalPercentage.formatted(.percent.precision(.fractionLength(1)).locale(AppLocalization.selectedLocale))) of total spending")
                .foregroundStyle(.secondary)

            if let budget = category.budgetLimit,
               let usage = category.budgetPercentage,
               let remaining = category.budgetRemaining {
                LabeledContent("Budget", value: budget.formatted(currencyFormat))
                LabeledContent("Used", value: usage.formatted(.percent.precision(.fractionLength(0)).locale(AppLocalization.selectedLocale)))
                LabeledContent(
                    remaining >= 0 ? "Remaining" : "Over budget",
                    value: abs(remaining).formatted(currencyFormat)
                )
            }

            LabeledContent(
                "Previous cycle",
                value: category.previousAmount.formatted(currencyFormat)
            )
            ChangeSummaryView(change: category.change)
        }
        .font(.subheadline)
    }

    private func fixedCommitmentsSection(_ report: FinancialCycleReport) -> some View {
        let commitments = report.fixedCommitments
        return reportSection("Fixed Commitments") {
            if commitments.totalCount == 0 {
                emptyText("No fixed commitments recorded for this cycle.")
            } else {
                LabeledContent("Paid") {
                    Text("\(commitments.paidCount) of \(commitments.totalCount)")
                }
                LabeledContent("Pending", value: "\(commitments.pendingCount)")
                if commitments.skippedCount > 0 {
                    LabeledContent("Skipped", value: "\(commitments.skippedCount)")
                }
                LabeledContent(
                    "Amount paid",
                    value: commitments.amountPaid.formatted(currencyFormat)
                )
                LabeledContent(
                    "Estimated remaining",
                    value: "~ \(commitments.estimatedRemaining.formatted(currencyFormat))"
                )
                if commitments.unknownRemainingCount > 0 {
                    Label(
                        "\(commitments.unknownRemainingCount) pending bill(s) cannot be estimated.",
                        systemImage: "exclamationmark.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Text("Commitments are grouped by their due-date cycle. Their expense transactions are counted in the cycle containing the actual payment date.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func fixedBillHistorySection(_ report: FinancialCycleReport) -> some View {
        reportSection("Fixed Bill History") {
            if report.fixedBillHistory.isEmpty {
                emptyText("No paid fixed bills in this cycle.")
            } else {
                ForEach(report.fixedBillHistory) { bill in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 10) {
                            CategoryIcon(
                                iconName: bill.iconName,
                                colorName: bill.colorName,
                                size: .body,
                                width: 24
                            )
                            VStack(alignment: .leading) {
                                Text(bill.name).fontWeight(.semibold)
                                Text(bill.categoryName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        LabeledContent(
                            "This cycle",
                            value: bill.currentAmount.formatted(currencyFormat)
                        )
                        if let previousAmount = bill.previousAmount,
                           let change = bill.change {
                            LabeledContent(
                                "Previous cycle",
                                value: previousAmount.formatted(currencyFormat)
                            )
                            ChangeSummaryView(change: change)
                        } else {
                            Text("No previous-cycle comparison")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func spendingTypeSection(_ report: FinancialCycleReport) -> some View {
        reportSection("Fixed / Recurring vs Variable") {
            amountAndPercentageRow(
                "Fixed / Recurring",
                amount: report.spendingTypes.fixedOrRecurring,
                percentage: report.spendingTypes.fixedPercentage
            )
            amountAndPercentageRow(
                "Variable",
                amount: report.spendingTypes.variable,
                percentage: report.spendingTypes.variablePercentage
            )
        }
    }

    private func automaticRecurringSection(_ report: FinancialCycleReport) -> some View {
        reportSection("Automatic Recurring") {
            if report.automaticRecurring.transactionCount == 0 {
                emptyText("No automatically generated recurring expenses.")
            } else {
                LabeledContent(
                    "Transactions",
                    value: "\(report.automaticRecurring.transactionCount)"
                )
                ForEach(report.automaticRecurring.topItems) { item in
                    LabeledContent(
                        item.title,
                        value: item.amount.formatted(currencyFormat)
                    )
                }
                Divider()
                LabeledContent(
                    "Total",
                    value: report.automaticRecurring.total.formatted(currencyFormat)
                )
                .fontWeight(.semibold)
            }
        }
    }

    private func paymentMethodSection(_ report: FinancialCycleReport) -> some View {
        reportSection("Payment Methods") {
            if report.paymentMethods.isEmpty {
                emptyText("No expense payment methods in this cycle.")
            } else {
                ForEach(report.paymentMethods) { method in
                    amountAndPercentageRow(
                        method.method.displayName,
                        amount: method.amount,
                        percentage: method.percentage
                    )
                }
            }
        }
    }

    private func creditCardSection(_ report: FinancialCycleReport) -> some View {
        reportSection("Credit Cards") {
            if report.creditCards.total == 0 {
                emptyText("No credit-card spending in this cycle.")
            } else {
                ForEach(report.creditCards.cards) { card in
                    LabeledContent(card.name, value: card.amount.formatted(currencyFormat))
                }
                Divider()
                LabeledContent(
                    "Installments",
                    value: report.creditCards.installmentAmount.formatted(currencyFormat)
                )
                LabeledContent(
                    "One-time purchases",
                    value: report.creditCards.oneTimeAmount.formatted(currencyFormat)
                )
                amountAndPercentageRow(
                    "Total",
                    amount: report.creditCards.total,
                    percentage: report.creditCards.percentage
                )
            }
        }
    }

    private func topExpensesSection(_ report: FinancialCycleReport) -> some View {
        reportSection("Top Expenses") {
            if report.topExpenses.isEmpty {
                emptyText("No expenses in this cycle.")
            } else {
                ForEach(report.topExpenses) { expense in
                    HStack(alignment: .top, spacing: 10) {
                        CategoryIcon(
                            iconName: expense.iconName,
                            colorName: expense.colorName,
                            size: .body,
                            width: 24
                        )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(expense.title).fontWeight(.semibold)
                            Text(expense.categoryName)
                            expenseDetails(expense)
                            Text(expense.effectiveDate, format: .dateTime.day().month().year())
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Spacer()
                        Text(expense.amount.formatted(currencyFormat))
                            .fontWeight(.semibold)
                    }
                }
            }
        }
    }

    private func budgetPerformanceSection(_ report: FinancialCycleReport) -> some View {
        reportSection("Budget Performance") {
            if report.budgetPerformance.isEmpty {
                emptyText("No category budgets configured.")
            } else {
                ForEach(BudgetPerformanceStatus.allCases) { status in
                    let items = report.budgetPerformance.filter { $0.status == status }
                    if !items.isEmpty {
                        DisclosureGroup("\(status.displayName) (\(items.count))") {
                            ForEach(items) { item in
                                budgetPerformanceRow(item)
                            }
                            .padding(.top, 6)
                        }
                    }
                }
            }
        }
    }

    private func budgetPerformanceRow(
        _ item: BudgetPerformanceCycleReport
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                CategoryIcon(
                    iconName: item.iconName,
                    colorName: item.colorName,
                    size: .body,
                    width: 22
                )
                Text(item.categoryName)
                Spacer()
                Text(item.percentage.formatted(.percent.precision(.fractionLength(0)).locale(AppLocalization.selectedLocale)))
            }
            Text("\(item.spent.formatted(currencyFormat)) of \(item.limit.formatted(currencyFormat))")
                .font(.caption)
            Text(
                item.remaining >= 0
                    ? "\(item.remaining.formatted(currencyFormat)) remaining"
                    : "\((-item.remaining).formatted(currencyFormat)) over budget"
            )
            .font(.caption)
            .foregroundStyle(item.status == .over ? .red : .secondary)
        }
        .padding(.vertical, 4)
    }

    private func comparisonSection(_ report: FinancialCycleReport) -> some View {
        reportSection("Compared with Previous Cycle") {
            ForEach(report.comparisons) { comparison in
                VStack(alignment: .leading, spacing: 5) {
                    Text(comparison.title).fontWeight(.semibold)
                    HStack {
                        Text("Previous: \(comparison.change.previous.formatted(currencyFormat))")
                        Spacer()
                        Text("Current: \(comparison.change.current.formatted(currencyFormat))")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    ChangeSummaryView(change: comparison.change)
                }
                .padding(.vertical, 3)
            }
        }
    }

    private func insightsSection(_ report: FinancialCycleReport) -> some View {
        reportSection("Insights") {
            if report.insights.isEmpty {
                emptyText("No notable changes for this cycle.")
            } else {
                ForEach(report.insights) { insight in
                    Label(insight.message, systemImage: "lightbulb")
                        .font(.subheadline)
                }
            }
        }
    }

    private func reportSection<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2.bold())
            VStack(alignment: .leading, spacing: 12, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.background.secondary, in: .rect(cornerRadius: 16))
        }
    }

    private func reportMetric(
        _ title: LocalizedStringKey,
        amount: Decimal,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(amount.formatted(currencyFormat))
                .font(.headline)
                .foregroundStyle(tint)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: .rect(cornerRadius: 12))
    }

    private func budgetSummary(spent: Decimal, budget: Decimal) -> some View {
        let remaining = budget - spent
        let usage = budget > 0
            ? NSDecimalNumber(decimal: spent / budget).doubleValue
            : 0
        return VStack(alignment: .leading, spacing: 7) {
            LabeledContent("Total budget", value: budget.formatted(currencyFormat))
            LabeledContent(
                "Budget used",
                value: usage.formatted(.percent.precision(.fractionLength(1)).locale(AppLocalization.selectedLocale))
            )
            LabeledContent(
                remaining >= 0 ? "Remaining" : "Exceeded by",
                value: abs(remaining).formatted(currencyFormat)
            )
            ProgressView(value: min(max(usage, 0), 1))
                .tint(usage >= 1 ? .red : usage >= 0.8 ? .orange : .accentColor)
        }
    }

    private func amountAndPercentageRow(
        _ title: LocalizedStringResource,
        amount: Decimal,
        percentage: Double
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            VStack(alignment: .trailing) {
                Text(amount.formatted(currencyFormat)).fontWeight(.semibold)
                Text(percentage.formatted(.percent.precision(.fractionLength(1)).locale(AppLocalization.selectedLocale)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func expenseDetails(_ expense: TopExpenseCycleReport) -> Text {
        var details = Text(expense.paymentMethod.displayName)
        if let cardName = expense.cardName {
            details = Text("\(details) • \(cardName)")
        }
        if let installment = expense.installmentDescription {
            details = Text("\(details) • \(installment)")
        }
        return details
    }

    private func cycleLabel(_ cycle: FinancialCycle) -> String {
        guard let finalDay = Calendar.current.date(
            byAdding: .day,
            value: -1,
            to: cycle.end
        ) else { return "" }
        let startFormat = Date.FormatStyle.dateTime
            .month(.abbreviated)
            .day()
            .locale(AppLocalization.selectedLocale)
        let endFormat = Date.FormatStyle.dateTime
            .month(.abbreviated)
            .day()
            .year()
            .locale(AppLocalization.selectedLocale)
        return "\(cycle.start.formatted(startFormat)) – \(finalDay.formatted(endFormat))"
    }

    private func emptyText(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ChangeSummaryView: View {
    let change: ReportChange

    private let currencyFormat = Decimal.FormatStyle.Currency(code: "BRL")
        .locale(AppLocalization.selectedLocale)

    var body: some View {
        HStack(spacing: 8) {
            Text(signedAmount)
            if let percentage = change.percentage {
                Text(signedPercentage(percentage))
            } else {
                Text("No percentage comparison")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .foregroundStyle(change.difference > 0 ? .orange : change.difference < 0 ? .green : .secondary)
    }

    private var signedAmount: String {
        let prefix = change.difference > 0 ? "+ " : change.difference < 0 ? "− " : ""
        return prefix + abs(change.difference).formatted(currencyFormat)
    }

    private func signedPercentage(_ value: Double) -> String {
        let prefix = value > 0 ? "+ " : value < 0 ? "− " : ""
        return prefix + abs(value).formatted(.percent.precision(.fractionLength(1)).locale(AppLocalization.selectedLocale))
    }
}

private struct CategoryReportChart: View {
    let categories: [CategoryCycleReport]

    var body: some View {
        Chart(categories) { category in
            BarMark(
                x: .value("Amount", NSDecimalNumber(decimal: category.amount).doubleValue),
                y: .value("Category", category.name)
            )
            .foregroundStyle(Color.category(named: category.colorName))
            .cornerRadius(4)
        }
        .chartXAxis {
            AxisMarks(position: .bottom) {
                AxisGridLine()
                AxisValueLabel(format: Decimal.FormatStyle.Currency(code: "BRL").locale(AppLocalization.selectedLocale))
            }
        }
        .frame(height: min(max(CGFloat(categories.count) * 34, 180), 420))
        .accessibilityLabel("Spending distribution by category")
    }
}
