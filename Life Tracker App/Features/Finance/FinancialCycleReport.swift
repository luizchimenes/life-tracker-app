import Foundation

struct ReportChange {
    let current: Decimal
    let previous: Decimal

    var difference: Decimal { current - previous }

    var percentage: Double? {
        guard previous != 0 else { return nil }
        return NSDecimalNumber(decimal: difference / abs(previous)).doubleValue
    }
}

enum BudgetPerformanceStatus: Int, CaseIterable, Identifiable {
    case within
    case close
    case over

    var id: Self { self }

    var displayName: LocalizedStringResource {
        switch self {
        case .within: "Within Budget"
        case .close: "Close to Budget"
        case .over: "Over Budget"
        }
    }
}

struct CategoryCycleReport: Identifiable {
    let id: String
    let categoryID: UUID?
    let name: String
    let iconName: String
    let colorName: String
    let amount: Decimal
    let totalPercentage: Double
    let budgetLimit: Decimal?
    let previousAmount: Decimal

    var change: ReportChange {
        ReportChange(current: amount, previous: previousAmount)
    }

    var budgetPercentage: Double? {
        guard let budgetLimit, budgetLimit > 0 else { return nil }
        return NSDecimalNumber(decimal: amount / budgetLimit).doubleValue
    }

    var budgetRemaining: Decimal? {
        budgetLimit.map { $0 - amount }
    }
}

struct FixedCommitmentCycleReport {
    let totalCount: Int
    let paidCount: Int
    let pendingCount: Int
    let skippedCount: Int
    let amountPaid: Decimal
    let estimatedRemaining: Decimal
    let unknownRemainingCount: Int
}

struct FixedBillHistoryCycleReport: Identifiable {
    let id: UUID
    let name: String
    let categoryName: String
    let iconName: String
    let colorName: String
    let currentAmount: Decimal
    let previousAmount: Decimal?

    var change: ReportChange? {
        previousAmount.map { ReportChange(current: currentAmount, previous: $0) }
    }
}

struct SpendingTypeCycleReport {
    let fixedOrRecurring: Decimal
    let variable: Decimal
    let totalExpenses: Decimal

    var fixedPercentage: Double {
        Self.percentage(fixedOrRecurring, of: totalExpenses)
    }

    var variablePercentage: Double {
        Self.percentage(variable, of: totalExpenses)
    }

    private static func percentage(_ value: Decimal, of total: Decimal) -> Double {
        guard total > 0 else { return 0 }
        return NSDecimalNumber(decimal: value / total).doubleValue
    }
}

struct AutomaticRecurringItemReport: Identifiable {
    let id: UUID
    let title: String
    let amount: Decimal
}

struct AutomaticRecurringCycleReport {
    let total: Decimal
    let transactionCount: Int
    let topItems: [AutomaticRecurringItemReport]
}

struct PaymentMethodCycleReport: Identifiable {
    let method: PaymentMethod
    let amount: Decimal
    let percentage: Double

    var id: PaymentMethod { method }
}

struct CreditCardItemReport: Identifiable {
    let id: String
    let name: String
    let amount: Decimal
}

struct CreditCardCycleReport {
    let total: Decimal
    let percentage: Double
    let cards: [CreditCardItemReport]
    let installmentAmount: Decimal
    let oneTimeAmount: Decimal
}

struct TopExpenseCycleReport: Identifiable {
    let id: UUID
    let title: String
    let categoryName: String
    let iconName: String
    let colorName: String
    let effectiveDate: Date
    let paymentMethod: PaymentMethod
    let cardName: String?
    let installmentDescription: String?
    let amount: Decimal
}

struct BudgetPerformanceCycleReport: Identifiable {
    let id: UUID
    let categoryName: String
    let iconName: String
    let colorName: String
    let spent: Decimal
    let limit: Decimal
    let status: BudgetPerformanceStatus

    var percentage: Double {
        guard limit > 0 else { return 0 }
        return NSDecimalNumber(decimal: spent / limit).doubleValue
    }

    var remaining: Decimal { limit - spent }
}

struct CycleMetricComparison: Identifiable {
    let id: String
    let title: String
    let change: ReportChange
}

struct ReportInsight: Identifiable {
    let message: String
    var id: String { message }
}

