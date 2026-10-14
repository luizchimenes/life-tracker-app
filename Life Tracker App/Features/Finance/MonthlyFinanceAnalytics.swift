import Foundation

struct CategorySpendingData: Identifiable {
    let id: String
    let categoryID: UUID?
    let name: String
    let iconName: String
    let colorName: String
    let amount: Decimal
    let pendingAmount: Decimal
    let budgetLimit: Decimal?

    var projectedAmount: Decimal {
        amount + pendingAmount
    }

    func percentage(of total: Decimal) -> Double {
        guard total > 0 else {
            return 0
        }

        return NSDecimalNumber(decimal: amount / total).doubleValue
    }
}

struct DailySpendingData: Identifiable {
    let date: Date
    let amount: Decimal

    var id: Date { date }
}

struct MonthlyFinanceAnalytics {
    let projection: MonthlyFinanceProjection
    let monthlyBudget: Decimal?
    let categorySpending: [CategorySpendingData]
    let projectedCategorySpending: [CategorySpendingData]
    let dailySpending: [DailySpendingData]
    let fixedOrRecurringExpenses: Decimal
    let variableExpenses: Decimal

    var topCategories: [CategorySpendingData] {
        Array(categorySpending.prefix(3))
    }

    init(
        transactions: [Transaction],
        recurringTransactions: [RecurringTransaction],
        fixedBillOccurrences: [FixedBillOccurrence] = [],
        categoryBudgets: [CategoryBudget],
        monthlyBudget: Decimal?,
        date: Date = .now,
        calendar: Calendar = .current
    ) {
        let projection = MonthlyFinanceProjection(
            transactions: transactions,
            recurringTransactions: recurringTransactions,
            fixedBillOccurrences: fixedBillOccurrences,
            date: date,
            calendar: calendar
        )
        self.projection = projection
        self.monthlyBudget = monthlyBudget

        let expenseTransactions = projection.actual.transactions.filter {
            $0.type == .expense
        }
        fixedOrRecurringExpenses = expenseTransactions
            .filter {
                SpendingClassification.classify($0) == .fixedOrRecurring
            }
            .reduce(Decimal.zero) { $0 + $1.amount }
        variableExpenses = expenseTransactions
            .filter { SpendingClassification.classify($0) == .variable }
            .reduce(Decimal.zero) { $0 + $1.amount }
        var budgetsByCategoryID: [UUID: Decimal] = [:]

        for budget in categoryBudgets where budget.monthlyLimit > 0 {
            budgetsByCategoryID[budget.category.id] = budget.monthlyLimit
        }

        var categoryTotals: [String: Decimal] = [:]
        var categoryDetails: [
            String: (
                categoryID: UUID?,
                name: String,
                iconName: String,
                colorName: String
            )
        ] = [:]
        var dailyTotals: [Date: Decimal] = [:]

        for transaction in expenseTransactions {
            let key = transaction.category?.id.uuidString ?? "uncategorized"
            categoryTotals[key, default: 0] += transaction.amount
            categoryDetails[key] = (
                categoryID: transaction.category?.id,
                name: transaction.category?.displayName()
                    ?? String(localized: "Uncategorized", locale: AppLocalization.selectedLocale),
                iconName: transaction.category?.iconName
                    ?? "questionmark.circle.fill",
                colorName: transaction.category?.colorName ?? "gray"
            )

            let day = calendar.startOfDay(
                for: transaction.effectiveFinancialDate
            )
            dailyTotals[day, default: 0] += transaction.amount
        }

        var categoriesByID: [UUID: TransactionCategory] = [:]
        for transaction in expenseTransactions {
            if let category = transaction.category {
                categoriesByID[category.id] = category
            }
        }
        for occurrence in projection.upcomingOccurrences where occurrence.type == .expense {
            categoriesByID[occurrence.category.id] = occurrence.category
        }
        for occurrence in projection.pendingFixedBillOccurrences {
            let category = occurrence.fixedBill.category
            categoriesByID[category.id] = category
        }

        let actualCategorySpending: [CategorySpendingData] = categoryTotals.compactMap { element in
            let (key, amount) = element
            guard let details = categoryDetails[key] else {
                return nil
            }

            let pendingAmount: Decimal
            let budgetLimit: Decimal?

            if let categoryID = details.categoryID,
               let category = categoriesByID[categoryID] {
                pendingAmount = projection.pendingRecurringExpenses(
                    for: category
                ) + projection.pendingFixedBillExpenses(for: category)
                budgetLimit = budgetsByCategoryID[categoryID]
            } else {
                pendingAmount = 0
                budgetLimit = nil
            }

            return CategorySpendingData(
                id: key,
                categoryID: details.categoryID,
                name: details.name,
                iconName: details.iconName,
                colorName: details.colorName,
                amount: amount,
                pendingAmount: pendingAmount,
                budgetLimit: budgetLimit
            )
        }
        .sorted { $0.amount > $1.amount }
        categorySpending = actualCategorySpending

        let actualCategoryIDs: Set<UUID> = Set(
            actualCategorySpending.compactMap { $0.categoryID }
        )
        let projectedOnlyCategories: [CategorySpendingData] = categoriesByID.values.compactMap { category -> CategorySpendingData? in
            guard !actualCategoryIDs.contains(category.id) else { return nil }
            let pendingAmount = projection.pendingRecurringExpenses(for: category)
                + projection.pendingFixedBillExpenses(for: category)
            guard pendingAmount > 0 else { return nil }
            return CategorySpendingData(
                id: category.id.uuidString,
                categoryID: category.id,
                name: category.displayName(),
                iconName: category.iconName,
                colorName: category.colorName,
                amount: 0,
                pendingAmount: pendingAmount,
                budgetLimit: budgetsByCategoryID[category.id]
            )
        }
        projectedCategorySpending = (actualCategorySpending + projectedOnlyCategories)
            .filter { $0.projectedAmount > 0 }
            .sorted { $0.projectedAmount > $1.projectedAmount }

        dailySpending = dailyTotals.map {
            DailySpendingData(date: $0.key, amount: $0.value)
        }
        .sorted { $0.date < $1.date }
    }
}
