import Foundation

// Backup file format, version 1.
//
// Explicit DTOs, independent of the SwiftData models: every stored value is
// copied as-is, relationships become IDs, enums keep their stored raw values,
// money is a decimal string ("129.90") and dates are seconds since the Apple
// reference date (2001-01-01 UTC) so they round-trip exactly.
//
// Compatibility policy: `backupVersion` is independent of the SwiftData schema
// version. A future app that changes this format must bump the version and add
// an explicit adapter from every older version it accepts. Files with a newer
// version than the app supports are rejected, never partially read.

nonisolated struct LifeTrackerBackup: Codable, Equatable, Sendable {
    static let formatIdentifier = "LifeTrackerBackup"
    static let currentVersion = 1

    var format: String
    var backupVersion: Int
    /// ISO 8601, for people reading the file.
    var createdAt: String
    var appSchemaVersion: String
    var appVersion: String
    var preferences: BackupPreferences
    var data: BackupDataset
}

/// Settings stored outside SwiftData. Permissions, caches and device
/// identifiers are never included.
nonisolated struct BackupPreferences: Codable, Equatable, Sendable {
    var appLanguage: String?
}

nonisolated struct BackupDataset: Codable, Equatable, Sendable {
    var transactions: [BackupTransaction]
    var transactionCategories: [BackupTransactionCategory]
    var categoryBudgets: [BackupCategoryBudget]
    var financeSettings: [BackupFinanceSettings]
    var recurringTransactions: [BackupRecurringTransaction]
    var creditCards: [BackupCreditCard]
    var creditCardInvoices: [BackupCreditCardInvoice]
    var fixedBills: [BackupFixedBill]
    var fixedBillOccurrences: [BackupFixedBillOccurrence]
    var habits: [BackupHabit]
    var habitScheduleVersions: [BackupHabitScheduleVersion]
    var habitCompletions: [BackupHabitCompletion]

    static let empty = BackupDataset(
        transactions: [], transactionCategories: [], categoryBudgets: [], financeSettings: [],
        recurringTransactions: [], creditCards: [], creditCardInvoices: [], fixedBills: [],
        fixedBillOccurrences: [], habits: [], habitScheduleVersions: [], habitCompletions: []
    )

    /// Same records in a stable order, so two datasets compare by content.
    var canonical: BackupDataset {
        BackupDataset(
            transactions: transactions.sorted { $0.id.uuidString < $1.id.uuidString },
            transactionCategories: transactionCategories.sorted { $0.id.uuidString < $1.id.uuidString },
            categoryBudgets: categoryBudgets.sorted { $0.id.uuidString < $1.id.uuidString },
            financeSettings: financeSettings.sorted { $0.id.uuidString < $1.id.uuidString },
            recurringTransactions: recurringTransactions.sorted { $0.id.uuidString < $1.id.uuidString },
            creditCards: creditCards.sorted { $0.id.uuidString < $1.id.uuidString },
            creditCardInvoices: creditCardInvoices.sorted { $0.id.uuidString < $1.id.uuidString },
            fixedBills: fixedBills.sorted { $0.id.uuidString < $1.id.uuidString },
            fixedBillOccurrences: fixedBillOccurrences.sorted { $0.id.uuidString < $1.id.uuidString },
            habits: habits.sorted { $0.id.uuidString < $1.id.uuidString },
            habitScheduleVersions: habitScheduleVersions.sorted { $0.id.uuidString < $1.id.uuidString },
            habitCompletions: habitCompletions.sorted { $0.id.uuidString < $1.id.uuidString }
        )
    }

    var counts: BackupCounts {
        BackupCounts(
            transactions: transactions.count,
            categories: transactionCategories.count,
            categoryBudgets: categoryBudgets.count,
            financeSettings: financeSettings.count,
            recurringTransactions: recurringTransactions.count,
            creditCards: creditCards.count,
            creditCardInvoices: creditCardInvoices.count,
            fixedBills: fixedBills.count,
            fixedBillOccurrences: fixedBillOccurrences.count,
            habits: habits.count,
            habitScheduleVersions: habitScheduleVersions.count,
            habitCompletions: habitCompletions.count
        )
    }
}

nonisolated struct BackupCounts: Equatable, Sendable {
    var transactions: Int
    var categories: Int
    var categoryBudgets: Int
    var financeSettings: Int
    var recurringTransactions: Int
    var creditCards: Int
    var creditCardInvoices: Int
    var fixedBills: Int
    var fixedBillOccurrences: Int
    var habits: Int
    var habitScheduleVersions: Int
    var habitCompletions: Int

    var total: Int {
        transactions + categories + categoryBudgets + financeSettings + recurringTransactions + creditCards
            + creditCardInvoices + fixedBills + fixedBillOccurrences + habits + habitScheduleVersions + habitCompletions
    }
}