struct FinancialCycleReport {
    let cycle: FinancialCycle
    let previousCycle: FinancialCycle
    let snapshot: MonthlyFinanceSnapshot
    let previousSnapshot: MonthlyFinanceSnapshot
    let monthlyBudget: Decimal?
    let categoryReports: [CategoryCycleReport]
    let fixedCommitments: FixedCommitmentCycleReport
    let fixedBillHistory: [FixedBillHistoryCycleReport]
    let spendingTypes: SpendingTypeCycleReport
    let automaticRecurring: AutomaticRecurringCycleReport
    let paymentMethods: [PaymentMethodCycleReport]
    let creditCards: CreditCardCycleReport
    let topExpenses: [TopExpenseCycleReport]
    let budgetPerformance: [BudgetPerformanceCycleReport]
    let comparisons: [CycleMetricComparison]
    let insights: [ReportInsight]

    var incomeChange: ReportChange {
        ReportChange(current: snapshot.income, previous: previousSnapshot.income)
    }

    var expenseChange: ReportChange {
        ReportChange(current: snapshot.expenses, previous: previousSnapshot.expenses)
    }

    var investmentChange: ReportChange {
        ReportChange(
            current: snapshot.investments,
            previous: previousSnapshot.investments
        )
    }

    var investmentPercentageOfIncome: Double? {
        guard snapshot.income > 0 else { return nil }
        return NSDecimalNumber(
            decimal: snapshot.investments / snapshot.income
        ).doubleValue
    }

    var balanceChange: ReportChange {
        ReportChange(current: snapshot.balance, previous: previousSnapshot.balance)
    }

    init?(
        cycle: FinancialCycle,
        transactions: [Transaction],
        categoryBudgets: [CategoryBudget],
        monthlyBudget: Decimal?,
        fixedBillOccurrences: [FixedBillOccurrence],
        calendar: Calendar = .current
    ) {
        guard let previousCycle = cycle.shifted(byMonths: -1, calendar: calendar) else {
            return nil
        }

        self.cycle = cycle
        self.previousCycle = previousCycle
        self.monthlyBudget = monthlyBudget.flatMap { $0 > 0 ? $0 : nil }

        let snapshot = MonthlyFinanceSnapshot(
            transactions: transactions,
            date: cycle.start,
            calendar: calendar
        )
        let previousSnapshot = MonthlyFinanceSnapshot(
            transactions: transactions,
            date: previousCycle.start,
            calendar: calendar
        )
        self.snapshot = snapshot
        self.previousSnapshot = previousSnapshot

        let currentAnalytics = MonthlyFinanceAnalytics(
            transactions: transactions,
            recurringTransactions: [],
            categoryBudgets: categoryBudgets,
            monthlyBudget: monthlyBudget,
            date: cycle.start,
            calendar: calendar
        )
        let previousAnalytics = MonthlyFinanceAnalytics(
            transactions: transactions,
            recurringTransactions: [],
            categoryBudgets: categoryBudgets,
            monthlyBudget: monthlyBudget,
            date: previousCycle.start,
            calendar: calendar
        )

        let previousCategories = Dictionary(
            uniqueKeysWithValues: previousAnalytics.categorySpending.map {
                ($0.id, $0.amount)
            }
        )
        categoryReports = currentAnalytics.categorySpending.map { category in
            CategoryCycleReport(
                id: category.id,
                categoryID: category.categoryID,
                name: category.name,
                iconName: category.iconName,
                colorName: category.colorName,
                amount: category.amount,
                totalPercentage: category.percentage(of: snapshot.expenses),
                budgetLimit: category.budgetLimit,
                previousAmount: previousCategories[category.id, default: 0]
            )
        }

        let currentOccurrences = fixedBillOccurrences.filter {
            cycle.contains($0.dueDate)
        }
        let previousOccurrences = fixedBillOccurrences.filter {
            previousCycle.contains($0.dueDate)
        }
        fixedCommitments = Self.makeFixedCommitments(currentOccurrences)
        fixedBillHistory = Self.makeFixedBillHistory(
            current: currentOccurrences,
            previous: previousOccurrences
        )

        spendingTypes = SpendingTypeCycleReport(
            fixedOrRecurring: currentAnalytics.fixedOrRecurringExpenses,
            variable: currentAnalytics.variableExpenses,
            totalExpenses: snapshot.expenses
        )

        let currentExpenses = snapshot.transactions.filter { $0.type == .expense }
        let previousExpenses = previousSnapshot.transactions.filter { $0.type == .expense }
        automaticRecurring = Self.makeAutomaticRecurring(currentExpenses)
        paymentMethods = Self.makePaymentMethods(
            currentExpenses,
            total: snapshot.expenses
        )
        creditCards = Self.makeCreditCards(
            currentExpenses,
            total: snapshot.expenses
        )
        topExpenses = Self.makeTopExpenses(currentExpenses)
        budgetPerformance = Self.makeBudgetPerformance(
            budgets: categoryBudgets,
            snapshot: snapshot
        )

        let previousFixed = previousAnalytics.fixedOrRecurringExpenses
        let previousVariable = previousAnalytics.variableExpenses
        let previousCard = Self.makeCreditCards(
            previousExpenses,
            total: previousSnapshot.expenses
        ).total
        comparisons = [
            CycleMetricComparison(id: "income", title: AppLocalization.string("Income"), change: ReportChange(current: snapshot.income, previous: previousSnapshot.income)),
            CycleMetricComparison(id: "expenses", title: AppLocalization.string("Expenses"), change: ReportChange(current: snapshot.expenses, previous: previousSnapshot.expenses)),
            CycleMetricComparison(id: "investments", title: AppLocalization.string("Investments"), change: ReportChange(current: snapshot.investments, previous: previousSnapshot.investments)),
            CycleMetricComparison(id: "balance", title: AppLocalization.string("Balance"), change: ReportChange(current: snapshot.balance, previous: previousSnapshot.balance)),
            CycleMetricComparison(id: "fixed", title: AppLocalization.string("Fixed / Recurring"), change: ReportChange(current: currentAnalytics.fixedOrRecurringExpenses, previous: previousFixed)),
            CycleMetricComparison(id: "variable", title: AppLocalization.string("Variable Spending"), change: ReportChange(current: currentAnalytics.variableExpenses, previous: previousVariable)),
            CycleMetricComparison(id: "card", title: AppLocalization.string("Credit Card"), change: ReportChange(current: creditCards.total, previous: previousCard))
        ]

        insights = Self.makeInsights(
            categories: categoryReports,
            commitments: fixedCommitments,
            billHistory: fixedBillHistory,
            spendingTypes: spendingTypes,
            creditCards: creditCards,
            budgetPerformance: budgetPerformance
        )
    }

