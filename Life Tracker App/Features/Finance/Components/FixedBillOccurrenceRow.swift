import SwiftUI

struct FixedBillOccurrenceRow: View {
    let occurrence: FixedBillOccurrence
    let action: () -> Void

    private let currencyFormat = Decimal.FormatStyle.Currency(code: "BRL")
        .locale(AppLocalization.selectedLocale)

    var body: some View {
        HStack(spacing: 12) {
            Button(action: action) {
                Image(
                    systemName: occurrence.status == .paid
                        ? "checkmark.circle.fill"
                        : "circle"
                )
                .font(.title2)
                .foregroundStyle(occurrence.status == .paid ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                occurrence.status == .paid
                    ? "Revert payment"
                    : "Mark as paid"
            )

            CategoryIcon(
                iconName: occurrence.fixedBill.category.iconName,
                colorName: occurrence.fixedBill.category.colorName
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(occurrence.fixedBill.name)
                    .font(.headline)

                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(
                        occurrence.isOverdue() ? .red : .secondary
                    )

                if occurrence.status == .paid,
                   let actualAmount = occurrence.actualAmount {
                    Text(actualAmount.formatted(currencyFormat))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let estimate = occurrence.fixedBill.estimatedAmount {
                    Text(estimateText(estimate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private var statusText: LocalizedStringResource {
        if occurrence.status == .paid, let paidDate = occurrence.paidDate {
            return "Due \(occurrence.dueDate, format: .dateTime.month(.abbreviated).day()) • Paid \(paidDate, format: .dateTime.month(.abbreviated).day())"
        }
        if occurrence.isOverdue() {
            return "Overdue • Due \(occurrence.dueDate, format: .dateTime.month(.abbreviated).day())"
        }
        if occurrence.status == .skipped {
            return "Skipped"
        }
        return "Due \(occurrence.dueDate, format: .dateTime.month(.abbreviated).day())"
    }

    private func estimateText(_ amount: Decimal) -> String {
        let formatted = amount.formatted(currencyFormat)
        return occurrence.fixedBill.amountMode == .variable
            ? "~ \(formatted)"
            : formatted
    }
}
