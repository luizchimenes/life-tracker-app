import SwiftData
import SwiftUI

enum TransactionTypeFilter: String, CaseIterable, Identifiable {
    case all, income, expense, investment
    var id: Self { self }
    var title: LocalizedStringResource {
        switch self {
        case .all: "All"
        case .income: "Income"
        case .expense: "Expense"
        case .investment: "Investment"
        }
    }
}

enum SpendingKindFilter: String, CaseIterable, Identifiable {
    case all
    case fixed
    case variable
    var id: Self { self }
    var title: LocalizedStringResource {
        switch self {
        case .all: "All"
        case .fixed: "Fixed / Recurring"
        case .variable: "Variable"
        }
    }
}

enum TransactionCycleFilter: String, CaseIterable, Identifiable {
    case current
    case previous
    case all
    var id: Self { self }
    var title: LocalizedStringResource {
        switch self {
        case .current: "Current Financial Cycle"
        case .previous: "Previous Financial Cycle"
        case .all: "All Activity"
        }
    }
}

enum TransactionSortOrder: String, CaseIterable, Identifiable {
    case dateDescending
    case dateAscending
    case amountDescending
    case amountAscending
    var id: Self { self }
    var title: LocalizedStringResource {
        switch self {
        case .dateDescending: "Transaction Date: Newest"
        case .dateAscending: "Transaction Date: Oldest"
        case .amountDescending: "Amount: High to Low"
        case .amountAscending: "Amount: Low to High"
        }
    }
}

