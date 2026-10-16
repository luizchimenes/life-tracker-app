import SwiftData
import SwiftUI

struct ManageMonthlyBudgetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var settingsRecords: [FinanceSettings]

    @State private var monthlyBudget: Decimal = 0
    @State private var showsSaveError = false
    @State private var saveErrorMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MoneyField("R$ 0,00", amount: $monthlyBudget)
                        .multilineTextAlignment(.trailing)
                } header: {
                    Text("Financial Cycle Spending Budget")
                } footer: {
                    Text("This recurring limit applies to each 9th-to-8th financial cycle. Set it to zero to remove it.")
                }
            }
            .navigationTitle("Financial Cycle Budget")
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
                }
            }
            .onAppear {
                monthlyBudget = settingsRecords.first?.monthlySpendingBudget ?? 0
            }
            .alert("Unable to Save", isPresented: $showsSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage)
            }
        }
#if os(macOS)
        .frame(minWidth: 480, minHeight: 280)
#endif
    }

    private func save() {
        let normalizedBudget = max(monthlyBudget, 0)

        if normalizedBudget > 0 {
            if let settings = settingsRecords.first {
                settings.monthlySpendingBudget = normalizedBudget
            } else {
                modelContext.insert(
                    FinanceSettings(monthlySpendingBudget: normalizedBudget)
                )
            }

            for duplicate in settingsRecords.dropFirst() {
                modelContext.delete(duplicate)
            }
        } else {
            for settings in settingsRecords {
                modelContext.delete(settings)
            }
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

#Preview {
    ManageMonthlyBudgetView()
        .modelContainer(LifeTrackerPersistence.previewContainer())
}
