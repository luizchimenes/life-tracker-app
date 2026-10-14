import SwiftUI

struct HomeInvoiceBillRow: View {
    let invoice: CreditCardInvoice

    var body: some View {
        HStack(spacing: 10) {
            CategoryIcon(
                iconName: "creditcard.fill",
                colorName: invoice.creditCard.colorName,
                size: .body,
                width: 24
            )

            VStack(alignment: .leading, spacing: 3) {
                Text("\(invoice.creditCard.name) Invoice")
                    .fontWeight(.medium)

                Text(dueText)
                    .font(.caption)
                    .foregroundStyle(invoice.isOverdue() ? .red : .secondary)
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private var dueText: LocalizedStringResource {
        invoice.isOverdue()
            ? "Overdue • Due \(invoice.dueDate, format: .dateTime.month(.abbreviated).day())"
            : "Due \(invoice.dueDate, format: .dateTime.month(.abbreviated).day())"
    }
}
