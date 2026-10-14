import SwiftData
import SwiftUI

struct AddCategoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var budgets: [CategoryBudget]

    private let category: TransactionCategory?

    @State private var name: String
    @State private var type: TransactionCategoryType
    @State private var iconName: String
    @State private var colorName: CategoryColorName
    @State private var showsSaveError = false
    @State private var saveErrorMessage = ""

    private let iconNames = [
        "fork.knife", "car.fill", "house.fill", "heart.fill",
        "gamecontroller.fill", "bag.fill", "book.fill", "repeat",
        "banknote.fill", "chart.line.uptrend.xyaxis", "airplane",
        "fuelpump.fill", "cart.fill", "creditcard.fill", "gift.fill",
        "pawprint.fill", "dumbbell.fill", "iphone", "wifi", "bolt.fill",
        "drop.fill", "cross.case.fill", "graduationcap.fill",
        "briefcase.fill", "building.2.fill"
    ]

    private var isEditing: Bool {
        category != nil
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(category: TransactionCategory? = nil) {
        self.category = category
        _name = State(initialValue: category?.name ?? "")
        _type = State(initialValue: category?.type ?? .expense)
        _iconName = State(initialValue: category?.iconName ?? "tag.fill")
        _colorName = State(
            initialValue: CategoryColorName(rawValue: category?.colorName ?? "") ?? .blue
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)

                    Picker("Type", selection: $type) {
                        ForEach(TransactionCategoryType.allCases) { categoryType in
                            Text(categoryType.displayName)
                                .tag(categoryType)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Icon") {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 44))],
                        spacing: 12
                    ) {
                        ForEach(iconNames, id: \.self) { candidate in
                            Button {
                                iconName = candidate
                            } label: {
                                Image(systemName: candidate)
                                    .font(.title3)
                                    .foregroundStyle(
                                        candidate == iconName
                                            ? Color.white
                                            : colorName.color
                                    )
                                    .frame(width: 40, height: 40)
                                    .background(
                                        candidate == iconName
                                            ? colorName.color
                                            : Color.clear,
                                        in: .circle
                                    )
                                    .contentShape(.circle)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(candidate)
                            .accessibilityAddTraits(
                                candidate == iconName ? .isSelected : []
                            )
                        }
                    }
                    .padding(.vertical, 4)
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
                                    .contentShape(.circle)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(candidate.rawValue)
                            .accessibilityAddTraits(
                                candidate == colorName ? .isSelected : []
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(isEditing ? "Edit Category" : "New Category")
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
        .frame(minWidth: 560, minHeight: 620)
#endif
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if let category {
            category.name = trimmedName
            category.type = type
            category.iconName = iconName
            category.colorName = colorName.rawValue

            if !type.supports(.expense) {
                for budget in budgets where budget.category.id == category.id {
                    modelContext.delete(budget)
                }
            }
        } else {
            modelContext.insert(
                TransactionCategory(
                    name: trimmedName,
                    iconName: iconName,
                    colorName: colorName.rawValue,
                    type: type
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

#Preview {
    AddCategoryView()
        .modelContainer(LifeTrackerPersistence.previewContainer())
}
