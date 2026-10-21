import SwiftData
import SwiftUI

struct EditTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TransactionCategory.name) private var categories: [TransactionCategory]

    let transaction: Transaction
    @State private var title: String
    @State private var amount: Decimal
    @State private var date: Date
    @State private var selectedCategoryID: UUID?
    @State private var notes: String
    @State private var paymentMethod: PaymentMethod
    @State private var errorMessage: String?
    @State private var financialCycleOverrideStart: Date?

    init(transaction: Transaction) {
        self.transaction = transaction
        _title = State(initialValue: transaction.title)
        _amount = State(initialValue: transaction.amount)
        _date = State(initialValue: transaction.date)
        _selectedCategoryID = State(initialValue: transaction.category?.id)
        _notes = State(initialValue: transaction.notes)
        _paymentMethod = State(initialValue: transaction.paymentMethod)
        _financialCycleOverrideStart = State(initialValue: transaction.financialCycleOverrideStartDate)
    }

    private var compatibleCategories: [TransactionCategory] {
        categories.filter { $0.type.supports(transaction.type) }
    }

    private var selectedCategory: TransactionCategory? {
        compatibleCategories.first { $0.id == selectedCategoryID }
    }

    private var canSave: Bool {
        transaction.canEditDirectly
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && amount > 0
            && selectedCategory != nil
            && paymentMethod != .creditCard
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Transaction") {
                    TextField("Title", text: $title)
                    MoneyField("Amount", amount: $amount)
                    DatePicker("Transaction Date", selection: $date, displayedComponents: .date)
                    Picker("Category", selection: $selectedCategoryID) {
                        ForEach(compatibleCategories) { category in
                            Label(category.displayName(), systemImage: category.iconName)
                                .tag(Optional(category.id))
                        }
                    }
                    if transaction.type != .income {
                        Picker("Payment Method", selection: $paymentMethod) {
                            ForEach(PaymentMethod.allCases.filter(\.isDirectPayment)) { method in
                                Text(method.displayName).tag(method)
                            }
                        }
                    }
                }
                FinancialCycleSelectionSection(date: date, overrideStart: $financialCycleOverrideStart)
                Section("Notes") {
                    TextEditor(text: $notes).frame(minHeight: 100)
                }
            }
            .navigationTitle("Edit Transaction")
            .onChange(of: date) {
                financialCycleOverrideStart = FinancialCycleAllocation.revalidated(financialCycleOverrideStart, for: date)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
            .alert("Unable to Save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func save() {
        guard let selectedCategory, canSave else { return }
        transaction.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        transaction.amount = amount
        transaction.date = date
        transaction.category = selectedCategory
        transaction.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        transaction.paymentMethod = transaction.type == .income ? .debit : paymentMethod
        transaction.financialCycleOverrideStartDate = FinancialCycleAllocation.revalidated(financialCycleOverrideStart, for: date)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
