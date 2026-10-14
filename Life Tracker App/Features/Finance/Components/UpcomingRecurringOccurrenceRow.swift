import SwiftUI

struct UpcomingRecurringOccurrenceRow: View {
    let occurrence: UpcomingRecurringOccurrence

    private var signedAmount: String {
        let amount = occurrence.amount.formatted(
            .currency(code: "BRL").locale(AppLocalization.selectedLocale)
        )
        return (occurrence.type == .income ? "+" : "−") + amount
    }

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(
                iconName: occurrence.category.iconName,
                colorName: occurrence.category.colorName
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(occurrence.recurringTransaction.title)
                    .font(.headline)

                Text(
                    occurrence.date,
                    format: .dateTime.day().month(.abbreviated)
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(signedAmount)
                .fontWeight(.semibold)
                .foregroundStyle(
                    occurrence.type == .income ? .green : .red
                )
        }
        .accessibilityElement(children: .combine)
    }
}
