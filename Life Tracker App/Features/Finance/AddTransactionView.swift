import SwiftData
import SwiftUI

struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TransactionCategory.name) private var categories: [TransactionCategory]
    @Query(sort: \CreditCard.name) private var creditCards: [CreditCard]

    @State private var title = ""
    @State private var amount: Decimal?
    @State private var type = TransactionType.expense
    @State private var selectedCategoryID: UUID?
    @State private var date = Date.now
    @State private var notes = ""
    @State private var paymentMethod = PaymentMethod.debit
    @State private var selectedCreditCardID: UUID?
    @State private var usesInstallments = false
    @State private var installmentCount = 2
    /// Manual financial cycle; `nil` is Automatic (the default).
    @State private var financialCycleOverrideStart: Date?
    @State private var showsSaveError = false
    @State private var saveErrorMessage = ""

    /// Set when the form was prefilled by voice. The user still reviews and
    /// saves here, through the same path as a manual entry.
    private let voiceDraft: VoiceTransactionDraft?
    private let onTryAgain: (() -> Void)?

    init(voiceDraft: VoiceTransactionDraft? = nil, onTryAgain: (() -> Void)? = nil) {
        self.voiceDraft = voiceDraft
        self.onTryAgain = onTryAgain
        guard let draft = voiceDraft else { return }
        _title = State(initialValue: draft.title ?? "")
        _amount = State(initialValue: draft.amount)
        _type = State(initialValue: draft.type ?? .expense)
        _selectedCategoryID = State(initialValue: draft.categoryID)
        _date = State(initialValue: draft.transactionDate)
        _paymentMethod = State(initialValue: draft.paymentMethod ?? .debit)
        _selectedCreditCardID = State(initialValue: draft.creditCardID)
        if let count = draft.installmentCount, count > 1 {
            _usesInstallments = State(initialValue: true)
            _installmentCount = State(initialValue: count)
        }
    }

    /// Voice entries never preselect a category or card the parser was unsure about.
    private var autoSelectsMissingValues: Bool {
        voiceDraft == nil
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && selectedCategory != nil
            && (amount ?? 0) > 0
            && (type != .expense || paymentMethod != .creditCard || selectedCreditCard != nil)
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
                if let voiceDraft, !voiceDraft.originalTranscript.isEmpty {
                    VoiceDraftReviewSection(draft: voiceDraft, onTryAgain: onTryAgain)
                }

                Section("Details") {
                    TextField("Title", text: $title)

                    MoneyField("Amount", amount: $amount)

                    Picker("Type", selection: $type) {
                        ForEach(TransactionType.allCases) { transactionType in
                            Text(transactionType.displayName)
                                .tag(transactionType)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Category", selection: $selectedCategoryID) {
                        if selectedCategory == nil {
                            Text("Choose a category").tag(UUID?.none)
                        }
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

                    if type != .income {
                        Picker("Payment Method", selection: $paymentMethod) {
                            ForEach(PaymentMethod.allCases.filter {
                                type == .expense || $0.isDirectPayment
                            }) { method in
                                Text(method.displayName)
                                    .tag(method)
                            }
                        }

                        if paymentMethod == .creditCard {
                            Picker("Credit Card", selection: $selectedCreditCardID) {
                                if selectedCreditCard == nil {
                                    Text("Choose a card").tag(UUID?.none)
                                }
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

                FinancialCycleSelectionSection(date: date, overrideStart: $financialCycleOverrideStart)

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle(voiceDraft == nil ? "Add Transaction" : "Review Transaction")
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
                if type == .income || paymentMethod == .creditCard {
                    paymentMethod = .debit
                    usesInstallments = false
                }
            }
            .onChange(of: date) {
                financialCycleOverrideStart = FinancialCycleAllocation.revalidated(financialCycleOverrideStart, for: date)
            }
            .onAppear(perform: selectFirstCreditCardIfNeeded)
            .onChange(of: creditCards.count) {
                selectFirstCreditCardIfNeeded()
            }
        }
    }

    private func save() {
        guard let selectedCategory, let amount else {
            return
        }

        do {
            try TransactionEntry(
                title: title,
                amount: amount,
                type: type,
                category: selectedCategory,
                date: date,
                notes: notes,
                paymentMethod: paymentMethod,
                creditCard: selectedCreditCard,
                installmentCount: usesInstallments ? installmentCount : 1,
                financialCycleOverrideStart: financialCycleOverrideStart
            )
            .save(in: modelContext)
            dismiss()
        } catch {
            modelContext.rollback()
            saveErrorMessage = error.localizedDescription
            showsSaveError = true
        }
    }

    private func selectFirstCompatibleCategoryIfNeeded() {
        guard selectedCategory == nil, autoSelectsMissingValues else {
            return
        }

        selectedCategoryID = compatibleCategories.first?.id
    }

    private func selectFirstCreditCardIfNeeded() {
        guard selectedCreditCard == nil, autoSelectsMissingValues else {
            return
        }

        selectedCreditCardID = activeCreditCards.first?.id
    }
}

#Preview {
    AddTransactionView()
        .modelContainer(LifeTrackerPersistence.previewContainer())
}

/// The single save path for manually typed and voice-prefilled transactions.
/// Card expenses go through `CreditCardPurchaseService` (invoices and
/// installments); everything else is one direct transaction.
struct TransactionEntry {
    let title: String
    let amount: Decimal
    let type: TransactionType
    let category: TransactionCategory
    let date: Date
    let notes: String
    let paymentMethod: PaymentMethod
    let creditCard: CreditCard?
    let installmentCount: Int
    /// Manual financial cycle for the entry (or installment 1); `nil` is Automatic.
    var financialCycleOverrideStart: Date? = nil

    func save(in modelContext: ModelContext, calendar: Calendar = .current) throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard amount > 0, !trimmedTitle.isEmpty else { return }
        guard FinancialCycleAllocation.isValid(financialCycleOverrideStart, for: date, calendar: calendar) else {
            throw FinancialCycleAllocationError.notAllowed
        }

        if type == .expense, paymentMethod == .creditCard, let creditCard {
            try CreditCardPurchaseService.createPurchase(
                title: trimmedTitle,
                totalAmount: amount,
                purchaseDate: date,
                category: category,
                notes: trimmedNotes,
                creditCard: creditCard,
                installmentCount: installmentCount,
                financialCycleOverrideStart: financialCycleOverrideStart,
                in: modelContext,
                calendar: calendar
            )
        } else {
            modelContext.insert(
                Transaction(
                    title: trimmedTitle,
                    amount: abs(amount),
                    date: date,
                    type: type,
                    category: category,
                    notes: trimmedNotes,
                    paymentMethod: type == .income ? .debit : paymentMethod.directOrDebit,
                    financialCycleOverrideStartDate: financialCycleOverrideStart
                )
            )
            try modelContext.save()
        }
    }
}
