import Foundation
import SwiftData

enum CreditCardInvoiceStatus: String, Codable, CaseIterable, Identifiable {
    case open
    case closed
    case paid

    var id: Self { self }

    var displayName: LocalizedStringResource {
        switch self {
        case .open:
            "Open"
        case .closed:
            "Closed"
        case .paid:
            "Paid"
        }
    }
}

@Model
final class CreditCardInvoice {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var invoiceIdentifier: String
    var creditCard: CreditCard
    var referenceMonth: Date
    var closingDate: Date
    var dueDate: Date
    var status: CreditCardInvoiceStatus
    var paidDate: Date?

    init(
        id: UUID = UUID(),
        invoiceIdentifier: String,
        creditCard: CreditCard,
        referenceMonth: Date,
        closingDate: Date,
        dueDate: Date,
        status: CreditCardInvoiceStatus = .open,
        paidDate: Date? = nil
    ) {
        self.id = id
        self.invoiceIdentifier = invoiceIdentifier
        self.creditCard = creditCard
        self.referenceMonth = referenceMonth
        self.closingDate = closingDate
        self.dueDate = dueDate
        self.status = status
        self.paidDate = paidDate
    }

    func effectiveStatus(
        on date: Date = .now,
        calendar: Calendar = .current
    ) -> CreditCardInvoiceStatus {
        if status == .paid || paidDate != nil {
            return .paid
        }

        // The invoice closes at the start of its closing day, so it can be
        // paid that same day; purchases from that day go to the next invoice.
        return calendar.startOfDay(for: date) >= calendar.startOfDay(for: closingDate)
            ? .closed
            : .open
    }

    func total(in transactions: [Transaction]) -> Decimal {
        transactions
            .filter { $0.creditCardInvoice?.id == id }
            .reduce(Decimal.zero) { $0 + $1.amount }
    }

    func isOverdue(
        on date: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        effectiveStatus(on: date, calendar: calendar) == .closed
            && calendar.startOfDay(for: date) > calendar.startOfDay(for: dueDate)
    }
}
