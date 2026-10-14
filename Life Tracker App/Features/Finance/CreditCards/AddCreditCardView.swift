import SwiftData
import SwiftUI

struct AddCreditCardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let creditCard: CreditCard?

    @State private var name: String
    @State private var lastFourDigits: String
    @State private var closingDay: Int
    @State private var dueDay: Int
    @State private var creditLimit: Decimal
    @State private var isActive: Bool
    @State private var colorName: CategoryColorName
    @State private var showsSaveError = false
    @State private var saveErrorMessage = ""

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && lastFourDigits.count == 4
            && creditLimit >= 0
    }

    init(creditCard: CreditCard? = nil) {
        self.creditCard = creditCard
        _name = State(initialValue: creditCard?.name ?? "")
        _lastFourDigits = State(initialValue: creditCard?.lastFourDigits ?? "")
        _closingDay = State(initialValue: creditCard?.closingDay ?? 2)
        _dueDay = State(initialValue: creditCard?.dueDay ?? 9)
        _creditLimit = State(initialValue: creditCard?.creditLimit ?? 0)
        _isActive = State(initialValue: creditCard?.isActive ?? true)
        _colorName = State(
            initialValue: CategoryColorName(
                rawValue: creditCard?.colorName ?? ""
            ) ?? .blue
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Card") {
                    TextField("Name", text: $name)

                    TextField("Last 4 Digits", text: $lastFourDigits)
#if os(iOS)
                        .keyboardType(.numberPad)
#endif
                        .onChange(of: lastFourDigits) {
                            lastFourDigits = String(
                                lastFourDigits
                                    .filter(\.isNumber)
                                    .prefix(4)
                            )
                        }

                    TextField(
                        "Credit Limit (R$)",
                        value: $creditLimit,
                        format: .number
                            .locale(AppLocalization.selectedLocale)
                            .precision(.fractionLength(0...2))
                    )
#if os(iOS)
                    .keyboardType(.decimalPad)
#endif

                    Stepper(
                        "Closing Day: \(closingDay)",
                        value: $closingDay,
                        in: 1...31
                    )
                    Stepper(
                        "Due Day: \(dueDay)",
                        value: $dueDay,
                        in: 1...31
                    )
                    Toggle("Active", isOn: $isActive)
                }

                Section("Color") {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 44))],
                        spacing: 12
                    ) {
                        ForEach(CategoryColorName.allCases) { candidate in
                            Button {
                                colorName = candidate
                            } label: {
                                Circle()
                                    .fill(candidate.color)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        if candidate == colorName {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .frame(width: 40, height: 40)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle(
                creditCard == nil ? "New Credit Card" : "Edit Credit Card"
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
            .alert("Unable to Save", isPresented: $showsSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage)
            }
        }
#if os(macOS)
        .frame(minWidth: 520, minHeight: 580)
#endif
    }

    private func save() {
        if let creditCard {
            creditCard.name = name.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            creditCard.lastFourDigits = lastFourDigits
            creditCard.closingDay = closingDay
            creditCard.dueDay = dueDay
            creditCard.creditLimit = max(creditLimit, 0)
            creditCard.isActive = isActive
            creditCard.colorName = colorName.rawValue
        } else {
            modelContext.insert(
                CreditCard(
                    name: name.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
                    lastFourDigits: lastFourDigits,
                    closingDay: closingDay,
                    dueDay: dueDay,
                    creditLimit: creditLimit,
                    isActive: isActive,
                    colorName: colorName.rawValue
                )
            )
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            saveErrorMessage = error.localizedDescription
            showsSaveError = true
        }
    }
}