    private static func makeFixedCommitments(
        _ occurrences: [FixedBillOccurrence]
    ) -> FixedCommitmentCycleReport {
        let pending = occurrences.filter { $0.status == .pending }
        return FixedCommitmentCycleReport(
            totalCount: occurrences.count,
            paidCount: occurrences.count { $0.status == .paid },
            pendingCount: pending.count,
            skippedCount: occurrences.count { $0.status == .skipped },
            amountPaid: occurrences
                .filter { $0.status == .paid }
                .compactMap(\.actualAmount)
                .reduce(Decimal.zero, +),
            estimatedRemaining: pending
                .compactMap { $0.fixedBill.estimatedAmount }
                .reduce(Decimal.zero, +),
            unknownRemainingCount: pending.count {
                $0.fixedBill.estimatedAmount == nil
            }
        )
    }

    private static func makeFixedBillHistory(
        current: [FixedBillOccurrence],
        previous: [FixedBillOccurrence]
    ) -> [FixedBillHistoryCycleReport] {
        current
            .filter { $0.status == .paid && $0.actualAmount != nil }
            .map { occurrence in
                let previousOccurrence = previous.first {
                    $0.fixedBill.id == occurrence.fixedBill.id
                        && $0.status == .paid
                        && $0.actualAmount != nil
                }
                return FixedBillHistoryCycleReport(
                    id: occurrence.fixedBill.id,
                    name: occurrence.fixedBill.name,
                    categoryName: occurrence.fixedBill.category.displayName(),
                    iconName: occurrence.fixedBill.category.iconName,
                    colorName: occurrence.fixedBill.category.colorName,
                    currentAmount: occurrence.actualAmount ?? 0,
                    previousAmount: previousOccurrence?.actualAmount
                )
            }
            .sorted { $0.currentAmount > $1.currentAmount }
    }

