import Foundation
import SwiftData

/// Frozen copy of the stored shape shipped before V2. Never edit these types:
/// they must match stores already on devices so migration can recognize them.
enum LifeTrackerSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Transaction.self,
            TransactionCategory.self,
            CategoryBudget.self,
            FinanceSettings.self,
            RecurringTransaction.self,
            CreditCard.self,
            CreditCardInvoice.self,
            FixedBill.self,
            FixedBillOccurrence.self
        ]
    }

    @Model
    final class Transaction {
        @Attribute(.unique) var id: UUID
        var title: String
        var amount: Decimal
        var date: Date
        var type: TransactionType
        var category: TransactionCategory?
        var notes: String
        var sourceRecurringTransactionID: UUID?
        @Attribute(.unique) var recurringOccurrenceID: String?
        var paymentMethodRawValue: String?
        var creditCard: CreditCard?
        var creditCardInvoice: CreditCardInvoice?
        var installmentNumber: Int?
        var totalInstallments: Int?
        var sourcePurchaseID: UUID?
        @Attribute(.unique) var sourceFixedBillOccurrenceID: UUID?

        init(
            id: UUID = UUID(),
            title: String,
            amount: Decimal,
            date: Date,
            type: TransactionType,
            category: TransactionCategory?,
            notes: String = "",
            sourceRecurringTransactionID: UUID? = nil,
            recurringOccurrenceID: String? = nil,
            paymentMethodRawValue: String? = nil,
            creditCard: CreditCard? = nil,
            creditCardInvoice: CreditCardInvoice? = nil,
            installmentNumber: Int? = nil,
            totalInstallments: Int? = nil,
            sourcePurchaseID: UUID? = nil,
            sourceFixedBillOccurrenceID: UUID? = nil
        ) {
            self.id = id
            self.title = title
            self.amount = amount
            self.date = date
            self.type = type
            self.category = category
            self.notes = notes
            self.sourceRecurringTransactionID = sourceRecurringTransactionID
            self.recurringOccurrenceID = recurringOccurrenceID
            self.paymentMethodRawValue = paymentMethodRawValue
            self.creditCard = creditCard
            self.creditCardInvoice = creditCardInvoice
            self.installmentNumber = installmentNumber
            self.totalInstallments = totalInstallments
            self.sourcePurchaseID = sourcePurchaseID
            self.sourceFixedBillOccurrenceID = sourceFixedBillOccurrenceID
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

    @Model
    final class CategoryBudget {
        @Attribute(.unique) var id: UUID
        var category: TransactionCategory
        var monthlyLimit: Decimal

        init(id: UUID = UUID(), category: TransactionCategory, monthlyLimit: Decimal) {
            self.id = id
            self.category = category
            self.monthlyLimit = monthlyLimit
        }
    }

    @Model
    final class FinanceSettings {
        @Attribute(.unique) var id: UUID
        var monthlySpendingBudget: Decimal

        init(id: UUID = UUID(), monthlySpendingBudget: Decimal) {
            self.id = id
            self.monthlySpendingBudget = monthlySpendingBudget
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
            self.dayOfMonth = dayOfMonth
            self.isActive = isActive
            self.lastGeneratedDate = lastGeneratedDate
        }
    }

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
            self.lastFourDigits = lastFourDigits
            self.closingDay = closingDay
            self.dueDay = dueDay
            self.creditLimit = creditLimit
            self.isActive = isActive
            self.colorName = colorName
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

        init(
            id: UUID = UUID(),
            name: String,
            category: TransactionCategory,
            dueDay: Int,
            estimatedAmount: Decimal? = nil,
            amountMode: FixedBillAmountMode,
            defaultPaymentMethodRawValue: String = PaymentMethod.debit.rawValue,
            startDate: Date,
            isActive: Bool = true,
            notes: String = "",
            createdAt: Date
        ) {
            self.id = id
            self.name = name
            self.category = category
            self.dueDay = dueDay
            self.estimatedAmount = estimatedAmount
            self.amountMode = amountMode
            self.defaultPaymentMethodRawValue = defaultPaymentMethodRawValue
            self.startDate = startDate
            self.isActive = isActive
            self.notes = notes
            self.createdAt = createdAt
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

        init(
            id: UUID = UUID(),
            occurrenceIdentifier: String,
            fixedBill: FixedBill,
            dueDate: Date,
            financialCycleIdentifier: String,
            status: FixedBillOccurrenceStatus = .pending,
            actualAmount: Decimal? = nil,
            paidDate: Date? = nil,
            paymentMethodRawValue: String? = nil,
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
            self.paymentMethodRawValue = paymentMethodRawValue
            self.generatedTransactionID = generatedTransactionID
        }
    }
}
