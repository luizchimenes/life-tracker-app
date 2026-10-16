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
