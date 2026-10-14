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

    init(transaction: Transaction) {
        self.transaction = transaction
        _title = State(initialValue: transaction.title)
        _amount = State(initialValue: transaction.amount)
        _date = State(initialValue: transaction.date)
        _selectedCategoryID = State(initialValue: transaction.category?.id)
        _notes = State(initialValue: transaction.notes)
        _paymentMethod = State(initialValue: transaction.paymentMethod)
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
                    TextField("Amount", value: $amount, format: .number.locale(AppLocalization.selectedLocale).precision(.fractionLength(0...2)))
#if os(iOS)
                        .keyboardType(.decimalPad)
#endif
                    DatePicker("Transaction Date", selection: $date, displayedComponents: .date)
                    Picker("Category", selection: $selectedCategoryID) {
                        ForEach(compatibleCategories) { category in
                            Label(category.displayName(), systemImage: category.iconName)
                                .tag(Optional(category.id))
                        }
                    }
                    if transaction.type == .expense {
                        Picker("Payment Method", selection: $paymentMethod) {
                            ForEach(PaymentMethod.allCases.filter(\.isDirectPayment)) { method in
                                Text(method.displayName).tag(method)
                            }
                        }
                    }
                }
                Section("Notes") {
                    TextEditor(text: $notes).frame(minHeight: 100)
                }
            }
            .navigationTitle("Edit Transaction")
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
        transaction.paymentMethod = transaction.type == .expense ? paymentMethod : .debit
        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
