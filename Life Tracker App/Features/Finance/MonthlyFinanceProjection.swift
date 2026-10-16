import Foundation

struct UpcomingRecurringOccurrence: Identifiable {
    let id: String
    let recurringTransaction: RecurringTransaction
    let date: Date

    var amount: Decimal {
        recurringTransaction.amount
    }

    var type: TransactionType {
        recurringTransaction.type
    }

    var category: TransactionCategory {
        recurringTransaction.category
    }
}

struct MonthlyFinanceProjection {
    let actual: MonthlyFinanceSnapshot
    let upcomingOccurrences: [UpcomingRecurringOccurrence]
    let pendingFixedBillOccurrences: [FixedBillOccurrence]

    var actualIncome: Decimal {
        actual.income
    }

    var actualExpenses: Decimal {
        actual.expenses
    }

    var pendingRecurringIncome: Decimal {
        upcomingOccurrences
            .filter { $0.type == .income }
            .reduce(Decimal.zero) { $0 + $1.amount }
    }

    var pendingRecurringExpenses: Decimal {
        upcomingOccurrences
            .filter { $0.type == .expense }
            .reduce(Decimal.zero) { $0 + $1.amount }
    }

    var pendingFixedBillExpenses: Decimal {
        pendingFixedBillOccurrences
            .compactMap { $0.fixedBill.estimatedAmount }
            .reduce(Decimal.zero, +)
    }

    var projectedIncome: Decimal {
        actualIncome + pendingRecurringIncome
    }

    var projectedExpenses: Decimal {
        actualExpenses + pendingRecurringExpenses + pendingFixedBillExpenses
    }

    /// Income − expenses, projected. Does not subtract investments; see
    /// `projectedAvailableAfterInvestments` for the money left to use.
    var projectedBalance: Decimal {
        projectedIncome - projectedExpenses
    }

    /// Investments have no schedule, so the projection is what was invested.
    var projectedInvestments: Decimal {
        actual.investments
    }

    var projectedAvailableAfterInvestments: Decimal {
        projectedIncome - projectedExpenses - projectedInvestments
    }

    init(
        transactions: [Transaction],
        recurringTransactions: [RecurringTransaction],
        fixedBillOccurrences: [FixedBillOccurrence] = [],
        date: Date = .now,
        calendar: Calendar = .current
    ) {
        actual = MonthlyFinanceSnapshot(
            transactions: transactions,
            date: date,
            calendar: calendar
        )

        guard let cycle = actual.cycle else {
            upcomingOccurrences = []
            pendingFixedBillOccurrences = []
            return
        }

        // Overdue bills from earlier cycles are still owed and, once paid,
        // will be recorded in this cycle, so they belong in its projection.
        pendingFixedBillOccurrences = fixedBillOccurrences.filter {
            $0.status == .pending
                && FixedBillCycleSnapshot.belongsToCurrentList($0, cycle: cycle)
        }

        let todayStart = calendar.startOfDay(for: date)
        let existingOccurrenceIDs = Set(
            transactions.compactMap(\.recurringOccurrenceID)
        )

        var occurrences: [UpcomingRecurringOccurrence] = []
        let cycleMonths = [
            cycle.start,
            calendar.date(byAdding: .month, value: 1, to: cycle.start)
        ].compactMap { $0 }

        for rule in recurringTransactions
        where rule.isActive && rule.frequency == .monthly {
            for month in cycleMonths {
                guard let occurrenceDate = RecurringTransactionGenerator.occurrenceDate(
                    in: month,
                    dayOfMonth: rule.dayOfMonth,
                    calendar: calendar
                ) else {
                    continue
                }

                let occurrenceStart = calendar.startOfDay(for: occurrenceDate)
                let ruleStart = calendar.startOfDay(for: rule.startDate)

                guard occurrenceStart >= ruleStart,
                      occurrenceStart > todayStart,
                      cycle.contains(occurrenceStart) else {
                    continue
                }

                let occurrenceID = RecurringTransactionGenerator.occurrenceIdentifier(
                    ruleID: rule.id,
                    occurrenceDate: occurrenceStart,
                    calendar: calendar
                )

                guard !existingOccurrenceIDs.contains(occurrenceID) else {
                    continue
                }

                occurrences.append(
                    UpcomingRecurringOccurrence(
                        id: occurrenceID,
                        recurringTransaction: rule,
                        date: occurrenceStart
                    )
                )
            }
        }

        upcomingOccurrences = occurrences.sorted { $0.date < $1.date }
    }

    func pendingRecurringExpenses(
        for category: TransactionCategory
    ) -> Decimal {
        upcomingOccurrences
            .filter {
                $0.type == .expense && $0.category.id == category.id
            }
            .reduce(Decimal.zero) { $0 + $1.amount }
    }

    func pendingFixedBillExpenses(
        for category: TransactionCategory
    ) -> Decimal {
        pendingFixedBillOccurrences
            .filter { $0.fixedBill.category.id == category.id }
            .compactMap { $0.fixedBill.estimatedAmount }
            .reduce(Decimal.zero, +)
    }

    func projectedBudgetRemaining(monthlyBudget: Decimal) -> Decimal {
        monthlyBudget - projectedExpenses
    }
}
