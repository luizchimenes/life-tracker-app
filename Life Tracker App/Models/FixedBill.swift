import Foundation
import SwiftData

enum FixedBillAmountMode: String, Codable, CaseIterable, Identifiable {
    case fixed
    case variable

    var id: Self { self }

    var displayName: LocalizedStringResource {
        switch self {
        case .fixed:
            "Fixed"
        case .variable:
            "Variable"
        }
    }
}

@Model
final class FixedBill {
    @Attribute(.unique) var id: UUID
    var name: String
    var category: TransactionCategory
    var dueDay: Int
    var estimatedAmount: Decimal?
    var amountMode: FixedBillAmountMode
    var defaultPaymentMethodRawValue: String
    var startDate: Date
    var isActive: Bool
    var notes: String
    var createdAt: Date

    var defaultPaymentMethod: PaymentMethod {
        get {
            PaymentMethod(rawValue: defaultPaymentMethodRawValue) ?? .debit
        }
        set {
            defaultPaymentMethodRawValue = newValue.rawValue
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        category: TransactionCategory,
        dueDay: Int,
        estimatedAmount: Decimal? = nil,
        amountMode: FixedBillAmountMode,
        defaultPaymentMethod: PaymentMethod = .debit,
        startDate: Date,
        isActive: Bool = true,
        notes: String = "",
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.dueDay = min(max(dueDay, 1), 31)
        self.estimatedAmount = estimatedAmount.map { max($0, 0) }
        self.amountMode = amountMode
        defaultPaymentMethodRawValue = defaultPaymentMethod.isDirectPayment
            ? defaultPaymentMethod.rawValue
            : PaymentMethod.debit.rawValue
        self.startDate = startDate
        self.isActive = isActive
        self.notes = notes
        self.createdAt = createdAt
    }
}
