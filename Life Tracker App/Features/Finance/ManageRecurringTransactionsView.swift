import SwiftData
import SwiftUI

struct ManageRecurringTransactionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \RecurringTransaction.title)
    private var recurringTransactions: [RecurringTransaction]

    @State private var showsAddRecurringTransaction = false
    @State private var transactionToEdit: RecurringTransaction?
    @State private var showsPersistenceError = false
    @State private var persistenceErrorMessage = ""

    private var activeTransactions: [RecurringTransaction] {
        recurringTransactions.filter(\.isActive)
    }

    private var inactiveTransactions: [RecurringTransaction] {
        recurringTransactions.filter { !$0.isActive }
    }

    var body: some View {
        NavigationStack {
            List {
                if recurringTransactions.isEmpty {
                    ContentUnavailableView(
                        "No Recurring Transactions",
                        systemImage: "repeat",
                        description: Text("Add a recurring income or expense to get started.")
                    )
                } else {
                    recurringSection(
                        title: "Active",
                        transactions: activeTransactions
                    )

                    if !inactiveTransactions.isEmpty {
                        recurringSection(
                            title: "Inactive",
                            transactions: inactiveTransactions
                        )
                    }
                }
            }
            .navigationTitle("Recurring Transactions")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("Add Recurring Transaction", systemImage: "plus") {
                        showsAddRecurringTransaction = true
                    }
                }
            }
            .sheet(isPresented: $showsAddRecurringTransaction) {
                AddRecurringTransactionView()
            }
            .sheet(item: $transactionToEdit) { transaction in
                AddRecurringTransactionView(recurringTransaction: transaction)
            }
            .alert("Unable to Save", isPresented: $showsPersistenceError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(persistenceErrorMessage)
            }
        }
#if os(macOS)
        .frame(minWidth: 620, minHeight: 560)
#endif
    }

    @ViewBuilder
    private func recurringSection(
        title: LocalizedStringKey,
        transactions: [RecurringTransaction]
    ) -> some View {
        if !transactions.isEmpty {
            Section(title) {
                ForEach(transactions) { transaction in
                    HStack {
                        RecurringTransactionRow(
                            recurringTransaction: transaction
                        )
                        .onTapGesture {
                            transactionToEdit = transaction
                        }

                        Toggle(
                            "Active",
                            isOn: activeBinding(for: transaction)
                        )
                        .labelsHidden()
                    }
                }
                .onDelete {
                    deleteTransactions(at: $0, from: transactions)
                }
            }
        }
    }

    private func activeBinding(
        for transaction: RecurringTransaction
    ) -> Binding<Bool> {
        Binding(
            get: { transaction.isActive },
            set: { isActive in
                transaction.isActive = isActive
                persistChanges(generateTransactions: isActive)
            }
        )
    }

    private func deleteTransactions(
        at offsets: IndexSet,
        from transactions: [RecurringTransaction]
    ) {
        for index in offsets {
            modelContext.delete(transactions[index])
        }

        persistChanges(generateTransactions: false)
    }

    private func persistChanges(generateTransactions: Bool) {
        do {
            try modelContext.save()

            if generateTransactions {
                try RecurringTransactionGenerator.generateDueTransactions(
                    in: modelContext
                )
            }
        } catch {
            modelContext.rollback()
            persistenceErrorMessage = error.localizedDescription
            showsPersistenceError = true
        }
    }
}

#Preview {
    ManageRecurringTransactionsView()
        .modelContainer(LifeTrackerPersistence.previewContainer())
}
