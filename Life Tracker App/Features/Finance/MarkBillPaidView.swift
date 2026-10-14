import SwiftData
import SwiftUI

struct MarkBillPaidView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TransactionCategory.name) private var categories: [TransactionCategory]

    let occurrence: FixedBillOccurrence

    @State private var actualAmount: Decimal
    @State private var paidDate = Date.now
    @State private var paymentMethod: PaymentMethod
    @State private var selectedCategoryID: UUID?
    @State private var note = ""
    @State private var showsPaymentError = false
    @State private var paymentErrorMessage = ""

    private let currencyFormat = Decimal.FormatStyle.Currency(code: "BRL")
        .locale(AppLocalization.selectedLocale)

    private var expenseCategories: [TransactionCategory] {
        categories.filter { $0.type.supports(.expense) }
    }

    private var selectedCategory: TransactionCategory? {
        expenseCategories.first { $0.id == selectedCategoryID }
    }

    private var directPaymentMethods: [PaymentMethod] {
        PaymentMethod.allCases.filter(\.isDirectPayment)
    }

    init(occurrence: FixedBillOccurrence) {
        self.occurrence = occurrence
        _actualAmount = State(initialValue: occurrence.fixedBill.estimatedAmount ?? 0)
        _paymentMethod = State(initialValue: occurrence.fixedBill.defaultPaymentMethod)
        _selectedCategoryID = State(initialValue: occurrence.fixedBill.category.id)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Bill") {
                    LabeledContent("Name", value: occurrence.fixedBill.name)
                    if let estimate = occurrence.fixedBill.estimatedAmount {
                        LabeledContent(
                            occurrence.fixedBill.amountMode == .variable
                                ? "Estimated"
                                : "Expected",
                            value: estimate.formatted(currencyFormat)
                        )
                    }
                }

                Section("Payment") {
                    HStack {
                        Text("Amount Paid")
                        Spacer()
                        Text("R$")
                            .foregroundStyle(.secondary)
                        TextField(
                            "0,00",
                            value: $actualAmount,
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

                    DatePicker(
                        "Payment Date",
                        selection: $paidDate,
                        displayedComponents: .date
                    )

                    Picker("Payment Method", selection: $paymentMethod) {
                        ForEach(directPaymentMethods) { method in
                            Text(method.displayName).tag(method)
                        }
                    }

                    Picker("Category", selection: $selectedCategoryID) {
                        ForEach(expenseCategories) { category in
                            Label(category.displayName(), systemImage: category.iconName)
                                .tag(Optional(category.id))
                        }
                    }
                }

                Section("Optional Note") {
                    TextEditor(text: $note)
                        .frame(minHeight: 80)
                }

                Section {
                    Text("The obligation remains associated with its due-date financial cycle. The expense is recorded in the cycle containing the actual payment date.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Mark Bill Paid")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm Payment", action: confirmPayment)
                        .disabled(actualAmount <= 0 || selectedCategory == nil)
                }
            }
            .alert("Unable to Confirm Payment", isPresented: $showsPaymentError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(paymentErrorMessage)
            }
        }
#if os(macOS)
        .frame(minWidth: 540, minHeight: 620)
#endif
    }

    private func confirmPayment() {
        guard let selectedCategory else { return }

        do {
            try FixedBillPaymentService.markPaid(
                occurrence: occurrence,
                actualAmount: actualAmount,
                paidDate: paidDate,
                paymentMethod: paymentMethod,
                category: selectedCategory,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                in: modelContext
            )
            dismiss()
        } catch {
            modelContext.rollback()
            paymentErrorMessage = error.localizedDescription
            showsPaymentError = true
        }
    }
}
