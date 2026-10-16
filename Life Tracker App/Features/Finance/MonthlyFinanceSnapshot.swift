import Foundation

struct MonthlyFinanceSnapshot {
    let transactions: [Transaction]
    let income: Decimal
    let expenses: Decimal
    let investments: Decimal
    let cycle: FinancialCycle?

    var balance: Decimal {
        income - expenses
    }

    var availableAfterInvestments: Decimal {
        balance - investments
    }

    init(
        transactions: [Transaction],
        date: Date = .now,
        calendar: Calendar = .current
    ) {
        guard let cycle = FinancialCycle(
            containing: date,
            calendar: calendar
        ) else {
            self.transactions = []
            income = 0
            expenses = 0
            investments = 0
            self.cycle = nil
            return
        }

        let monthlyTransactions = transactions.filter {
            cycle.contains($0.effectiveFinancialDate)
        }

        self.transactions = monthlyTransactions
        self.cycle = cycle
        income = monthlyTransactions
            .filter { $0.type == .income }
            .reduce(Decimal.zero) { $0 + $1.amount }
        expenses = monthlyTransactions
            .filter { $0.type == .expense }
            .reduce(Decimal.zero) { $0 + $1.amount }
        investments = monthlyTransactions
            .filter { $0.type == .investment }
            .reduce(Decimal.zero) { $0 + $1.amount }
    }

    func expenses(for category: TransactionCategory) -> Decimal {
        transactions
            .filter {
                $0.type == .expense && $0.category?.id == category.id
            }
            .reduce(Decimal.zero) { $0 + $1.amount }
    }
}
