import Foundation
import SwiftData

@Model
final class CategoryBudget {
    @Attribute(.unique) var id: UUID
    var category: TransactionCategory
    var monthlyLimit: Decimal

    init(
        id: UUID = UUID(),
        category: TransactionCategory,
        monthlyLimit: Decimal
    ) {
        self.id = id
        self.category = category
        self.monthlyLimit = monthlyLimit
    }
}
