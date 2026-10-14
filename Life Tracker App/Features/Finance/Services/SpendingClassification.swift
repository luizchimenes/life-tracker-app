enum SpendingClassification {
    case fixedOrRecurring
    case variable

    static func classify(_ transaction: Transaction) -> Self {
        if transaction.sourceRecurringTransactionID != nil
            || transaction.sourceFixedBillOccurrenceID != nil {
            return .fixedOrRecurring
        }

        return .variable
    }
}