/// Exact decimal money, encoded as a locale-independent string.
nonisolated struct BackupDecimal: Codable, Equatable, Sendable {
    var value: Decimal

    init(_ value: Decimal) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
              !value.isNaN,
              text.range(of: #"^-?\d+(\.\d+)?$"#, options: .regularExpression) != nil else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid decimal \(text)"))
        }
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(NSDecimalNumber(decimal: value).description(withLocale: Locale(identifier: "en_US_POSIX")))
    }
}

nonisolated struct BackupTransaction: Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    var amount: BackupDecimal
    var date: Date
    var type: String
    var categoryID: UUID?
    var notes: String
    var sourceRecurringTransactionID: UUID?
    var recurringOccurrenceID: String?
    var paymentMethodRawValue: String?
    var creditCardID: UUID?
    var creditCardInvoiceID: UUID?
    var installmentNumber: Int?
    var totalInstallments: Int?
    var sourcePurchaseID: UUID?
    var sourceFixedBillOccurrenceID: UUID?
    var financialCycleOverrideStartDate: Date?
}

nonisolated struct BackupTransactionCategory: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var iconName: String
    var colorName: String
    var type: String
    var isDefault: Bool
}

nonisolated struct BackupCategoryBudget: Codable, Equatable, Sendable {
    var id: UUID
    var categoryID: UUID
    var monthlyLimit: BackupDecimal
}

nonisolated struct BackupFinanceSettings: Codable, Equatable, Sendable {
    var id: UUID
    var monthlySpendingBudget: BackupDecimal
}

nonisolated struct BackupRecurringTransaction: Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    var amount: BackupDecimal
    var type: String
    var categoryID: UUID
    var notes: String
    var startDate: Date
    var frequency: String
    var dayOfMonth: Int
    var isActive: Bool
    var lastGeneratedDate: Date?
    var paymentMethodRawValue: String?
    var creditCardID: UUID?
}

nonisolated struct BackupCreditCard: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var lastFourDigits: String
    var closingDay: Int
    var dueDay: Int
    var creditLimit: BackupDecimal
    var isActive: Bool
    var colorName: String
}

nonisolated struct BackupCreditCardInvoice: Codable, Equatable, Sendable {
    var id: UUID
    var invoiceIdentifier: String
    var creditCardID: UUID
    var referenceMonth: Date
    var closingDate: Date
    var dueDate: Date
    var status: String
    var paidDate: Date?
}

nonisolated struct BackupFixedBill: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var categoryID: UUID
    var dueDay: Int
    var estimatedAmount: BackupDecimal?
    var amountMode: String
    var defaultPaymentMethodRawValue: String
    var startDate: Date
    var isActive: Bool
    var notes: String
    var createdAt: Date
}

nonisolated struct BackupFixedBillOccurrence: Codable, Equatable, Sendable {
    var id: UUID
    var occurrenceIdentifier: String
    var fixedBillID: UUID
    var dueDate: Date
    var financialCycleIdentifier: String
    var status: String
    var actualAmount: BackupDecimal?
    var paidDate: Date?
    var paymentMethodRawValue: String?
    var generatedTransactionID: UUID?
}

nonisolated struct BackupHabit: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var notes: String
    var iconName: String
    var colorName: String
    var createdAt: Date
    var startDate: Date
    var isArchived: Bool
    var archivedAt: Date?
    var sortOrder: Int
    var scheduleTypeRawValue: String
    var weekdaysRawValue: String
}

nonisolated struct BackupHabitScheduleVersion: Codable, Equatable, Sendable {
    var id: UUID
    var habitID: UUID
    var effectiveFrom: Date
    var scheduleTypeRawValue: String
    var weekdaysRawValue: String
}

nonisolated struct BackupHabitCompletion: Codable, Equatable, Sendable {
    var id: UUID
    var completionKey: String
    var habitID: UUID
    var day: Date
    var createdAt: Date
}

nonisolated enum BackupCoding {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Exact: the stored value of every SwiftData date.
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSinceReferenceDate)
        }
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let seconds = try container.decode(Double.self)
            guard seconds.isFinite else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid date"))
            }
            return Date(timeIntervalSinceReferenceDate: seconds)
        }
        return decoder
    }
}
