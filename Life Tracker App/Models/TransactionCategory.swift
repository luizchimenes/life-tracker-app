import Foundation
import SwiftData

enum TransactionCategoryType: String, Codable, CaseIterable, Identifiable {
    case income
    case expense
    case both

    var id: Self { self }

    var displayName: LocalizedStringResource {
        switch self {
        case .income:
            "Income"
        case .expense:
            "Expense"
        case .both:
            "Both"
        }
    }

    func supports(_ transactionType: TransactionType) -> Bool {
        switch (self, transactionType) {
        case (.both, _), (.income, .income), (.expense, .expense):
            true
        default:
            false
        }
    }
}

@Model
final class TransactionCategory {
    @Attribute(.unique) var id: UUID
    var name: String
    var iconName: String
    var colorName: String
    var type: TransactionCategoryType
    var isDefault: Bool = false

    init(
        id: UUID = UUID(),
        name: String,
        iconName: String,
        colorName: String,
        type: TransactionCategoryType,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.colorName = colorName
        self.type = type
        self.isDefault = isDefault
    }
}

extension TransactionCategory {
    func displayName(locale: Locale = AppLocalization.selectedLocale) -> String {
        guard isDefault, let resource = defaultNameResource else { return name }
        var localizedResource = resource
        localizedResource.locale = locale
        return String(localized: localizedResource)
    }

    private var defaultNameResource: LocalizedStringResource? {
        switch name {
        case "Food": "Food"
        case "Transport": "Transport"
        case "Housing": "Housing"
        case "Health": "Health"
        case "Entertainment": "Entertainment"
        case "Shopping": "Shopping"
        case "Education": "Education"
        case "Subscriptions": "Subscriptions"
        case "Other": "Other"
        case "Salary": "Salary"
        case "Freelance": "Freelance"
        case "Investments": "Investments"
        case "Refund": "Refund"
        case "Other Income": "Other Income"
        default: nil
        }
    }
}

extension TransactionCategory {
    static func makeDefaults() -> [TransactionCategory] { [
        TransactionCategory(name: "Food", iconName: "fork.knife", colorName: "orange", type: .expense, isDefault: true),
        TransactionCategory(name: "Transport", iconName: "car.fill", colorName: "blue", type: .expense, isDefault: true),
        TransactionCategory(name: "Housing", iconName: "house.fill", colorName: "brown", type: .expense, isDefault: true),
        TransactionCategory(name: "Health", iconName: "heart.fill", colorName: "red", type: .expense, isDefault: true),
        TransactionCategory(name: "Entertainment", iconName: "gamecontroller.fill", colorName: "purple", type: .expense, isDefault: true),
        TransactionCategory(name: "Shopping", iconName: "bag.fill", colorName: "pink", type: .expense, isDefault: true),
        TransactionCategory(name: "Education", iconName: "book.fill", colorName: "indigo", type: .expense, isDefault: true),
        TransactionCategory(name: "Subscriptions", iconName: "repeat", colorName: "teal", type: .expense, isDefault: true),
        TransactionCategory(name: "Other", iconName: "ellipsis.circle.fill", colorName: "gray", type: .expense, isDefault: true),
        TransactionCategory(name: "Salary", iconName: "banknote.fill", colorName: "green", type: .income, isDefault: true),
        TransactionCategory(name: "Freelance", iconName: "laptopcomputer", colorName: "blue", type: .income, isDefault: true),
        TransactionCategory(name: "Investments", iconName: "chart.line.uptrend.xyaxis", colorName: "green", type: .income, isDefault: true),
        TransactionCategory(name: "Refund", iconName: "arrow.uturn.backward.circle.fill", colorName: "orange", type: .income, isDefault: true),
        TransactionCategory(name: "Other Income", iconName: "plus.circle.fill", colorName: "mint", type: .income, isDefault: true)
    ] }

    @MainActor
    static func seedDefaultsIfNeeded(in modelContext: ModelContext) throws {
        let descriptor = FetchDescriptor<TransactionCategory>()

        let existingCategories = try modelContext.fetch(descriptor)

        if existingCategories.isEmpty {
            for category in makeDefaults() {
                modelContext.insert(category)
            }
        } else if !existingCategories.contains(where: \.isDefault) {
            let defaults = makeDefaults()

            for category in existingCategories {
                category.isDefault = defaults.contains {
                    $0.name == category.name && $0.type == category.type
                }
            }
        }

        try modelContext.save()
    }
}