    private static func makeAutomaticRecurring(
        _ expenses: [Transaction]
    ) -> AutomaticRecurringCycleReport {
        let recurring = expenses.filter { $0.sourceRecurringTransactionID != nil }
        let grouped = Dictionary(grouping: recurring) {
            $0.sourceRecurringTransactionID ?? $0.id
        }
        let items = grouped.map { id, transactions in
            AutomaticRecurringItemReport(
                id: id,
                title: transactions.first?.title ?? AppLocalization.string("Recurring Expense"),
                amount: transactions.reduce(Decimal.zero) { $0 + $1.amount }
            )
        }
        .sorted { $0.amount > $1.amount }

        return AutomaticRecurringCycleReport(
            total: recurring.reduce(Decimal.zero) { $0 + $1.amount },
            transactionCount: recurring.count,
            topItems: Array(items.prefix(5))
        )
    }

    private static func makePaymentMethods(
        _ expenses: [Transaction],
        total: Decimal
    ) -> [PaymentMethodCycleReport] {
        PaymentMethod.allCases.compactMap { method in
            let amount = expenses
                .filter { $0.paymentMethod == method }
                .reduce(Decimal.zero) { $0 + $1.amount }
            guard amount > 0 else { return nil }
            return PaymentMethodCycleReport(
                method: method,
                amount: amount,
                percentage: percentage(amount, of: total)
            )
        }
        .sorted { $0.amount > $1.amount }
    }

    private static func makeCreditCards(
        _ expenses: [Transaction],
        total: Decimal
    ) -> CreditCardCycleReport {
        let cardExpenses = expenses.filter { $0.paymentMethod == .creditCard }
        let grouped = Dictionary(grouping: cardExpenses) {
            $0.creditCard?.id.uuidString ?? "unknown"
        }
        let cards = grouped.map { id, transactions in
            CreditCardItemReport(
                id: id,
                name: transactions.first?.creditCard?.name ?? AppLocalization.string("Unknown Card"),
                amount: transactions.reduce(Decimal.zero) { $0 + $1.amount }
            )
        }
        .sorted { $0.amount > $1.amount }
        let installmentAmount = cardExpenses
            .filter { ($0.totalInstallments ?? 1) > 1 }
            .reduce(Decimal.zero) { $0 + $1.amount }
        let cardTotal = cardExpenses.reduce(Decimal.zero) { $0 + $1.amount }

        return CreditCardCycleReport(
            total: cardTotal,
            percentage: percentage(cardTotal, of: total),
            cards: cards,
            installmentAmount: installmentAmount,
            oneTimeAmount: cardTotal - installmentAmount
        )
    }

    private static func makeTopExpenses(
        _ expenses: [Transaction]
    ) -> [TopExpenseCycleReport] {
        expenses
            .sorted { $0.amount > $1.amount }
            .prefix(5)
            .map { transaction in
                TopExpenseCycleReport(
                    id: transaction.id,
                    title: transaction.title,
                    categoryName: transaction.category?.displayName()
                        ?? String(localized: "Uncategorized", locale: AppLocalization.selectedLocale),
                    iconName: transaction.category?.iconName ?? "questionmark.circle.fill",
                    colorName: transaction.category?.colorName ?? "gray",
                    effectiveDate: transaction.effectiveFinancialDate,
                    paymentMethod: transaction.paymentMethod,
                    cardName: transaction.creditCard?.name,
                    installmentDescription: (transaction.totalInstallments ?? 1) > 1
                        ? "\(transaction.installmentNumber ?? 1)/\(transaction.totalInstallments ?? 1)"
                        : nil,
                    amount: transaction.amount
                )
            }
    }

    private static func makeBudgetPerformance(
        budgets: [CategoryBudget],
        snapshot: MonthlyFinanceSnapshot
    ) -> [BudgetPerformanceCycleReport] {
        budgets
            .filter { $0.monthlyLimit > 0 }
            .map { budget in
                let spent = snapshot.expenses(for: budget.category)
                let usage = spent / budget.monthlyLimit
                let status: BudgetPerformanceStatus = usage >= 1
                    ? .over
                    : usage >= Decimal(string: "0.8")! ? .close : .within
                return BudgetPerformanceCycleReport(
                    id: budget.category.id,
                    categoryName: budget.category.displayName(),
                    iconName: budget.category.iconName,
                    colorName: budget.category.colorName,
                    spent: spent,
                    limit: budget.monthlyLimit,
                    status: status
                )
            }
            .sorted {
                if $0.status.rawValue == $1.status.rawValue {
                    return $0.percentage > $1.percentage
                }
                return $0.status.rawValue > $1.status.rawValue
            }
    }

