import Foundation

struct InstallmentPurchaseSummary {
    let sourcePurchaseID: UUID
    let installments: [Transaction]

    init?(transaction: Transaction, allTransactions: [Transaction]) {
        guard let sourcePurchaseID = transaction.sourcePurchaseID else { return nil }
        self.sourcePurchaseID = sourcePurchaseID
        installments = allTransactions
            .filter { $0.sourcePurchaseID == sourcePurchaseID }
            .sorted { ($0.installmentNumber ?? 0) < ($1.installmentNumber ?? 0) }
    }

    var title: String {
        installments.first?.title ?? AppLocalization.string("Installment Purchase")
    }
    var originalTotal: Decimal { installments.reduce(0) { $0 + $1.amount } }
    var totalInstallments: Int { installments.map { $0.totalInstallments ?? 1 }.max() ?? installments.count }
    var standardInstallmentAmount: Decimal { installments.first?.amount ?? 0 }
    var accountedInstallments: Int {
        installments.count { invoiceStatus(for: $0) == .paid }
    }
    var currentInstallment: Int? {
        installments.first { invoiceStatus(for: $0) != .paid }?.installmentNumber
            ?? installments.last?.installmentNumber
    }
    var accountedAmount: Decimal {
        installments.filter { invoiceStatus(for: $0) == .paid }.reduce(0) { $0 + $1.amount }
    }
    var remainingInstallments: Int { max(totalInstallments - accountedInstallments, 0) }
    var remainingAmount: Decimal { max(originalTotal - accountedAmount, 0) }
    var finalInstallmentDate: Date? { installments.map { $0.invoiceDueDate ?? $0.effectiveFinancialDate }.max() }

    private func invoiceStatus(for transaction: Transaction) -> CreditCardInvoiceStatus? {
        transaction.creditCardInvoice?.effectiveStatus()
    }
}
