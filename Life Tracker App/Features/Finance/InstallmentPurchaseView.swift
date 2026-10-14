import SwiftUI

struct InstallmentPurchaseView: View {
    let summary: InstallmentPurchaseSummary

    private let currency = Decimal.FormatStyle.Currency(code: "BRL")
        .locale(AppLocalization.selectedLocale)

    var body: some View {
        List {
            Section("Purchase") {
                LabeledContent("Name", value: summary.title)
                LabeledContent("Original Purchase Total", value: summary.originalTotal.formatted(currency))
                LabeledContent("Installments") {
                    Text("\(summary.totalInstallments)× \(summary.standardInstallmentAmount.formatted(currency))")
                }
                if let currentInstallment = summary.currentInstallment {
                    LabeledContent("Current Installment") {
                        Text("\(currentInstallment) of \(summary.totalInstallments)")
                    }
                }
                LabeledContent("Accounted", value: summary.accountedAmount.formatted(currency))
                LabeledContent("Remaining") {
                    Text("\(summary.remainingInstallments) installments • \(summary.remainingAmount.formatted(currency)) committed")
                }
                if let finalDate = summary.finalInstallmentDate {
                    LabeledContent("Final Installment") {
                        Text(finalDate, format: .dateTime.month(.wide).year())
                    }
                }
            }

            Section("Installment Schedule") {
                ForEach(summary.installments) { transaction in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("\(transaction.installmentNumber ?? 1)/\(transaction.totalInstallments ?? 1)")
                                .fontWeight(.semibold)
                            Spacer()
                            Text(transaction.amount.formatted(currency))
                        }
                        HStack {
                            Text("Invoice due \(transaction.invoiceDueDate ?? transaction.effectiveFinancialDate, format: .dateTime.day().month().year())")
                            Spacer()
                            if let invoice = transaction.creditCardInvoice {
                                Text(invoice.effectiveStatus().displayName)
                            } else {
                                Text("Scheduled")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Installment Purchase")
    }
}
