import Foundation
import SwiftData

enum FixedBillOccurrenceStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case paid
    case skipped

    var id: Self { self }

    var displayName: LocalizedStringResource {
        switch self {
        case .pending:
            "Pending"
        case .paid:
            "Paid"
        case .skipped:
            "Skipped"
        }
    }
}

@Model
final class FixedBillOccurrence {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var occurrenceIdentifier: String
    var fixedBill: FixedBill
    var dueDate: Date
    var financialCycleIdentifier: String
    var status: FixedBillOccurrenceStatus
    var actualAmount: Decimal?
    var paidDate: Date?
    var paymentMethodRawValue: String?
    var generatedTransactionID: UUID?

    var paymentMethod: PaymentMethod? {
        get {
            paymentMethodRawValue.flatMap(PaymentMethod.init(rawValue:))
        }
        set {
            paymentMethodRawValue = newValue?.rawValue
        }
    }

    init(
        id: UUID = UUID(),
        occurrenceIdentifier: String,
        fixedBill: FixedBill,
        dueDate: Date,
        financialCycleIdentifier: String,
        status: FixedBillOccurrenceStatus = .pending,
        actualAmount: Decimal? = nil,
        paidDate: Date? = nil,
        paymentMethod: PaymentMethod? = nil,
        generatedTransactionID: UUID? = nil
    ) {
        self.id = id
        self.occurrenceIdentifier = occurrenceIdentifier
        self.fixedBill = fixedBill
        self.dueDate = dueDate
        self.financialCycleIdentifier = financialCycleIdentifier
        self.status = status
        self.actualAmount = actualAmount
        self.paidDate = paidDate
        paymentMethodRawValue = paymentMethod?.rawValue
        self.generatedTransactionID = generatedTransactionID
    }

    func isOverdue(
        on date: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        status == .pending
            && calendar.startOfDay(for: date) > calendar.startOfDay(for: dueDate)
    }
}
