import Foundation

nonisolated enum TransactionSourceKind {
    case manual
    case recurring
    case fixedBill
    case installment

    static func resolve(_ transaction: Transaction) -> Self {
        // A recurring card charge is a one-installment purchase; its recurring
        // origin is what the user manages, so it wins.
        if transaction.sourceRecurringTransactionID != nil { return .recurring }
        if transaction.sourcePurchaseID != nil { return .installment }
        if transaction.sourceFixedBillOccurrenceID != nil { return .fixedBill }
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
