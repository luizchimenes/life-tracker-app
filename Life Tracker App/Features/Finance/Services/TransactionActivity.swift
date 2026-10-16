import Foundation

@MainActor
enum TransactionActivity {
    static func recent(
        from transactions: [Transaction],
        limit: Int
    ) -> [Transaction] {
        Array(
            purchaseRepresentatives(from: transactions)
                .sorted(by: transactionDateDescending)
                .prefix(limit)
        )
    }

    static func purchaseRepresentatives(
        from transactions: [Transaction]
    ) -> [Transaction] {
        var standalone: [Transaction] = []
        var installmentPurchases: [UUID: Transaction] = [:]

        for transaction in transactions {
            guard let purchaseID = transaction.sourcePurchaseID else {
                standalone.append(transaction)
                continue
            }

            if let current = installmentPurchases[purchaseID] {
                let currentNumber = current.installmentNumber ?? Int.max
                let candidateNumber = transaction.installmentNumber ?? Int.max
                if candidateNumber < currentNumber {
                    installmentPurchases[purchaseID] = transaction
                }
            } else {
                installmentPurchases[purchaseID] = transaction
            }
        }

        return standalone + installmentPurchases.values
    }

    static func belongs(
        _ transaction: Transaction,
        to cycle: FinancialCycle
    ) -> Bool {
        cycle.contains(transaction.effectiveFinancialDate)
    }

    static func transactionDateDescending(
        _ lhs: Transaction,
        _ rhs: Transaction
    ) -> Bool {
        if lhs.date == rhs.date {
            return lhs.id.uuidString > rhs.id.uuidString
        }
        return lhs.date > rhs.date
    }
}

enum TransactionAmountPresentation {
    static func sign(for type: TransactionType) -> String {
        switch type {
        case .income: "+"
        case .expense: "−"
        case .investment: ""
        }
    }
}
