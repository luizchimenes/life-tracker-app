import SwiftUI

struct TransactionRow: View {
    let transaction: Transaction

    private var signedAmount: String {
        let formattedAmount = transaction.amount.formatted(
            .currency(code: "BRL").locale(AppLocalization.selectedLocale)
        )
        let sign = TransactionAmountPresentation.sign(for: transaction.type)
        return sign + formattedAmount
    }

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(
                iconName: transaction.category?.iconName ?? "questionmark.circle.fill",
                colorName: transaction.category?.colorName ?? "gray"
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.title)
                    .font(.headline)

                HStack(spacing: 4) {
                    Text(transaction.category?.displayName() ?? String(localized: "Uncategorized", locale: AppLocalization.selectedLocale))

                    if transaction.paymentMethod == .creditCard {
                        if let cardName = transaction.creditCard?.name {
                            Text("• \(cardName)")
                        } else {
                            Image(systemName: "creditcard.fill")
                                .accessibilityLabel("Credit card")
                        }

                        if let number = transaction.installmentNumber,
                           let count = transaction.totalInstallments,
                           count > 1 {
                            Text("\(number)/\(count)")
                        }
                    }

                    if SpendingClassification.classify(transaction) == .fixedOrRecurring {
                        Image(systemName: "repeat")
                            .accessibilityLabel("Fixed or recurring transaction")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if let invoiceDueDate = transaction.invoiceDueDate {
                    Text("Purchased \(transaction.date, format: .dateTime.day().month()) • Invoice due \(invoiceDueDate, format: .dateTime.day().month())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(transaction.date, format: .dateTime.day().month().year())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(signedAmount)
                .fontWeight(.semibold)
                .foregroundStyle(transaction.type == .income ? .green : .red)
        }
        .accessibilityElement(children: .combine)
    }
}
