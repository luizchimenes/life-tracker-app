import SwiftData
import SwiftUI

struct AddRecurringTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \TransactionCategory.name) private var categories: [TransactionCategory]
    @Query(sort: \CreditCard.name) private var creditCards: [CreditCard]

    private let recurringTransaction: RecurringTransaction?

    @State private var title: String
    @State private var amount: Decimal
    @State private var type: TransactionType
    @State private var selectedCategoryID: UUID?
    @State private var notes: String
    @State private var startDate: Date
    @State private var frequency: RecurringFrequency
    @State private var dayOfMonth: Int
    @State private var isActive: Bool
    @State private var paymentMethod: PaymentMethod
    @State private var selectedCreditCardID: UUID?
    @State private var showsSaveError = false
    @State private var saveErrorMessage = ""

    private var compatibleCategories: [TransactionCategory] {
        categories.filter { $0.type.supports(type) }
    }

    private var selectedCategory: TransactionCategory? {
        compatibleCategories.first { $0.id == selectedCategoryID }
    }

    private var activeCreditCards: [CreditCard] {
        creditCards.filter { $0.isActive || $0.id == recurringTransaction?.creditCard?.id }
    }

    private var selectedCreditCard: CreditCard? {
        activeCreditCards.first { $0.id == selectedCreditCardID }
    }

    private var usesCreditCard: Bool {
        type == .expense && paymentMethod == .creditCard
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && amount != 0
            && selectedCategory != nil
            && (!usesCreditCard || selectedCreditCard != nil)
    }

    init(recurringTransaction: RecurringTransaction? = nil) {
        self.recurringTransaction = recurringTransaction
        _title = State(initialValue: recurringTransaction?.title ?? "")
        _amount = State(initialValue: recurringTransaction?.amount ?? 0)
        _type = State(initialValue: recurringTransaction?.type ?? .expense)
        _selectedCategoryID = State(
            initialValue: recurringTransaction?.category.id
        )
        _notes = State(initialValue: recurringTransaction?.notes ?? "")
        _startDate = State(initialValue: recurringTransaction?.startDate ?? .now)
        _frequency = State(
            initialValue: recurringTransaction?.frequency ?? .monthly
        )
        _dayOfMonth = State(
            initialValue: recurringTransaction?.dayOfMonth
                ?? Calendar.current.component(.day, from: .now)
        )
        _isActive = State(initialValue: recurringTransaction?.isActive ?? true)
        _paymentMethod = State(initialValue: recurringTransaction?.paymentMethod ?? .debit)
        _selectedCreditCardID = State(initialValue: recurringTransaction?.creditCard?.id)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)

                    MoneyField("Amount", amount: $amount)

                    Picker("Type", selection: $type) {
                        ForEach(TransactionType.allCases.filter { $0 != .investment }) { transactionType in
                            Text(transactionType.displayName)
                                .tag(transactionType)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Category", selection: $selectedCategoryID) {
                        ForEach(compatibleCategories) { category in
                            HStack {
                                CategoryIcon(
                                    iconName: category.iconName,
                                    colorName: category.colorName,
                                    size: .body,
                                    width: 22
                                )
                                Text(category.displayName())
                            }
                            .tag(Optional(category.id))
                        }
                    }
                }

                if type == .expense {
                    Section {
                        Picker("Payment Method", selection: $paymentMethod) {
                            ForEach(PaymentMethod.allCases) { method in
                                Text(method.displayName).tag(method)
                            }
                        }
                        if paymentMethod == .creditCard {
                            Picker("Credit Card", selection: $selectedCreditCardID) {
                                ForEach(activeCreditCards) { card in
                                    Text("\(card.name) •••• \(card.lastFourDigits)")
                                        .tag(Optional(card.id))
                                }
                            }
                        }
                    } header: {
                        Text("Payment")
                    } footer: {
                        if paymentMethod == .creditCard {
                            Text("Each occurrence is charged once to this card's invoice. Changes apply to future occurrences only.")
                        }
                    }
                }

                Section("Schedule") {
                    DatePicker(
                        "Start Date",
                        selection: $startDate,
                        displayedComponents: .date
                    )

                    Picker("Frequency", selection: $frequency) {
                        ForEach(RecurringFrequency.allCases) { candidate in
                            Text(candidate.displayName)
                                .tag(candidate)
                        }
                    }

                    Stepper(
                        "Day of Month: \(dayOfMonth)",
                        value: $dayOfMonth,
                        in: 1...31
                    )

                    Toggle("Active", isOn: $isActive)
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle(
                recurringTransaction == nil
                    ? "New Recurring Transaction"
                    : "Edit Recurring Transaction"
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear(perform: selectFirstCompatibleCategoryIfNeeded)
            .onChange(of: type) {
                selectFirstCompatibleCategoryIfNeeded()
            }
            .onChange(of: categories.count) {
                selectFirstCompatibleCategoryIfNeeded()
            }
            .onChange(of: paymentMethod) {
                selectFirstCreditCardIfNeeded()
            }
            .alert("Unable to Save", isPresented: $showsSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage)
            }
        }
#if os(macOS)
        .frame(minWidth: 560, minHeight: 620)
#endif
    }

    private func save() {
        guard let selectedCategory else {
            return
        }

        if let recurringTransaction {
            recurringTransaction.title = title.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            recurringTransaction.amount = abs(amount)
            recurringTransaction.type = type
            recurringTransaction.category = selectedCategory
            recurringTransaction.notes = notes.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            recurringTransaction.startDate = startDate
            recurringTransaction.frequency = frequency
            recurringTransaction.dayOfMonth = dayOfMonth
            recurringTransaction.isActive = isActive
            recurringTransaction.paymentMethod = resolvedPaymentMethod
            recurringTransaction.creditCard = usesCreditCard ? selectedCreditCard : nil
        } else {
            modelContext.insert(
                RecurringTransaction(
                    title: title.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
                    amount: abs(amount),
                    type: type,
                    category: selectedCategory,
                    notes: notes.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
                    startDate: startDate,
                    frequency: frequency,
                    dayOfMonth: dayOfMonth,
                    isActive: isActive,
                    paymentMethod: resolvedPaymentMethod,
                    creditCard: usesCreditCard ? selectedCreditCard : nil
                )
            )
        }

        do {
            try modelContext.save()
            try RecurringTransactionGenerator.generateDueTransactions(
                in: modelContext
            )
            dismiss()
        } catch {
            modelContext.rollback()
            saveErrorMessage = error.localizedDescription
            showsSaveError = true
        }
    }

    /// Income always records as Debit, matching rules created before V2.
    private var resolvedPaymentMethod: PaymentMethod {
        type == .expense ? paymentMethod : .debit
    }

    private func selectFirstCreditCardIfNeeded() {
        guard usesCreditCard, selectedCreditCard == nil else {
            return
        }
        selectedCreditCardID = activeCreditCards.first?.id
    }

    private func selectFirstCompatibleCategoryIfNeeded() {
        guard selectedCategory == nil else {
            return
        }

        selectedCategoryID = compatibleCategories.first?.id
    }
}

#Preview {
    AddRecurringTransactionView()
        .modelContainer(LifeTrackerPersistence.previewContainer())
}
