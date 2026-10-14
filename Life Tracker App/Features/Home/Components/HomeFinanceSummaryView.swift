import SwiftUI

struct HomeFinanceSummaryView: View {
    let balance: Decimal
    let expenses: Decimal
    let projectedExpenses: Decimal
    let monthlyBudget: Decimal?

    private let currencyFormat = Decimal.FormatStyle.Currency(code: "BRL")
        .locale(AppLocalization.selectedLocale)

    var body: some View {
        VStack(spacing: 12) {
            valueRow(title: "Balance", amount: balance)
            valueRow(title: "Actual Spent", amount: expenses)
            valueRow(title: "Projected Spending", amount: projectedExpenses)

            if let monthlyBudget {
                Divider()
                valueRow(
                    title: projectedExpenses <= monthlyBudget
                        ? "Projected Budget Remaining"
                        : "Projected Over Budget",
                    amount: abs(monthlyBudget - projectedExpenses)
                )
            }
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
