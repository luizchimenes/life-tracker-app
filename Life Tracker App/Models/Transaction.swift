import Foundation
import SwiftData

enum TransactionType: String, Codable, CaseIterable, Identifiable {
    case income
    case expense
    case investment

    var id: Self { self }

    var displayName: LocalizedStringResource {
        switch self {
        case .income:
            "Income"
        case .expense:
            "Expense"
        case .investment:
            "Investment"
        }
    }
}

enum PaymentMethod: String, Codable, CaseIterable, Identifiable {
    case cash
    case pix
    case debit
    case creditCard
    case bankSlip

    var id: Self { self }

    var displayName: LocalizedStringResource {
        switch self {
        case .cash:
            "Cash"
        case .pix:
            "Pix"
        case .debit:
            "Debit"
        case .creditCard:
            "Credit Card"
        case .bankSlip:
            "Boleto"
        }
    }

    var isDirectPayment: Bool {
        self != .creditCard
    }

    /// Card charges need a card and an invoice; anything created without one
    /// falls back to Debit.
    var directOrDebit: PaymentMethod {
        isDirectPayment ? self : .debit
    }
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
    // Optional storage keeps transactions created by older app versions readable.
    // The public value defaults those legacy records to debit.
    var paymentMethodRawValue: String?
    var creditCard: CreditCard?
    var creditCardInvoice: CreditCardInvoice?
    var installmentNumber: Int?
    var totalInstallments: Int?
    var sourcePurchaseID: UUID?
    @Attribute(.unique) var sourceFixedBillOccurrenceID: UUID?

    var paymentMethod: PaymentMethod {
        get {
            paymentMethodRawValue.flatMap(PaymentMethod.init(rawValue:)) ?? .debit
        }
        set {
            paymentMethodRawValue = newValue.rawValue
        }
    }

    init(
        id: UUID = UUID(),
        title: String,
        amount: Decimal,
        date: Date,
        type: TransactionType,
        category: TransactionCategory,
        notes: String = "",
        sourceRecurringTransactionID: UUID? = nil,
        recurringOccurrenceID: String? = nil,
        paymentMethod: PaymentMethod = .debit,
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
        paymentMethodRawValue = paymentMethod.rawValue
        self.creditCard = creditCard
        self.creditCardInvoice = creditCardInvoice
        self.installmentNumber = installmentNumber
        self.totalInstallments = totalInstallments
        self.sourcePurchaseID = sourcePurchaseID
        self.sourceFixedBillOccurrenceID = sourceFixedBillOccurrenceID
    }

    /// Date that places the transaction in a financial cycle.
    /// Credit-card purchases count as spending when they are made, one
    /// installment per cycle; the invoice only governs limit and payment.
    var effectiveFinancialDate: Date {
        guard paymentMethod == .creditCard,
              let installmentNumber,
              installmentNumber > 1 else {
            return date
        }

        return Calendar.current.date(
            byAdding: .month,
            value: installmentNumber - 1,
            to: date
        ) ?? date
    }

    var invoiceDueDate: Date? {
        guard paymentMethod == .creditCard else {
            return nil
        }

        return creditCardInvoice?.dueDate
    }
}
