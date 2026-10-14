import Foundation
import SwiftData

struct CreditCardInvoiceDates {
    let referenceMonth: Date
    let closingDate: Date
    let dueDate: Date
    let identifier: String
}

enum CreditCardInvoiceResolver {
    static func invoiceDates(
        for purchaseDate: Date,
        creditCard: CreditCard,
        installmentOffset: Int = 0,
        calendar: Calendar = .current
    ) -> CreditCardInvoiceDates? {
        guard let purchaseMonth = startOfMonth(
            containing: purchaseDate,
            calendar: calendar
        ),
        let candidateClosingDate = date(
            inMonth: purchaseMonth,
            day: creditCard.closingDay,
            calendar: calendar
        ) else {
            return nil
        }

        let purchaseDay = calendar.startOfDay(for: purchaseDate)
        let baseClosingMonth: Date

        // Purchases made on the closing day already belong to the next invoice.
        if purchaseDay < candidateClosingDate {
            baseClosingMonth = purchaseMonth
        } else {
            guard let nextMonth = calendar.date(
                byAdding: .month,
                value: 1,
                to: purchaseMonth
            ) else {
                return nil
            }
            baseClosingMonth = nextMonth
        }

        guard let closingMonth = calendar.date(
            byAdding: .month,
            value: installmentOffset,
            to: baseClosingMonth
        ),
        let closingDate = date(
            inMonth: closingMonth,
            day: creditCard.closingDay,
            calendar: calendar
        ) else {
            return nil
        }

        let dueMonthOffset = creditCard.dueDay > creditCard.closingDay ? 0 : 1

        guard let dueMonth = calendar.date(
            byAdding: .month,
            value: dueMonthOffset,
            to: closingMonth
        ),
        let dueDate = date(
            inMonth: dueMonth,
            day: creditCard.dueDay,
            calendar: calendar
        ),
        let referenceMonth = startOfMonth(
            containing: dueDate,
            calendar: calendar
        ) else {
            return nil
        }

        let components = calendar.dateComponents(
            [.year, .month],
            from: referenceMonth
        )
        let identifier = [
            creditCard.id.uuidString,
            String(components.year ?? 0),
            String(components.month ?? 0)
        ].joined(separator: "-")

        return CreditCardInvoiceDates(
            referenceMonth: referenceMonth,
            closingDate: closingDate,
            dueDate: dueDate,
            identifier: identifier
        )
    }

    @MainActor
    static func invoice(
        for purchaseDate: Date,
        creditCard: CreditCard,
        installmentOffset: Int = 0,
        in modelContext: ModelContext,
        calendar: Calendar = .current
    ) throws -> CreditCardInvoice {
        guard let dates = invoiceDates(
            for: purchaseDate,
            creditCard: creditCard,
            installmentOffset: installmentOffset,
            calendar: calendar
        ) else {
            throw CreditCardInvoiceError.invalidDates
        }

        let existingInvoices = try modelContext.fetch(
            FetchDescriptor<CreditCardInvoice>()
        )

        if let existing = existingInvoices.first(
            where: { $0.invoiceIdentifier == dates.identifier }
        ) {
            return existing
        }

        let status: CreditCardInvoiceStatus =
            calendar.startOfDay(for: .now) > dates.closingDate ? .closed : .open
        let invoice = CreditCardInvoice(
            invoiceIdentifier: dates.identifier,
            creditCard: creditCard,
            referenceMonth: dates.referenceMonth,
            closingDate: dates.closingDate,
            dueDate: dates.dueDate,
            status: status
        )
        modelContext.insert(invoice)
        return invoice
    }

    private static func startOfMonth(
        containing date: Date,
        calendar: Calendar
    ) -> Date? {
        calendar.date(
            from: calendar.dateComponents([.year, .month], from: date)
        )
    }

    private static func date(
        inMonth month: Date,
        day: Int,
        calendar: Calendar
    ) -> Date? {
        guard let range = calendar.range(
            of: .day,
            in: .month,
            for: month
        ) else {
            return nil
        }

        var components = calendar.dateComponents([.year, .month], from: month)
        components.day = min(max(day, 1), range.count)

        guard let date = calendar.date(from: components) else {
            return nil
        }

        return calendar.startOfDay(for: date)
    }
}

enum CreditCardInvoiceError: Error {
    case invalidDates
}
