import Foundation

struct TransactionPeriodSummary: Identifiable {
    let cycle: FinancialCycle
    let transactions: [Transaction]
    let income: Decimal
    let expenses: Decimal
    let investments: Decimal

    var id: Date { cycle.start }
    var balance: Decimal { income - expenses }
    var availableAfterInvestments: Decimal { balance - investments }

    init(cycle: FinancialCycle, transactions: [Transaction]) {
        self.cycle = cycle
        self.transactions = transactions.filter {
            cycle.contains($0.effectiveFinancialDate)
        }
        income = self.transactions
            .filter { $0.type == .income }
            .reduce(0) { $0 + $1.amount }
        expenses = self.transactions
            .filter { $0.type == .expense }
            .reduce(0) { $0 + $1.amount }
        investments = self.transactions
            .filter { $0.type == .investment }
            .reduce(0) { $0 + $1.amount }
    }

    /// Each bar spans the calendar month of its cycle start (`unit: .month`),
    /// so a tapped chart date selects the cycle whose start shares its month.
    /// The whole column is the hit target; dates outside every bar return nil.
    static func period(
        atChartDate date: Date,
        in periods: [TransactionPeriodSummary],
        calendar: Calendar = .current
    ) -> TransactionPeriodSummary? {
        let tapped = calendar.dateComponents([.year, .month], from: date)
        return periods.first {
            calendar.dateComponents([.year, .month], from: $0.cycle.start) == tapped
        }
    }

    static func recentCycles(
        transactions: [Transaction],
        count: Int = 6,
        date: Date = .now,
        calendar: Calendar = .current
    ) -> [TransactionPeriodSummary] {
        guard let current = FinancialCycle(containing: date, calendar: calendar) else {
            return []
        }
        return (0..<count).reversed().compactMap { offset in
            current.shifted(byMonths: -offset, calendar: calendar).map {
                TransactionPeriodSummary(cycle: $0, transactions: transactions)
            }
        }
    }
}
