import SwiftData
import SwiftUI

extension FinancialCycle {
    /// "09/10 – 08/11": the full interval, so the choice is never ambiguous.
    var compactRangeText: String {
        let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: end) ?? end
        let style = Date.FormatStyle.dateTime
            .day(.twoDigits)
            .month(.twoDigits)
            .locale(AppLocalization.selectedLocale)
        return "\(start.formatted(style)) – \(lastDay.formatted(style))"
    }
}

/// Optional choice of which financial cycle counts an entry dated near the 9th.
/// Hidden on other dates unless the entry already has a manual choice.
struct FinancialCycleSelectionSection: View {
    let date: Date
    @Binding var overrideStart: Date?

    private var options: [FinancialCycleAllocation.Option] {
        FinancialCycleAllocation.options(for: date)
    }

    var body: some View {
        if !options.isEmpty || overrideStart != nil {
            Section {
                Picker("Count in Financial Cycle", selection: $overrideStart) {
                    ForEach(options) { option in
                        Text(Self.label(option)).tag(option.overrideStart)
                    }
                    if let overrideStart, !options.contains(where: { $0.overrideStart == overrideStart }),
                       let cycle = FinancialCycle(containing: overrideStart) {
                        Text("Manually Assigned — \(cycle.compactRangeText)").tag(Optional(overrideStart))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Financial Cycle")
            } footer: {
                Text("Only changes which cycle's totals include this entry. The date, card invoice and installments stay the same.")
            }
        }
    }

    static func label(_ option: FinancialCycleAllocation.Option) -> LocalizedStringResource {
        let range = option.cycle.compactRangeText
        return switch option.kind {
        case .automatic: "Automatic — \(range)"
        case .next: "Next Cycle — \(range)"
        case .previous: "Previous Cycle — \(range)"
        }
    }
}

/// "Alterar ciclo financeiro" for an existing entry. Changes only the cycle
/// allocation (for a purchase, of the whole installment group).
struct ChangeFinancialCycleView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allTransactions: [Transaction]

    let transaction: Transaction
    @State private var overrideStart: Date?
    @State private var errorMessage: String?

    init(transaction: Transaction, currentSelection: Date?) {
        self.transaction = transaction
        _overrideStart = State(initialValue: currentSelection)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(transaction.paymentMethod == .creditCard ? "Purchase Date" : "Transaction Date") {
                        Text(transaction.date, format: .dateTime.day().month().year())
                    }
                } footer: {
                    if transaction.sourcePurchaseID != nil, (transaction.totalInstallments ?? 1) > 1 {
                        Text("Installment 1 counts in the chosen cycle and each later installment in the following cycles. Invoices are not changed.")
                    }
                }

                FinancialCycleSelectionSection(date: transaction.date, overrideStart: $overrideStart)
            }
            .navigationTitle("Change Financial Cycle")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .alert("Unable to Save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() {
        do {
            try FinancialCycleAllocationService.apply(
                overrideStart,
                to: transaction,
                allTransactions: allTransactions,
                in: modelContext
            )
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