    private static func makeInsights(
        categories: [CategoryCycleReport],
        commitments: FixedCommitmentCycleReport,
        billHistory: [FixedBillHistoryCycleReport],
        spendingTypes: SpendingTypeCycleReport,
        creditCards: CreditCardCycleReport,
        budgetPerformance: [BudgetPerformanceCycleReport]
    ) -> [ReportInsight] {
        var messages: [String] = []
        let currency = Decimal.FormatStyle.Currency(code: "BRL")
            .locale(AppLocalization.selectedLocale)

        let categoryIncrease = categories
            .filter { ($0.change.percentage ?? 0) >= 0.1 }
            .max {
                ($0.change.percentage ?? 0) < ($1.change.percentage ?? 0)
            }
        if let increase = categoryIncrease,
           let percentage = increase.change.percentage {
            messages.append(AppLocalization.string("\(increase.name) spending increased \(percentage.formatted(.percent.precision(.fractionLength(1)).locale(AppLocalization.selectedLocale))) compared with the previous cycle."))
        }

        let categoryDecrease = categories
            .filter { ($0.change.percentage ?? 0) <= -0.1 }
            .min {
                ($0.change.percentage ?? 0) < ($1.change.percentage ?? 0)
            }
        if let decrease = categoryDecrease,
           let percentage = decrease.change.percentage {
            messages.append(AppLocalization.string("\(decrease.name) had the largest decrease at \(abs(percentage).formatted(.percent.precision(.fractionLength(1)).locale(AppLocalization.selectedLocale))) compared with the previous cycle."))
        }

        let billIncrease = billHistory
            .filter { ($0.change?.difference ?? 0) > 0 }
            .max {
                ($0.change?.difference ?? 0) < ($1.change?.difference ?? 0)
            }
        if let bill = billIncrease,
           let difference = bill.change?.difference {
            messages.append(AppLocalization.string("\(bill.name) increased \(difference.formatted(currency)) from the previous cycle."))
        }

        if let over = budgetPerformance.first(where: { $0.status == .over }) {
            messages.append(AppLocalization.string("\(over.categoryName) exceeded its category budget by \((-over.remaining).formatted(currency))."))
        } else if let close = budgetPerformance.first(where: { $0.status == .close }) {
            messages.append(AppLocalization.string("\(close.categoryName) used \(close.percentage.formatted(.percent.precision(.fractionLength(0)).locale(AppLocalization.selectedLocale))) of its category budget."))
        }

        if creditCards.total > 0 {
            messages.append(AppLocalization.string("Credit-card spending represented \(creditCards.percentage.formatted(.percent.precision(.fractionLength(0)).locale(AppLocalization.selectedLocale))) of total expenses."))
        }

        if spendingTypes.totalExpenses > 0 {
            messages.append(AppLocalization.string("Fixed and recurring expenses represented \(spendingTypes.fixedPercentage.formatted(.percent.precision(.fractionLength(0)).locale(AppLocalization.selectedLocale))) of spending."))
        }

        if commitments.pendingCount > 0 {
            if commitments.pendingCount == 1 {
                messages.append(AppLocalization.string("1 fixed commitment remains unpaid."))
            } else {
                messages.append(AppLocalization.string("\(commitments.pendingCount) fixed commitments remain unpaid."))
            }
        }
        if commitments.unknownRemainingCount > 0 {
            if commitments.unknownRemainingCount == 1 {
                messages.append(AppLocalization.string("1 pending variable bill has no estimate."))
            } else {
                messages.append(AppLocalization.string("\(commitments.unknownRemainingCount) pending variable bills have no estimate."))
            }
        }

        return Array(messages.prefix(6)).map(ReportInsight.init(message:))
    }

    private static func percentage(_ value: Decimal, of total: Decimal) -> Double {
        guard total > 0 else { return 0 }
        return NSDecimalNumber(decimal: value / total).doubleValue
    }
}
