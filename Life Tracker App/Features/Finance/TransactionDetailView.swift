import SwiftData
import SwiftUI

struct TransactionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allTransactions: [Transaction]
    @Query private var recurringRules: [RecurringTransaction]
    @Query private var fixedBillOccurrences: [FixedBillOccurrence]

    let transaction: Transaction

    @State private var showsEdit = false
    @State private var showsChangeCycle = false
    @State private var showsDeleteConfirmation = false
    @State private var errorMessage: String?

    private let currency = Decimal.FormatStyle.Currency(code: "BRL")
        .locale(AppLocalization.selectedLocale)

    private var installmentSummary: InstallmentPurchaseSummary? {
        InstallmentPurchaseSummary(transaction: transaction, allTransactions: allTransactions)
    }

    private var recurringRule: RecurringTransaction? {
        guard let id = transaction.sourceRecurringTransactionID else { return nil }
        return recurringRules.first { $0.id == id }
    }

    private var fixedBillOccurrence: FixedBillOccurrence? {
        guard let id = transaction.sourceFixedBillOccurrenceID else { return nil }
        return fixedBillOccurrences.first { $0.id == id }
    }

    var body: some View {
        List {
            Section("Transaction") {
                LabeledContent("Title", value: transaction.title)
                LabeledContent("Amount", value: transaction.amount.formatted(currency))
                LabeledContent("Type") { Text(transaction.type.displayName) }
                LabeledContent("Category", value: transaction.category?.displayName() ?? String(localized: "Uncategorized", locale: AppLocalization.selectedLocale))
                LabeledContent(transaction.paymentMethod == .creditCard ? "Purchase Date" : "Transaction Date") {
                    Text(transaction.date, format: .dateTime.day().month().year())
                }
                if let cycle = transaction.effectiveFinancialCycle {
                    LabeledContent("Financial Cycle") {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(cycle.compactRangeText)
                            Text(transaction.hasManualFinancialCycle ? "Manually Assigned" : "Automatic")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                LabeledContent("Payment Method") { Text(transaction.paymentMethod.displayName) }
            }

            if let recurringRule {
                Section("Recurring Source") {
                    LabeledContent("Rule", value: recurringRule.title)
                    Text("This is historical activity. Edit the recurring rule to change future occurrences.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let occurrence = fixedBillOccurrence {
                Section("Fixed Bill Source") {
                    LabeledContent("Bill", value: occurrence.fixedBill.name)
                    LabeledContent("Status") { Text(occurrence.status.displayName) }
                    LabeledContent("Obligation Due Date") {
                        Text(occurrence.dueDate, format: .dateTime.day().month().year())
                    }
                    if let paidDate = occurrence.paidDate {
                        LabeledContent("Actual Payment Date") {
                            Text(paidDate, format: .dateTime.day().month().year())
                        }
                    }
                    Text("The obligation stays in the financial cycle containing its due date. Spending belongs to the cycle containing the actual payment date.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Correct this payment by reverting it from Bills to Pay, then confirm the payment again.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if transaction.paymentMethod == .creditCard {
                Section("Credit Card") {
                    if let card = transaction.creditCard {
                        LabeledContent("Card", value: "\(card.name) •••• \(card.lastFourDigits)")
                    }
                    if let invoice = transaction.creditCardInvoice {
                        LabeledContent("Invoice") {
                            Text(invoice.referenceMonth, format: .dateTime.month(.wide).year())
                        }
                        LabeledContent("Invoice Due") {
                            Text(invoice.dueDate, format: .dateTime.day().month().year())
                        }
                    }
                    if let number = transaction.installmentNumber,
                       let count = transaction.totalInstallments,
                       count > 1 {
                        LabeledContent("Installment") {
                            Text("\(number) of \(count)")
                        }
                        if let installmentSummary {
                            LabeledContent("Original Purchase Total", value: installmentSummary.originalTotal.formatted(currency))
                            LabeledContent("Installment Plan") {
                                Text("\(count)× \(installmentSummary.standardInstallmentAmount.formatted(currency))")
                            }
                            LabeledContent("Remaining Commitment") {
                                Text("\(installmentSummary.remainingInstallments) installments • \(installmentSummary.remainingAmount.formatted(currency))")
                            }
                        }
                    }
                }
            }

            if let installmentSummary {
                Section {
                    NavigationLink("Manage Installment Purchase") {
                        InstallmentPurchaseView(summary: installmentSummary)
                    }
                } footer: {
                    Text("Installment records are managed as one purchase to preserve invoice reconciliation.")
                }
            }

            if !transaction.notes.isEmpty {
                Section("Notes") { Text(transaction.notes) }
            }

            Section {
                if transaction.canEditDirectly {
                    Button("Edit Transaction", systemImage: "pencil") { showsEdit = true }
                } else {
                    sourceEditingGuidance
                    // Card purchases cannot be edited, but their cycle allocation
                    // can change without touching invoices or installments.
                    if canChangeCycle {
                        Button("Change Financial Cycle", systemImage: "calendar.badge.clock") { showsChangeCycle = true }
                    }
                }
                Button("Delete", systemImage: "trash", role: .destructive) {
                    showsDeleteConfirmation = true
                }
            }
        }
        .navigationTitle("Transaction")
        .sheet(isPresented: $showsEdit) { EditTransactionView(transaction: transaction) }
        .sheet(isPresented: $showsChangeCycle) {
            ChangeFinancialCycleView(
                transaction: transaction,
                currentSelection: FinancialCycleAllocationService.currentSelection(for: transaction, allTransactions: allTransactions)
            )
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(deleteButtonTitle, role: .destructive, action: deleteTransaction)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteMessage)
        }
        .alert("Unable to Delete", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    /// Card purchases near the 9th, or with a manual choice to undo.
    private var canChangeCycle: Bool {
        transaction.sourceKind == .installment
            && FinancialCycleAllocationService.canChangeAllocation(of: transaction)
            && (!FinancialCycleAllocation.options(for: transaction.date).isEmpty
                || FinancialCycleAllocationService.currentSelection(for: transaction, allTransactions: allTransactions) != nil)
    }

    @ViewBuilder
    private var sourceEditingGuidance: some View {
        switch transaction.sourceKind {
        case .recurring:
            Label("Edit future occurrences in Recurring Transactions", systemImage: "repeat")
                .foregroundStyle(.secondary)
        case .fixedBill:
            Label("Correct payment from Bills to Pay", systemImage: "checklist")
                .foregroundStyle(.secondary)
        case .installment:
            Label("Manage the complete installment purchase", systemImage: "creditcard")
                .foregroundStyle(.secondary)
        case .manual:
            Label("Credit-card history cannot be edited in place", systemImage: "lock")
                .foregroundStyle(.secondary)
        }
    }

    private var deleteTitle: LocalizedStringResource {
        transaction.sourceKind != .installment ? "Delete Transaction?" : "Delete Entire Installment Purchase?"
    }

    private var deleteButtonTitle: LocalizedStringResource {
        transaction.sourceKind != .installment ? "Delete Transaction" : "Delete Entire Purchase"
    }

    private var deleteMessage: LocalizedStringResource {
        switch transaction.sourceKind {
        case .recurring:
            "This removes only this historical occurrence. The recurring rule remains active and future occurrences continue."
        case .fixedBill:
            "This removes the linked payment and restores the bill occurrence to pending."
        case .installment:
            "All installments for this purchase will be deleted from their invoices. This cannot be undone."
        case .manual:
            "This transaction will be permanently deleted."
        }
    }

    private func deleteTransaction() {
        do {
            let records = try TransactionDeletionService.transactionsForSafeDeletion(
                of: transaction,
                from: allTransactions
            )
            try TransactionDeletionService.delete(records, from: allTransactions, in: modelContext)
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
