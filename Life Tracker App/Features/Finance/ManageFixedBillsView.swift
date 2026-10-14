import SwiftData
import SwiftUI

struct ManageFixedBillsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FixedBill.name) private var fixedBills: [FixedBill]

    @State private var showsAddBill = false
    @State private var billToEdit: FixedBill?
    @State private var showsPersistenceError = false
    @State private var persistenceErrorMessage = ""

    private var activeBills: [FixedBill] {
        fixedBills.filter(\.isActive)
    }

    private var inactiveBills: [FixedBill] {
        fixedBills.filter { !$0.isActive }
    }

    var body: some View {
        NavigationStack {
            List {
                if fixedBills.isEmpty {
                    ContentUnavailableView(
                        "No Fixed Expenses",
                        systemImage: "checklist",
                        description: Text("Add obligations that require monthly payment confirmation.")
                    )
                } else {
                    billSection("Active", bills: activeBills)

                    if !inactiveBills.isEmpty {
                        billSection("Inactive", bills: inactiveBills)
                    }
                }
            }
            .navigationTitle("Fixed Expenses")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Fixed Expense", systemImage: "plus") {
                        showsAddBill = true
                    }
                }
            }
            .sheet(isPresented: $showsAddBill) {
                AddFixedBillView()
            }
            .sheet(item: $billToEdit) { bill in
                AddFixedBillView(fixedBill: bill)
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
    private func billSection(
        _ title: LocalizedStringKey,
        bills: [FixedBill]
    ) -> some View {
        if !bills.isEmpty {
            Section(title) {
                ForEach(bills) { bill in
                    HStack(spacing: 12) {
                        CategoryIcon(
                            iconName: bill.category.iconName,
                            colorName: bill.category.colorName
                        )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(bill.name)
                                .fontWeight(.medium)
                            HStack(spacing: 3) {
                                Text("Due monthly on day \(bill.dueDay) •")
                                Text(bill.amountMode.displayName)
                            }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(.rect)
                        .onTapGesture { billToEdit = bill }

                        Spacer()

                        Toggle("Active", isOn: activeBinding(for: bill))
                            .labelsHidden()
                    }
                }
            }
        }
    }

    private func activeBinding(for bill: FixedBill) -> Binding<Bool> {
        Binding(
            get: { bill.isActive },
            set: { isActive in
                bill.isActive = isActive
                persistChanges(generateOccurrences: isActive)
            }
        )
    }

    private func persistChanges(generateOccurrences: Bool) {
        do {
            try modelContext.save()
            if generateOccurrences {
                try FixedBillOccurrenceGenerator.generateRelevantOccurrences(
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
