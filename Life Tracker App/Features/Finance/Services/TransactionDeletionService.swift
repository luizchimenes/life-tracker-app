import Foundation
import SwiftData

enum TransactionDeletionError: LocalizedError {
    case installmentRequiresWholePurchase

    var errorDescription: String? {
        switch self {
        case .installmentRequiresWholePurchase:
            AppLocalization.string("Installments must be deleted together from the installment purchase overview.")
        }
    }
}

@MainActor
enum TransactionDeletionService {
    static func transactionsForSafeDeletion(
        of transaction: Transaction,
        from allTransactions: [Transaction]
    ) throws -> [Transaction] {
        guard let sourcePurchaseID = transaction.sourcePurchaseID else {
            return [transaction]
        }

        let purchase = allTransactions.filter {
            $0.sourcePurchaseID == sourcePurchaseID
        }
        guard purchase.count == transaction.totalInstallments else {
            throw TransactionDeletionError.installmentRequiresWholePurchase
        }
        return purchase
    }

    static func deletePurchase(
        sourcePurchaseID: UUID,
        from allTransactions: [Transaction],
        in modelContext: ModelContext
    ) throws {
        let purchase = allTransactions.filter {
            $0.sourcePurchaseID == sourcePurchaseID
        }
        try delete(purchase, from: allTransactions, in: modelContext)
    }

    static func delete(
        _ transactionsToDelete: [Transaction],
        from allTransactions: [Transaction],
        in modelContext: ModelContext
    ) throws {
        let deletedTransactionIDs = Set(transactionsToDelete.map(\.id))
        let affectedInvoices = Dictionary(
            transactionsToDelete.compactMap { transaction in
                transaction.creditCardInvoice.map { ($0.id, $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )

        let affectedOccurrenceIDs = Set(
            transactionsToDelete.compactMap(\.sourceFixedBillOccurrenceID)
        )

        if !affectedOccurrenceIDs.isEmpty {
            let occurrences = try modelContext.fetch(
                FetchDescriptor<FixedBillOccurrence>()
            )
            for occurrence in occurrences
            where affectedOccurrenceIDs.contains(occurrence.id) {
                occurrence.status = .pending
                occurrence.actualAmount = nil
                occurrence.paidDate = nil
                occurrence.paymentMethod = nil
                occurrence.generatedTransactionID = nil
            }
        }

        for transaction in transactionsToDelete {
            modelContext.delete(transaction)
        }

        for (invoiceID, invoice) in affectedInvoices {
            let hasRemainingPurchase = allTransactions.contains { transaction in
                !deletedTransactionIDs.contains(transaction.id)
                    && transaction.creditCardInvoice?.id == invoiceID
            }

            if !hasRemainingPurchase {
                modelContext.delete(invoice)
            }
        }

        try modelContext.save()
    }
}
