import SwiftUI

struct InvoiceBillRow: View {
    let invoice: CreditCardInvoice
    let total: Decimal
    let action: () -> Void

    private let currencyFormat = Decimal.FormatStyle.Currency(code: "BRL")
        .locale(AppLocalization.selectedLocale)

    var body: some View {
        HStack(spacing: 12) {
            Button(action: action) {
                Image(systemName: "circle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark as paid")

            CategoryIcon(
                iconName: "creditcard.fill",
                colorName: invoice.creditCard.colorName
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("\(invoice.creditCard.name) Invoice")
                    .font(.headline)

                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(invoice.isOverdue() ? .red : .secondary)

                Text(total.formatted(currencyFormat))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private var statusText: LocalizedStringResource {
        invoice.isOverdue()
            ? "Overdue • Due \(invoice.dueDate, format: .dateTime.month(.abbreviated).day())"
            : "Due \(invoice.dueDate, format: .dateTime.month(.abbreviated).day())"
    }
}
