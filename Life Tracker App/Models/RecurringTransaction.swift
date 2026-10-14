import Foundation
import SwiftData

enum RecurringFrequency: String, Codable, CaseIterable, Identifiable {
    case monthly

    var id: Self { self }

    var displayName: LocalizedStringResource {
        switch self {
        case .monthly:
            "Monthly"
        }
    }
}

@Model
final class RecurringTransaction {
    @Attribute(.unique) var id: UUID
    var title: String
    var amount: Decimal
    var type: TransactionType
    var category: TransactionCategory
    var notes: String
    var startDate: Date
    var frequency: RecurringFrequency
    var dayOfMonth: Int
    var isActive: Bool
    var lastGeneratedDate: Date?

    init(
        id: UUID = UUID(),
        title: String,
        amount: Decimal,
        type: TransactionType,
        category: TransactionCategory,
        notes: String = "",
        startDate: Date,
        frequency: RecurringFrequency = .monthly,
        dayOfMonth: Int,
        isActive: Bool = true,
        lastGeneratedDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.type = type
        self.category = category
        self.notes = notes
        self.startDate = startDate
        self.frequency = frequency
        self.dayOfMonth = min(max(dayOfMonth, 1), 31)
        self.isActive = isActive
        self.lastGeneratedDate = lastGeneratedDate
    }
}
