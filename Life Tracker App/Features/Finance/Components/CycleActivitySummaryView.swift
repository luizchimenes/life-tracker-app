import SwiftUI

/// Compact current-cycle figures: what was spent, what is expected by the end
/// of the cycle, and what was invested.
struct CycleActivitySummaryView: View {
    let projection: MonthlyFinanceProjection

    private let currencyFormat = Decimal.FormatStyle.Currency(code: "BRL")
        .locale(AppLocalization.selectedLocale)

    var body: some View {
        VStack(spacing: 10) {
            row("Actual Spending", projection.actualExpenses)
            row("Projected Spending", projection.projectedExpenses)
            row("Invested", projection.projectedInvestments)
        }
        .padding(.vertical, 4)
    }

    private func row(_ title: LocalizedStringKey, _ amount: Decimal) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(amount.formatted(currencyFormat))
                .fontWeight(.semibold)
        }
    }
}
