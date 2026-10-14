import SwiftData
import SwiftUI

struct ManageBudgetsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \TransactionCategory.name) private var categories: [TransactionCategory]
    @Query private var budgets: [CategoryBudget]

    @State private var limits: [UUID: Decimal] = [:]
    @State private var showsSaveError = false
    @State private var saveErrorMessage = ""

    private var expenseCategories: [TransactionCategory] {
        categories.filter { $0.type.supports(.expense) }
    }

    var body: some View {
        NavigationStack {
            List(expenseCategories) { category in
                HStack(spacing: 12) {
                    CategoryIcon(
                        iconName: category.iconName,
                        colorName: category.colorName
                    )

                    Text(category.displayName())

                    Spacer()

                    HStack(spacing: 4) {
                        Text("R$")
                            .foregroundStyle(.secondary)

                        TextField(
                            "0,00",
                            value: limitBinding(for: category),
                            format: .number
                                .locale(AppLocalization.selectedLocale)
                                .precision(.fractionLength(0...2))
                        )
                        .multilineTextAlignment(.trailing)
                        .frame(minWidth: 80, idealWidth: 110, maxWidth: 140)
#if os(iOS)
                        .keyboardType(.decimalPad)
#endif
                    }
                }
            }
            .navigationTitle("Manage Budgets")
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
            .onAppear(perform: loadLimits)
            .alert("Unable to Save", isPresented: $showsSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage)
            }
        }
#if os(macOS)
        .frame(minWidth: 520, minHeight: 500)
#endif
    }

    private func limitBinding(for category: TransactionCategory) -> Binding<Decimal> {
        Binding(
            get: { limits[category.id, default: 0] },
            set: { limits[category.id] = max($0, 0) }
        )
    }

    private func loadLimits() {
        limits.removeAll()

        for budget in budgets {
            limits[budget.category.id] = budget.monthlyLimit
        }
    }

    private func save() {
        for category in expenseCategories {
            let limit = limits[category.id, default: 0]
            let existingBudgets = budgets.filter { $0.category.id == category.id }

            if limit > 0 {
                if let existingBudget = existingBudgets.first {
                    existingBudget.monthlyLimit = limit
                } else {
                    modelContext.insert(
                        CategoryBudget(category: category, monthlyLimit: limit)
                    )
                }

                for duplicate in existingBudgets.dropFirst() {
                    modelContext.delete(duplicate)
                }
            } else {
                for existingBudget in existingBudgets {
                    modelContext.delete(existingBudget)
                }
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
    ManageBudgetsView()
        .modelContainer(LifeTrackerPersistence.previewContainer())
}
