import SwiftData
import SwiftUI

struct AddFixedBillView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TransactionCategory.name) private var categories: [TransactionCategory]

    private let fixedBill: FixedBill?

    @State private var name: String
    @State private var selectedCategoryID: UUID?
    @State private var dueDay: Int
    @State private var amountMode: FixedBillAmountMode
    @State private var estimatedAmount: Decimal
    @State private var includesEstimate: Bool
    @State private var defaultPaymentMethod: PaymentMethod
    @State private var startDate: Date
    @State private var notes: String
    @State private var isActive: Bool
    @State private var showsSaveError = false
    @State private var saveErrorMessage = ""

    private var expenseCategories: [TransactionCategory] {
        categories.filter { $0.type.supports(.expense) }
    }

    private var selectedCategory: TransactionCategory? {
        expenseCategories.first { $0.id == selectedCategoryID }
    }

    private var directPaymentMethods: [PaymentMethod] {
        PaymentMethod.allCases.filter(\.isDirectPayment)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && selectedCategory != nil
            && (amountMode == .variable || estimatedAmount > 0)
    }

    init(fixedBill: FixedBill? = nil) {
        self.fixedBill = fixedBill
        _name = State(initialValue: fixedBill?.name ?? "")
        _selectedCategoryID = State(initialValue: fixedBill?.category.id)
        _dueDay = State(initialValue: fixedBill?.dueDay ?? 10)
        _amountMode = State(initialValue: fixedBill?.amountMode ?? .variable)
        _estimatedAmount = State(initialValue: fixedBill?.estimatedAmount ?? 0)
        _includesEstimate = State(initialValue: fixedBill?.estimatedAmount != nil)
        _defaultPaymentMethod = State(
            initialValue: fixedBill?.defaultPaymentMethod ?? .bankSlip
        )
        _startDate = State(initialValue: fixedBill?.startDate ?? .now)
        _notes = State(initialValue: fixedBill?.notes ?? "")
        _isActive = State(initialValue: fixedBill?.isActive ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)

                    Picker("Category", selection: $selectedCategoryID) {
                        ForEach(expenseCategories) { category in
                            Label(category.displayName(), systemImage: category.iconName)
                                .tag(Optional(category.id))
                        }
                    }

                    Stepper("Due Day: \(dueDay)", value: $dueDay, in: 1...31)
                }

                Section("Amount") {
                    Picker("Amount Type", selection: $amountMode) {
                        ForEach(FixedBillAmountMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if amountMode == .variable {
                        Toggle("Add an Estimate", isOn: $includesEstimate)
                    }

                    if amountMode == .fixed || includesEstimate {
                        HStack {
                            Text(amountMode == .variable ? "Estimated Amount" : "Expected Amount")
                            Spacer()
                            Text("R$")
                                .foregroundStyle(.secondary)
                            TextField(
                                "0,00",
                                value: $estimatedAmount,
                                format: .number
                                    .locale(AppLocalization.selectedLocale)
                                    .precision(.fractionLength(0...2))
                            )
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
#if os(iOS)
                            .keyboardType(.decimalPad)
#endif
                        }
                    }
                }

                Section("Payment") {
                    Picker("Default Method", selection: $defaultPaymentMethod) {
                        ForEach(directPaymentMethods) { method in
                            Text(method.displayName).tag(method)
                        }
                    }

                    DatePicker(
                        "Start Date",
                        selection: $startDate,
                        displayedComponents: .date
                    )
                    Toggle("Active", isOn: $isActive)
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 90)
                }
            }
            .navigationTitle(fixedBill == nil ? "New Fixed Expense" : "Edit Fixed Expense")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: selectCategoryIfNeeded)
            .onChange(of: categories.count) { selectCategoryIfNeeded() }
            .alert("Unable to Save", isPresented: $showsSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage)
            }
        }
#if os(macOS)
        .frame(minWidth: 560, minHeight: 680)
#endif
    }

    private func selectCategoryIfNeeded() {
        if selectedCategory == nil {
            selectedCategoryID = expenseCategories.first?.id
        }
    }

    private func save() {
        guard let selectedCategory else { return }

        let storedEstimate: Decimal? = amountMode == .fixed || includesEstimate
            ? max(estimatedAmount, 0)
            : nil

        if let fixedBill {
            fixedBill.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            fixedBill.category = selectedCategory
            fixedBill.dueDay = dueDay
            fixedBill.amountMode = amountMode
            fixedBill.estimatedAmount = storedEstimate
            fixedBill.defaultPaymentMethod = defaultPaymentMethod
            fixedBill.startDate = startDate
            fixedBill.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            fixedBill.isActive = isActive
        } else {
            modelContext.insert(
                FixedBill(
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    category: selectedCategory,
                    dueDay: dueDay,
                    estimatedAmount: storedEstimate,
                    amountMode: amountMode,
                    defaultPaymentMethod: defaultPaymentMethod,
                    startDate: startDate,
                    isActive: isActive,
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
        }

        do {
            try modelContext.save()
            try FixedBillOccurrenceGenerator.generateRelevantOccurrences(
                in: modelContext
            )
            dismiss()
        } catch {
            modelContext.rollback()
            saveErrorMessage = error.localizedDescription
            showsSaveError = true
        }
    }
}
