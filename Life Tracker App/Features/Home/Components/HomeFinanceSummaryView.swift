import SwiftUI

/// Compact Home version of Finance: same `FinanceOverview` values, no
/// independent calculations.
struct HomeFinanceSummaryView: View {
    let overview: FinanceOverview

    private let currencyFormat = Decimal.FormatStyle.Currency(code: "BRL")
        .locale(AppLocalization.selectedLocale)

    var body: some View {
        VStack(spacing: 12) {
            SafeToSpendView(safeToSpend: overview.safeToSpend, prominent: false)

            Divider()

            valueRow(title: "Actual Spent", amount: overview.projection.actualExpenses)
            valueRow(title: "Projected Spending", amount: overview.projection.projectedExpenses)
            valueRow(title: "Invested", amount: overview.projection.projectedInvestments)
        }
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 16))
    }

    private func valueRow(
        title: LocalizedStringKey,
        amount: Decimal
    ) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(amount.formatted(currencyFormat))
                .fontWeight(.semibold)
        }
    }
}

/// Bills to Pay counts and total, plus the next invoice to close.
struct HomeBillsSummaryView: View {
    let bills: BillsToPaySummary

    private let currencyFormat = Decimal.FormatStyle.Currency(code: "BRL")
        .locale(AppLocalization.selectedLocale)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if bills.pendingCount > 0 {
                BillsToPaySummaryView(bills: bills)
            } else {
                Text("Nothing left to pay")
                    .foregroundStyle(.secondary)
            }

            if let next = bills.upcomingInvoices.first {
                Divider()
                Text("Next invoice: \(next.invoice.creditCard.name) • \(next.total.formatted(currencyFormat)) • closes \(next.invoice.closingDate, format: .dateTime.month(.abbreviated).day())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 16))
    }
}
