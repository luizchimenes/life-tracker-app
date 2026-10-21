import Foundation
import SwiftData

@MainActor
enum CreditCardPurchaseService {
    static func createPurchase(
        title: String,
        totalAmount: Decimal,
        purchaseDate: Date,
        category: TransactionCategory,
        notes: String,
        creditCard: CreditCard,
        installmentCount: Int,
        sourceRecurringTransactionID: UUID? = nil,
        recurringOccurrenceID: String? = nil,
        financialCycleOverrideStart: Date? = nil,
        in modelContext: ModelContext,
        calendar: Calendar = .current
    ) throws {
        let count = min(max(installmentCount, 1), 36)
        let sourcePurchaseID = UUID()
        let amounts = installmentAmounts(
            total: abs(totalAmount),
            count: count
        )

        for index in 0..<count {
            let invoice = try CreditCardInvoiceResolver.invoice(
                for: purchaseDate,
                creditCard: creditCard,
                installmentOffset: index,
                in: modelContext,
                calendar: calendar
            )

            modelContext.insert(
                Transaction(
                    title: title,
                    amount: amounts[index],
                    date: purchaseDate,
                    type: .expense,
                    category: category,
                    notes: notes,
                    sourceRecurringTransactionID: sourceRecurringTransactionID,
                    recurringOccurrenceID: recurringOccurrenceID,
                    paymentMethod: .creditCard,
                    creditCard: creditCard,
                    creditCardInvoice: invoice,
                    installmentNumber: index + 1,
                    totalInstallments: count,
                    sourcePurchaseID: sourcePurchaseID,
                    // A manual choice moves installment 1; the rest follow one cycle apart.
                    financialCycleOverrideStartDate: FinancialCycleAllocation.overrideStart(
                        forInstallmentAt: index,
                        firstStart: financialCycleOverrideStart,
                        calendar: calendar
                    )
                )
            )
        }

        try modelContext.save()
    }

    static func installmentAmounts(
        total: Decimal,
        count: Int
    ) -> [Decimal] {
        let safeCount = max(count, 1)
        var divided = total / Decimal(safeCount)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &divided, 2, .bankers)

        var amounts = Array(
            repeating: rounded,
            count: safeCount
        )
        amounts[safeCount - 1] =
            total - rounded * Decimal(safeCount - 1)
        return amounts
    }
}
