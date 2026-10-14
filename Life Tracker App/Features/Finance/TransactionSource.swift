import Foundation

nonisolated enum TransactionSourceKind {
    case manual
    case recurring
    case fixedBill
    case installment

    static func resolve(_ transaction: Transaction) -> Self {
        if transaction.sourcePurchaseID != nil { return .installment }
        if transaction.sourceFixedBillOccurrenceID != nil { return .fixedBill }
        if transaction.sourceRecurringTransactionID != nil { return .recurring }
        return .manual
    }
}

extension Transaction {
    var sourceKind: TransactionSourceKind {
        TransactionSourceKind.resolve(self)
    }

    var canEditDirectly: Bool {
        sourceKind == .manual && paymentMethod != .creditCard
    }
}
