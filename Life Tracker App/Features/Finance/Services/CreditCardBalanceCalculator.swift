import Foundation

enum CreditCardBalanceCalculator {
    static func outstandingAmount(
        for creditCard: CreditCard,
        invoices: [CreditCardInvoice],
        transactions: [Transaction],
        on date: Date = .now,
        calendar: Calendar = .current
    ) -> Decimal {
        let unpaidInvoiceIDs = Set(
            invoices.lazy
                .filter {
                    $0.creditCard.id == creditCard.id
                        && $0.effectiveStatus(on: date, calendar: calendar) != .paid
                }
                .map(\.id)
        )

        return transactions.lazy
            .filter {
                $0.type == .expense
                    && $0.paymentMethod == .creditCard
                    && $0.creditCard?.id == creditCard.id
                    && $0.creditCardInvoice.map {
                        unpaidInvoiceIDs.contains($0.id)
                    } == true
            }
            .reduce(Decimal.zero) { $0 + $1.amount }
    }

    static func availableLimit(
        for creditCard: CreditCard,
        invoices: [CreditCardInvoice],
        transactions: [Transaction],
        on date: Date = .now,
        calendar: Calendar = .current
    ) -> Decimal {
        max(
            creditCard.creditLimit - outstandingAmount(
                for: creditCard,
                invoices: invoices,
                transactions: transactions,
                on: date,
                calendar: calendar
            ),
            0
        )
    }
}
