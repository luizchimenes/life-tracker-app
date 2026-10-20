import SwiftUI

/// Compact Home version of Finance: same `FinanceOverview` values, no
/// independent calculations.
struct HomeFinanceSummaryView: View {
    let overview: FinanceOverview

    var body: some View {
        CycleActivitySummaryView(projection: overview.projection, prominent: false)
            .padding()
            .background(.background.secondary, in: .rect(cornerRadius: 16))
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
