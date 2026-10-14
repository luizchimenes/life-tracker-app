import SwiftData
import SwiftUI

struct ManageCategoriesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \TransactionCategory.name) private var categories: [TransactionCategory]
    @Query private var transactions: [Transaction]
    @Query private var budgets: [CategoryBudget]
    @Query private var recurringTransactions: [RecurringTransaction]
    @Query private var fixedBills: [FixedBill]

    @State private var showsAddCategory = false
    @State private var categoryToEdit: TransactionCategory?
    @State private var deletionMessage: String?
    @State private var showsSaveError = false
    @State private var saveErrorMessage = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(TransactionCategoryType.allCases) { categoryType in
                    let matchingCategories = categories.filter {
                        $0.type == categoryType
                    }

                    if !matchingCategories.isEmpty {
                        Section(categoryType.displayName) {
                            ForEach(matchingCategories) { category in
                                CategoryManagementRow(category: category)
                                    .onTapGesture {
                                        guard !category.isDefault else {
                                            return
                                        }

                                        categoryToEdit = category
                                    }
                                    .deleteDisabled(category.isDefault)
                            }
                            .onDelete {
                                deleteCategories(
                                    at: $0,
                                    from: matchingCategories
                                )
                            }
                        }
                    }
                }
            }
            .navigationTitle("Manage Categories")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("Add Category", systemImage: "plus") {
                        showsAddCategory = true
                    }
                }
            }
            .sheet(isPresented: $showsAddCategory) {
                AddCategoryView()
            }
            .sheet(item: $categoryToEdit) { category in
                AddCategoryView(category: category)
            }
            .alert(
                "Category Can’t Be Deleted",
                isPresented: Binding(
                    get: { deletionMessage != nil },
                    set: { if !$0 { deletionMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deletionMessage ?? "")
            }
            .alert("Unable to Delete", isPresented: $showsSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage)
            }
        }
#if os(macOS)
        .frame(minWidth: 560, minHeight: 560)
#endif
    }

    private func deleteCategories(
        at offsets: IndexSet,
        from matchingCategories: [TransactionCategory]
    ) {
        for index in offsets {
            let category = matchingCategories[index]

            guard !category.isDefault else {
                deletionMessage = AppLocalization.string("Built-in categories can’t be deleted.")
                return
            }

            guard !transactions.contains(where: { $0.category?.id == category.id }) else {
                deletionMessage = AppLocalization.string("This category is used by one or more transactions. Reassign those transactions before deleting it.")
                return
            }

            guard !budgets.contains(where: { $0.category.id == category.id }) else {
                deletionMessage = AppLocalization.string("This category has a financial cycle budget. Remove its budget before deleting it.")
                return
            }

            guard !recurringTransactions.contains(where: { $0.category.id == category.id }) else {
                deletionMessage = AppLocalization.string("This category is used by a recurring transaction. Remove or reassign that recurring rule before deleting it.")
                return
            }

            guard !fixedBills.contains(where: { $0.category.id == category.id }) else {
                deletionMessage = AppLocalization.string("This category is used by a fixed expense. Reassign that fixed expense before deleting it.")
                return
            }

            modelContext.delete(category)
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            saveErrorMessage = error.localizedDescription
            showsSaveError = true
        }
    }
}

#Preview {
    ManageCategoriesView()
        .modelContainer(LifeTrackerPersistence.previewContainer())
}
