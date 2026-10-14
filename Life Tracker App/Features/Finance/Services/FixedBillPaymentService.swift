import Foundation
import SwiftData

enum FixedBillPaymentError: LocalizedError {
    case alreadyPaid
    case invalidAmount
    case unsupportedPaymentMethod

    var errorDescription: String? {
        switch self {
        case .alreadyPaid:
            AppLocalization.string("This bill occurrence has already been paid.")
        case .invalidAmount:
            AppLocalization.string("Enter an amount greater than zero.")
        case .unsupportedPaymentMethod:
            AppLocalization.string("Credit-card payment is not supported for fixed bills yet.")
        }
    }
}

@MainActor
enum FixedBillPaymentService {
    static func skip(
        occurrence: FixedBillOccurrence,
        in modelContext: ModelContext
    ) throws {
        guard occurrence.status != .paid,
              occurrence.generatedTransactionID == nil else {
            throw FixedBillPaymentError.alreadyPaid
        }
        occurrence.status = .skipped
        occurrence.actualAmount = nil
        occurrence.paidDate = nil
        occurrence.paymentMethod = nil
        try modelContext.save()
    }

    static func restoreSkippedToPending(
        occurrence: FixedBillOccurrence,
        in modelContext: ModelContext
    ) throws {
        guard occurrence.status == .skipped else { return }
        occurrence.status = .pending
        try modelContext.save()
    }

    static func markPaid(
        occurrence: FixedBillOccurrence,
        actualAmount: Decimal,
        paidDate: Date,
        paymentMethod: PaymentMethod,
        category: TransactionCategory,
        note: String,
        in modelContext: ModelContext
    ) throws {
        guard occurrence.status != .paid,
              occurrence.generatedTransactionID == nil else {
            throw FixedBillPaymentError.alreadyPaid
        }
        guard actualAmount > 0 else {
            throw FixedBillPaymentError.invalidAmount
        }
        guard paymentMethod.isDirectPayment else {
            throw FixedBillPaymentError.unsupportedPaymentMethod
        }

        let existingTransactions = try modelContext.fetch(
            FetchDescriptor<Transaction>()
        )
        guard !existingTransactions.contains(where: {
            $0.sourceFixedBillOccurrenceID == occurrence.id
        }) else {
            throw FixedBillPaymentError.alreadyPaid
        }

        let transaction = Transaction(
            title: occurrence.fixedBill.name,
            amount: actualAmount,
            date: paidDate,
            type: .expense,
            category: category,
            notes: note,
            paymentMethod: paymentMethod,
            sourceFixedBillOccurrenceID: occurrence.id
        )
        modelContext.insert(transaction)

        occurrence.status = .paid
        occurrence.actualAmount = actualAmount
        occurrence.paidDate = paidDate
        occurrence.paymentMethod = paymentMethod
        occurrence.generatedTransactionID = transaction.id

        try modelContext.save()
    }

    static func revertToPending(
        occurrence: FixedBillOccurrence,
        in modelContext: ModelContext
    ) throws {
        let occurrenceID = occurrence.id
        let transactions = try modelContext.fetch(
            FetchDescriptor<Transaction>()
        )

        for transaction in transactions
        where transaction.sourceFixedBillOccurrenceID == occurrenceID {
            modelContext.delete(transaction)
        }

        occurrence.status = .pending
        occurrence.actualAmount = nil
        occurrence.paidDate = nil
        occurrence.paymentMethod = nil
        occurrence.generatedTransactionID = nil

        try modelContext.save()
    }
}
