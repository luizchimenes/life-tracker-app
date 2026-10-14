import Foundation
import SwiftData

@Model
final class FinanceSettings {
    @Attribute(.unique) var id: UUID
    var monthlySpendingBudget: Decimal

    init(
        id: UUID = UUID(),
        monthlySpendingBudget: Decimal
    ) {
        self.id = id
        self.monthlySpendingBudget = monthlySpendingBudget
    }
}
