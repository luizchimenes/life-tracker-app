import SwiftData
import SwiftUI

struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TransactionCategory.name) private var categories: [TransactionCategory]
    @Query(sort: \CreditCard.name) private var creditCards: [CreditCard]

    @State private var title = ""
    @State private var amount: Decimal = 0
    @State private var type = TransactionType.expense
    @State private var selectedCategoryID: UUID?
    @State private var date = Date.now
    @State private var notes = ""
    @State private var paymentMethod = PaymentMethod.debit
    @State private var selectedCreditCardID: UUID?
    @State private var usesInstallments = false
    @State private var installmentCount = 2
    @State private var showsSaveError = false
    @State private var saveErrorMessage = ""

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && selectedCategory != nil
            && amount != 0
            && (paymentMethod != .creditCard || selectedCreditCard != nil)
    }

    private var compatibleCategories: [TransactionCategory] {
        categories.filter { $0.type.supports(type) }
    }

    private var selectedCategory: TransactionCategory? {
        compatibleCategories.first { $0.id == selectedCategoryID }
    }

    private var activeCreditCards: [CreditCard] {
        creditCards.filter(\.isActive)
    }

    private var selectedCreditCard: CreditCard? {
        activeCreditCards.first { $0.id == selectedCreditCardID }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)

                    TextField(
                        "Amount",
                        value: $amount,
                        format: .number
                            .locale(AppLocalization.selectedLocale)
                            .precision(.fractionLength(0...2))
                    )
#if os(iOS)
                    .keyboardType(.decimalPad)
#endif

                    Picker("Type", selection: $type) {
                        ForEach(TransactionType.allCases) { transactionType in
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
                    DatePicker("Date", selection: $date, displayedComponents: .date)

                    if type == .expense {
                        Picker("Payment Method", selection: $paymentMethod) {
                            ForEach(PaymentMethod.allCases) { method in
                                Text(method.displayName)
                                    .tag(method)
                            }
                        }

                        if paymentMethod == .creditCard {
                            Picker("Credit Card", selection: $selectedCreditCardID) {
                                ForEach(activeCreditCards) { card in
                                    Text("\(card.name) •••• \(card.lastFourDigits)")
                                        .tag(Optional(card.id))
                                }
                            }

                            Toggle("Installment Purchase", isOn: $usesInstallments)

                            if usesInstallments {
                                Stepper(
                                    "Installments: \(installmentCount)",
                                    value: $installmentCount,
                                    in: 2...36
                                )
                            }
                        }
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle("Add Transaction")
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
            .alert("Unable to Save", isPresented: $showsSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage)
            }
            .onAppear(perform: selectFirstCompatibleCategoryIfNeeded)
            .onChange(of: type) {
                selectFirstCompatibleCategoryIfNeeded()
            }
            .onChange(of: categories.count) {
                selectFirstCompatibleCategoryIfNeeded()
            }
            .onChange(of: type) {
                if type == .income {
                    paymentMethod = .debit
                }
            }
            .onAppear(perform: selectFirstCreditCardIfNeeded)
            .onChange(of: creditCards.count) {
                selectFirstCreditCardIfNeeded()
            }
        }
    }

    private func save() {
        guard let selectedCategory else {
            return
        }

        do {
            let trimmedTitle = title.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let trimmedNotes = notes.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            if type == .expense,
               paymentMethod == .creditCard,
               let selectedCreditCard {
                try CreditCardPurchaseService.createPurchase(
                    title: trimmedTitle,
                    totalAmount: amount,
                    purchaseDate: date,
                    category: selectedCategory,
                    notes: trimmedNotes,
                    creditCard: selectedCreditCard,
                    installmentCount: usesInstallments ? installmentCount : 1,
                    in: modelContext
                )
            } else {
                modelContext.insert(
                    Transaction(
                        title: trimmedTitle,
                        amount: abs(amount),
                        date: date,
                        type: type,
                        category: selectedCategory,
                        notes: trimmedNotes,
                        paymentMethod: type == .expense
                            ? paymentMethod
                            : .debit
                    )
                )
                try modelContext.save()
            }
            dismiss()
        } catch {
            modelContext.rollback()
            saveErrorMessage = error.localizedDescription
            showsSaveError = true
        }
    }

    private func selectFirstCompatibleCategoryIfNeeded() {
        guard selectedCategory == nil else {
            return
        }

        selectedCategoryID = compatibleCategories.first?.id
    }

    private func selectFirstCreditCardIfNeeded() {
        guard selectedCreditCard == nil else {
            return
        }

        selectedCreditCardID = activeCreditCards.first?.id
    }
}

#Preview {
    AddTransactionView()
        .modelContainer(LifeTrackerPersistence.previewContainer())
}
