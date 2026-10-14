import SwiftUI

struct RecurringTransactionRow: View {
    let recurringTransaction: RecurringTransaction

    private var formattedAmount: String {
        recurringTransaction.amount.formatted(
            .currency(code: "BRL").locale(AppLocalization.selectedLocale)
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(
                iconName: recurringTransaction.category.iconName,
                colorName: recurringTransaction.category.colorName
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(recurringTransaction.title)
                    .font(.headline)

                Text(formattedAmount)
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 3) {
                    Text(recurringTransaction.type.displayName)
                    Text("• Monthly on day \(recurringTransaction.dayOfMonth)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if !recurringTransaction.isActive {
                Text("Paused")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