struct TransactionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var transactions: [Transaction]
    @Query(sort: \TransactionCategory.name) private var categories: [TransactionCategory]
    @Query(sort: \CreditCard.name) private var creditCards: [CreditCard]

    @State private var searchText = ""
    @State private var typeFilter = TransactionTypeFilter.all
    @State private var categoryID: UUID?
    @State private var paymentMethod: PaymentMethod?
    @State private var creditCardID: UUID?
    @State private var spendingKind = SpendingKindFilter.all
    @State private var cycleFilter = TransactionCycleFilter.current
    @State private var selectedCycleStart = FinancialCycle(containing: Date.now)?.start
    @State private var sortOrder = TransactionSortOrder.dateDescending
    @State private var showsFilters = false
    @State private var transactionToDelete: Transaction?
    @State private var errorMessage: String?

    private var hasActiveFilters: Bool {
        typeFilter != .all || categoryID != nil || paymentMethod != nil
            || creditCardID != nil || spendingKind != .all || cycleFilter != .all
    }

    private var periods: [TransactionPeriodSummary] {
        TransactionPeriodSummary.recentCycles(transactions: transactions)
    }

    private var selectedPeriod: TransactionPeriodSummary? {
        guard let selectedCycleStart else { return nil }
        return periods.first {
            Calendar.current.isDate($0.cycle.start, inSameDayAs: selectedCycleStart)
        }
    }

    private var filteredTransactions: [Transaction] {
        let matching = transactions
            .filter(matchesSearch)
            .filter(matchesFilters)
        let visible = cycleFilter == .all && selectedPeriod == nil
            ? TransactionActivity.purchaseRepresentatives(from: matching)
            : matching
        return visible.sorted(by: sortTransactions)
    }

    private var groupedTransactions: [TransactionDateGroup] {
        let grouped = Dictionary(grouping: filteredTransactions) {
            Calendar.current.startOfDay(for: $0.date)
        }
        return grouped.map {
            TransactionDateGroup(date: $0.key, transactions: $0.value)
        }
        .sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            Section {
                TransactionPeriodChart(
                    periods: periods,
                    selectedCycleStart: $selectedCycleStart
                )
                if let selectedPeriod {
                    PeriodSummaryView(summary: selectedPeriod)
                } else {
                    Text("All Activity")
                        .font(.headline)
                }
            } header: {
                HStack {
                    Text(selectedPeriod.map(periodLabel) ?? AppLocalization.string("All Activity"))
                    Spacer()
                    if selectedPeriod != nil {
                        Button("All Activity") {
                            selectedCycleStart = nil
                            cycleFilter = .all
                        }
                        .textCase(nil)
                    }
                }
            }

            if filteredTransactions.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ForEach(groupedTransactions, id: \.date) { group in
                    Section(groupTitle(for: group.date)) {
                        ForEach(group.transactions) { transaction in
                            NavigationLink {
                                TransactionDetailView(transaction: transaction)
                            } label: {
                                TransactionRow(transaction: transaction)
                            }
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    transactionToDelete = transaction
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Transactions")
        .searchable(text: $searchText, prompt: "Title, category, or notes")
        .onChange(of: selectedCycleStart) {
            guard let selectedCycleStart,
                  let nearest = periods.min(by: {
                      abs($0.cycle.start.timeIntervalSince(selectedCycleStart))
                          < abs($1.cycle.start.timeIntervalSince(selectedCycleStart))
                  }) else {
                return
            }
            self.selectedCycleStart = nearest.cycle.start
            cycleFilter = .all
        }
        .onChange(of: cycleFilter) {
            guard let current = FinancialCycle(containing: .now) else { return }
            switch cycleFilter {
            case .current:
                selectedCycleStart = current.start
            case .previous:
                selectedCycleStart = current.shifted(byMonths: -1)?.start
            case .all:
                break
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu("Sort", systemImage: "arrow.up.arrow.down") {
                    Picker("Sort", selection: $sortOrder) {
                        ForEach(TransactionSortOrder.allCases) { order in
                            Text(order.title).tag(order)
                        }
                    }
                }
                Button("Filters", systemImage: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle") {
                    showsFilters = true
                }
            }
        }
        .sheet(isPresented: $showsFilters) {
            TransactionFiltersView(
                typeFilter: $typeFilter,
                categoryID: $categoryID,
                paymentMethod: $paymentMethod,
                creditCardID: $creditCardID,
                spendingKind: $spendingKind,
                cycleFilter: $cycleFilter,
                categories: categories,
                creditCards: creditCards,
                reset: resetFilters
            )
        }
        .confirmationDialog(
            transactionToDelete?.sourceKind != .installment ? "Delete Transaction?" : "Delete Entire Installment Purchase?",
            isPresented: Binding(get: { transactionToDelete != nil }, set: { if !$0 { transactionToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(transactionToDelete?.sourceKind != .installment ? "Delete Transaction" : "Delete Entire Purchase", role: .destructive) {
                deleteSelectedTransaction()
            }
            Button("Cancel", role: .cancel) { transactionToDelete = nil }
        } message: {
            Text(deletionMessage)
        }
        .alert("Unable to Delete", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func matchesSearch(_ transaction: Transaction) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return transaction.title.localizedCaseInsensitiveContains(query)
            || transaction.notes.localizedCaseInsensitiveContains(query)
            || (transaction.category?.name.localizedCaseInsensitiveContains(query) ?? false)
            || (transaction.category?.displayName().localizedCaseInsensitiveContains(query) ?? false)
            || (transaction.category?.displayName().localizedCaseInsensitiveContains(query) ?? false)
    }

    private func matchesFilters(_ transaction: Transaction) -> Bool {
        if typeFilter == .income, transaction.type != .income { return false }
        if typeFilter == .expense, transaction.type != .expense { return false }
        if typeFilter == .investment, transaction.type != .investment { return false }
        if let selectedPeriod,
           !selectedPeriod.cycle.contains(transaction.effectiveFinancialDate) {
            return false
        }
        if let categoryID, transaction.category?.id != categoryID { return false }
        if let paymentMethod, transaction.paymentMethod != paymentMethod { return false }
        if let creditCardID, transaction.creditCard?.id != creditCardID { return false }
        let classification = SpendingClassification.classify(transaction)
        if spendingKind != .all, transaction.type != .expense { return false }
        if spendingKind == .fixed, classification != .fixedOrRecurring { return false }
        if spendingKind == .variable, classification != .variable { return false }
        guard cycleFilter != .all else { return true }
        guard let current = FinancialCycle(containing: .now) else { return false }
        let cycle = cycleFilter == .current ? current : current.shifted(byMonths: -1)
        return cycle.map { TransactionActivity.belongs(transaction, to: $0) } ?? false
    }

    private func sortTransactions(_ lhs: Transaction, _ rhs: Transaction) -> Bool {
        switch sortOrder {
        case .dateDescending: TransactionActivity.transactionDateDescending(lhs, rhs)
        case .dateAscending: TransactionActivity.transactionDateDescending(rhs, lhs)
        case .amountDescending: lhs.amount > rhs.amount
        case .amountAscending: lhs.amount < rhs.amount
        }
    }

    private func periodLabel(_ summary: TransactionPeriodSummary) -> String {
        let end = Calendar.current.date(byAdding: .day, value: -1, to: summary.cycle.end)
            ?? summary.cycle.end
        let format = Date.FormatStyle.dateTime
            .month(.abbreviated)
            .day()
            .locale(AppLocalization.selectedLocale)
        return "\(summary.cycle.start.formatted(format)) – \(end.formatted(format))"
    }

    private func groupTitle(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return AppLocalization.string("Today")
        }
        if Calendar.current.isDateInYesterday(date) {
            return AppLocalization.string("Yesterday")
        }
        return date.formatted(
            .dateTime
                .day()
                .month(.wide)
                .year()
                .locale(AppLocalization.selectedLocale)
        )
    }

    private var deletionMessage: LocalizedStringResource {
        guard let transactionToDelete else { return "" }
        switch transactionToDelete.sourceKind {
        case .recurring: return "Only this historical occurrence is removed. Future occurrences continue."
        case .fixedBill: return "The linked bill returns to pending and its estimate returns to projections."
        case .installment: return "All installments for this purchase are removed from their invoices."
        case .manual: return "This transaction will be permanently deleted."
        }
    }

    private func deleteSelectedTransaction() {
        guard let transactionToDelete else { return }
        do {
            let records = try TransactionDeletionService.transactionsForSafeDeletion(of: transactionToDelete, from: transactions)
            try TransactionDeletionService.delete(records, from: transactions, in: modelContext)
            self.transactionToDelete = nil
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private func resetFilters() {
        typeFilter = .all
        categoryID = nil
        paymentMethod = nil
        creditCardID = nil
        spendingKind = .all
        cycleFilter = .all
    }
}

private struct TransactionDateGroup {
    let date: Date
    let transactions: [Transaction]
}

private struct PeriodSummaryView: View {
    let summary: TransactionPeriodSummary

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
            GridRow {
                metric("Income", amount: summary.income)
                metric("Expenses", amount: summary.expenses)
            }
            GridRow {
                metric("Investments", amount: summary.investments)
                metric("Balance", amount: summary.balance)
            }
            GridRow {
                metric(
                    "Available After Investments",
                    amount: summary.availableAfterInvestments
                )
                .gridCellColumns(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metric(
        _ title: LocalizedStringResource,
        amount: Decimal
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(
                amount,
                format: .currency(code: "BRL")
                    .locale(AppLocalization.selectedLocale)
            )
            .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TransactionFiltersView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var typeFilter: TransactionTypeFilter
    @Binding var categoryID: UUID?
    @Binding var paymentMethod: PaymentMethod?
    @Binding var creditCardID: UUID?
    @Binding var spendingKind: SpendingKindFilter
    @Binding var cycleFilter: TransactionCycleFilter
    let categories: [TransactionCategory]
    let creditCards: [CreditCard]
    let reset: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $typeFilter) {
                    ForEach(TransactionTypeFilter.allCases) { Text($0.title).tag($0) }
                }
                Picker("Financial Cycle", selection: $cycleFilter) {
                    ForEach(TransactionCycleFilter.allCases) { Text($0.title).tag($0) }
                }
                Picker("Category", selection: $categoryID) {
                    Text("All Categories").tag(UUID?.none)
                    ForEach(categories) { Text($0.displayName()).tag(Optional($0.id)) }
                }
                Picker("Payment Method", selection: $paymentMethod) {
                    Text("All Methods").tag(PaymentMethod?.none)
                    ForEach(PaymentMethod.allCases) { Text($0.displayName).tag(Optional($0)) }
                }
                Picker("Credit Card", selection: $creditCardID) {
                    Text("All Cards").tag(UUID?.none)
                    ForEach(creditCards) { Text($0.name).tag(Optional($0.id)) }
                }
                Picker("Spending", selection: $spendingKind) {
                    ForEach(SpendingKindFilter.allCases) { Text($0.title).tag($0) }
                }
                Button("Reset Filters", action: reset)
            }
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
