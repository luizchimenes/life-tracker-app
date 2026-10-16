import SwiftUI

/// Counts and payable total for Bills to Pay. Payment obligations only;
/// never mixed into spending.
struct BillsToPaySummaryView: View {
    let bills: BillsToPaySummary

    private let currencyFormat = Decimal.FormatStyle.Currency(code: "BRL")
        .locale(AppLocalization.selectedLocale)

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if bills.overdueCount > 0 {
                Text("\(Text(pendingText)) • \(Text(overdueText).foregroundStyle(.red))")
            } else {
                Text(pendingText)
            }

            if bills.pendingCount > 0 {
                Text(totalText)
                    .fontWeight(.semibold)
            }

            if bills.unknownAmountCount > 0 {
                Text(unknownText)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var pendingText: LocalizedStringResource {
        "\(bills.pendingCount) pending"
    }

    private var overdueText: LocalizedStringResource {
        "\(bills.overdueCount) overdue"
    }

    private var totalText: LocalizedStringResource {
        let total = bills.knownTotal.formatted(currencyFormat)
        if bills.unknownAmountCount > 0 {
            return "\(total) known"
        }
        return bills.includesEstimates ? "~ \(total)" : "\(total)"
    }

    private var unknownText: LocalizedStringResource {
        "+ \(bills.unknownAmountCount) amounts still unknown"
    }
}

/// Informational preview of a card's next invoice. It is still open, so it
/// cannot be paid and is not part of the payable count or total.
struct InvoicePreviewRow: View {
    let item: BillsToPaySummary.InvoiceItem

    private let currencyFormat = Decimal.FormatStyle.Currency(code: "BRL")
        .locale(AppLocalization.selectedLocale)

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "eye")
                .font(.title2)
                .foregroundStyle(.secondary)

            CategoryIcon(
                iconName: "creditcard.fill",
                colorName: item.invoice.creditCard.colorName
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("\(item.invoice.creditCard.name) Invoice")
                    .font(.headline)

                Text("Closes \(item.invoice.closingDate, format: .dateTime.month(.abbreviated).day()) • Due \(item.invoice.dueDate, format: .dateTime.month(.abbreviated).day())")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    Text(item.total.formatted(currencyFormat))
                    Text("Invoice Preview")
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: .capsule)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}
