import SwiftData
import SwiftUI

struct FinanceView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var budgets: [CategoryBudget]
    @Query private var settingsRecords: [FinanceSettings]
    @Environment(\.presentAppSettings) private var presentAppSettings
    @Query private var recurringTransactions: [RecurringTransaction]
    @Query private var fixedBillOccurrences: [FixedBillOccurrence]
    @Query private var creditCardInvoices: [CreditCardInvoice]

    @State private var showsAddTransaction = false
    @State private var showsManageBudgets = false
    @State private var showsManageCategories = false
    @State private var showsMonthlyBudget = false
    @State private var showsRecurringTransactions = false
    @State private var showsAnalytics = false
    @State private var showsCreditCards = false
    @State private var showsManageFixedBills = false
    @State private var showsReports = false
    @State private var showsTransactions = false
    @State private var occurrenceToPay: FixedBillOccurrence?
    @State private var occurrenceToSkip: FixedBillOccurrence?
    @State private var occurrenceToRevert: FixedBillOccurrence?
    @State private var invoiceToPay: CreditCardInvoice?
    @State private var paymentErrorMessage = ""
    @State private var showsPaymentError = false

    @State private var showsCycleDetails = false

    private var overview: FinanceOverview {
        FinanceOverview(
            transactions: transactions,
            recurringTransactions: recurringTransactions,
            fixedBillOccurrences: fixedBillOccurrences,
            creditCardInvoices: creditCardInvoices,
            monthlyBudget: monthlyBudget
        )
    }

    private var fixedBillSnapshot: FixedBillCycleSnapshot {
        FixedBillCycleSnapshot(occurrences: fixedBillOccurrences)
    }

    private var monthlyBudget: Decimal? {
        guard let budget = settingsRecords.first?.monthlySpendingBudget,
              budget > 0 else {
            return nil
        }

        return budget
    }

    private func configuredBudgets(_ snapshot: MonthlyFinanceSnapshot) -> [CategoryBudget] {
        budgets
            .filter { $0.monthlyLimit > 0 && $0.category.type.supports(.expense) }
            .sorted { budgetUsage($0, snapshot) > budgetUsage($1, snapshot) }
    }

    private var recentTransactions: [Transaction] {
        TransactionActivity.recent(from: transactions, limit: 5)
    }

    var body: some View {
        let overview = self.overview
        let snapshot = overview.actual
        let projection = overview.projection
        let bills = overview.bills
        let configuredBudgets = configuredBudgets(snapshot)

        NavigationStack {
            List {
                Section {
                    SafeToSpendView(safeToSpend: overview.safeToSpend)
                        .padding(.vertical, 4)

                    DisclosureGroup("Cycle Details", isExpanded: $showsCycleDetails) {
                        FinanceSummaryView(
                            income: snapshot.income,
                            expenses: snapshot.expenses,
                            investments: snapshot.investments,
                            balance: snapshot.balance,
                            availableAfterInvestments: snapshot.availableAfterInvestments
                        )
                        FinanceProjectionView(
                            projection: projection,
                            monthlyBudget: monthlyBudget
                        )
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Financial Cycle")
                        if let cycleDescription = cycleDescription(snapshot) {
                            Text("\(cycleDescription) • \(Text("\(overview.safeToSpend.daysRemaining) days remaining"))")
                                .font(.caption)
                                .textCase(nil)
                        }
                    }
                }

                Section("This Cycle") {
                    CycleActivitySummaryView(projection: projection)
                }

                if !fixedBillSnapshot.occurrences.isEmpty
                    || !bills.payableInvoices.isEmpty
                    || !bills.upcomingInvoices.isEmpty {
                    Section {
                        ForEach(bills.payableInvoices) { item in
                            InvoiceBillRow(
                                invoice: item.invoice,
                                total: item.total
                            ) {
                                invoiceToPay = item.invoice
                            }
                        }

                        ForEach(fixedBillSnapshot.occurrences) { occurrence in
                            FixedBillOccurrenceRow(occurrence: occurrence) {
                                if occurrence.status == .paid {
                                    occurrenceToRevert = occurrence
                                } else if occurrence.status == .pending {
                                    occurrenceToPay = occurrence
                                } else {
                                    restoreSkipped(occurrence)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                if occurrence.status == .pending {
                                    Button("Skip", systemImage: "forward.fill") {
                                        occurrenceToSkip = occurrence
                                    }
                                    .tint(.orange)
                                }
                            }
                        }

                        ForEach(bills.upcomingInvoices) { item in
                            InvoicePreviewRow(item: item)
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bills to Pay")
                            BillsToPaySummaryView(bills: bills)
                                .font(.caption)
                                .textCase(nil)
                        }
                    }
                }

                Section("Budgets") {
                    if let monthlyBudget {
                        MonthlyBudgetSummaryView(
                            amountSpent: snapshot.expenses,
                            budget: monthlyBudget
                        )
                    }

                    if configuredBudgets.isEmpty && monthlyBudget == nil {
                        Text("No budgets configured")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(configuredBudgets) { budget in
                            CategoryBudgetRow(
                                budget: budget,
                                amountSpent: snapshot.expenses(for: budget.category),
                                pendingRecurringAmount: projection.pendingRecurringExpenses(
                                    for: budget.category
                                ) + projection.pendingFixedBillExpenses(for: budget.category)
                            )
                        }
                    }
                }

                if !projection.upcomingOccurrences.isEmpty {
                    Section("Upcoming") {
                        ForEach(projection.upcomingOccurrences.prefix(5)) { occurrence in
                            UpcomingRecurringOccurrenceRow(
                                occurrence: occurrence
                            )
                        }
                    }
                }

                Section {
                    if recentTransactions.isEmpty {
                        ContentUnavailableView(
                            "No Transactions",
                            systemImage: "list.bullet.rectangle",
                            description: Text("Tap the add button to record your first transaction.")
                        )
                    } else {
                        ForEach(recentTransactions) { transaction in
                            NavigationLink {
                                TransactionDetailView(transaction: transaction)
                            } label: {
                                TransactionRow(transaction: transaction)
                            }
                        }
                        Button("View All Transactions", systemImage: "list.bullet.rectangle") {
                            showsTransactions = true
                        }
                    }
                } header: {
                    Text("Recent Activity")
                }
            }
            .navigationTitle("Finance")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu("Finance Actions", systemImage: "ellipsis.circle") {
                        Button("Transactions", systemImage: "list.bullet.rectangle") {
                            showsTransactions = true
                        }
                        Button("Credit Cards", systemImage: "creditcard") { showsCreditCards = true }
                        Button("Fixed Expenses", systemImage: "checklist") {
                            showsManageFixedBills = true
                        }

                        Menu("Insights", systemImage: "chart.bar.xaxis") {
                            Button("Analytics", systemImage: "chart.bar.xaxis") { showsAnalytics = true }
                            Button("Reports", systemImage: "doc.text.magnifyingglass") { showsReports = true }
                        }

                        Menu("Manage", systemImage: "gearshape") {
                            Button("App Settings", systemImage: "globe") { presentAppSettings() }
                            Button("Categories", systemImage: "tag") { showsManageCategories = true }
                            Button("Category Budgets", systemImage: "gauge.with.dots.needle.33percent") { showsManageBudgets = true }
                            Button("Financial Cycle Budget", systemImage: "calendar") { showsMonthlyBudget = true }
                            Button("Recurring Transactions", systemImage: "repeat") { showsRecurringTransactions = true }
                        }
                    }

                    Button("Add Transaction", systemImage: "plus") {
                        showsAddTransaction = true
                    }
                }
            }
            .sheet(isPresented: $showsAddTransaction) {
                AddTransactionView()
            }
            .sheet(isPresented: $showsManageBudgets) {
                ManageBudgetsView()
            }
            .sheet(isPresented: $showsManageCategories) {
                ManageCategoriesView()
            }
            .sheet(isPresented: $showsMonthlyBudget) {
                ManageMonthlyBudgetView()
            }
            .sheet(isPresented: $showsRecurringTransactions) {
                ManageRecurringTransactionsView()
            }
            .sheet(isPresented: $showsAnalytics) {
                FinanceAnalyticsView()
            }
            .sheet(isPresented: $showsCreditCards) {
                CreditCardsView()
            }
            .sheet(isPresented: $showsManageFixedBills) {
                ManageFixedBillsView()
            }
            .sheet(isPresented: $showsReports) {
                FinancialCycleReportView()
            }
            .sheet(isPresented: $showsTransactions) {
                NavigationStack { TransactionsView() }
            }
            .sheet(item: $occurrenceToPay) { occurrence in
                MarkBillPaidView(occurrence: occurrence)
            }
            .alert("Unable to Update Bill", isPresented: $showsPaymentError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(paymentErrorMessage)
            }
            .confirmationDialog(
                "Skip This Bill?",
                isPresented: Binding(get: { occurrenceToSkip != nil }, set: { if !$0 { occurrenceToSkip = nil } }),
                titleVisibility: .visible
            ) {
                Button("Skip Bill", role: .destructive) {
                    if let occurrenceToSkip { skip(occurrenceToSkip) }
                    occurrenceToSkip = nil
                }
                Button("Cancel", role: .cancel) { occurrenceToSkip = nil }
            } message: {
                Text("No expense transaction will be created, and this occurrence will be removed from projections.")
            }
            .confirmationDialog(
                "Revert This Payment?",
                isPresented: Binding(get: { occurrenceToRevert != nil }, set: { if !$0 { occurrenceToRevert = nil } }),
                titleVisibility: .visible
            ) {
                Button("Revert to Pending", role: .destructive) {
                    if let occurrenceToRevert { revertToPending(occurrenceToRevert) }
                    occurrenceToRevert = nil
                }
                Button("Cancel", role: .cancel) { occurrenceToRevert = nil }
            } message: {
                Text("Only the linked payment transaction will be deleted. The bill will return to pending and its estimate will return to projections.")
            }
            .confirmationDialog(
                "Pay Invoice?",
                isPresented: Binding(get: { invoiceToPay != nil }, set: { if !$0 { invoiceToPay = nil } }),
                titleVisibility: .visible
            ) {
                Button("Mark as Paid") {
                    if let invoiceToPay { payInvoice(invoiceToPay) }
                    invoiceToPay = nil
                }
                Button("Cancel", role: .cancel) { invoiceToPay = nil }
            } message: {
                Text("This settles the card and releases its limit. No new expense is created because the purchases were already counted when made.")
            }
            .task {
                try? TransactionCategory.seedDefaultsIfNeeded(in: modelContext)
            }
        }
    }

    private func budgetUsage(_ budget: CategoryBudget, _ snapshot: MonthlyFinanceSnapshot) -> Decimal {
        guard budget.monthlyLimit > 0 else {
            return 0
        }

        return snapshot.expenses(for: budget.category) / budget.monthlyLimit
    }

    private func cycleDescription(_ snapshot: MonthlyFinanceSnapshot) -> String? {
        guard let cycle = snapshot.cycle,
              let inclusiveEnd = Calendar.current.date(byAdding: .day, value: -1, to: cycle.end) else {
            return nil
        }

        let dateFormat = Date.FormatStyle.dateTime
            .month(.abbreviated)
            .day()
            .locale(AppLocalization.selectedLocale)
        let start = cycle.start.formatted(dateFormat)
        let end = inclusiveEnd.formatted(dateFormat)
        return "\(start) – \(end)"
    }

    private func revertToPending(_ occurrence: FixedBillOccurrence) {
        do {
            try FixedBillPaymentService.revertToPending(
                occurrence: occurrence,
                in: modelContext
            )
        } catch {
            paymentErrorMessage = error.localizedDescription
            showsPaymentError = true
        }
    }

    private func payInvoice(_ invoice: CreditCardInvoice) {
        do {
            try CreditCardInvoicePaymentService.markPaid(invoice, in: modelContext)
        } catch {
            modelContext.rollback()
            paymentErrorMessage = error.localizedDescription
            showsPaymentError = true
        }
    }

    private func skip(_ occurrence: FixedBillOccurrence) {
        do {
            try FixedBillPaymentService.skip(occurrence: occurrence, in: modelContext)
        } catch {
            modelContext.rollback()
            paymentErrorMessage = error.localizedDescription
            showsPaymentError = true
        }
    }

    private func restoreSkipped(_ occurrence: FixedBillOccurrence) {
        do {
            try FixedBillPaymentService.restoreSkippedToPending(occurrence: occurrence, in: modelContext)
        } catch {
            modelContext.rollback()
            paymentErrorMessage = error.localizedDescription
            showsPaymentError = true
        }
    }
}

#Preview {
    FinanceView()
        .modelContainer(LifeTrackerPersistence.previewContainer())
}
