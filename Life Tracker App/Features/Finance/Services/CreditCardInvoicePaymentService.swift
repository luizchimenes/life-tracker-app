import Foundation
import SwiftData

enum CreditCardInvoicePaymentError: LocalizedError {
    case invoiceStillOpen

    var errorDescription: String? {
        switch self {
        case .invoiceStillOpen:
            AppLocalization.string("This invoice is still open. It can be marked as paid after it closes.")
        }
    }
}

@MainActor
enum CreditCardInvoicePaymentService {
    /// Closed, unpaid invoices with charges, oldest due date first.
    /// Paying them only settles the card: their purchases were already
    /// counted as spending when they were made.
    static func payableInvoices(
        _ invoices: [CreditCardInvoice],
        transactions: [Transaction],
        on date: Date = .now,
        calendar: Calendar = .current
    ) -> [CreditCardInvoice] {
        invoices
            .filter {
                $0.effectiveStatus(on: date, calendar: calendar) == .closed
                    && $0.total(in: transactions) > 0
            }
            .sorted { $0.dueDate < $1.dueDate }
    }

    static func markPaid(
        _ invoice: CreditCardInvoice,
        paidDate: Date = .now,
        in modelContext: ModelContext,
        calendar: Calendar = .current
    ) throws {
        guard invoice.effectiveStatus(on: paidDate, calendar: calendar) == .closed else {
            throw CreditCardInvoicePaymentError.invoiceStillOpen
        }

        invoice.status = .paid
        invoice.paidDate = paidDate
        try modelContext.save()
    }
}
