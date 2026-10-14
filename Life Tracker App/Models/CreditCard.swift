import Foundation
import SwiftData

@Model
final class CreditCard {
    @Attribute(.unique) var id: UUID
    var name: String
    var lastFourDigits: String
    var closingDay: Int
    var dueDay: Int
    var creditLimit: Decimal
    var isActive: Bool
    var colorName: String

    init(
        id: UUID = UUID(),
        name: String,
        lastFourDigits: String,
        closingDay: Int,
        dueDay: Int,
        creditLimit: Decimal,
        isActive: Bool = true,
        colorName: String = "blue"
    ) {
        self.id = id
        self.name = name
        self.lastFourDigits = String(lastFourDigits.suffix(4))
        self.closingDay = min(max(closingDay, 1), 31)
        self.dueDay = min(max(dueDay, 1), 31)
        self.creditLimit = max(creditLimit, 0)
        self.isActive = isActive
        self.colorName = colorName
    }
}
