import SwiftUI

struct FinanceSummaryView: View {
    let income: Decimal
    let expenses: Decimal
    let investments: Decimal
    let balance: Decimal
    let availableAfterInvestments: Decimal

    var body: some View {
        VStack(spacing: 12) {
            SummaryRow(title: "Income", amount: income, tint: .green)
            SummaryRow(title: "Expenses", amount: expenses, tint: .red)
            SummaryRow(title: "Investments", amount: investments, tint: .indigo)
            Divider()
            SummaryRow(
                title: "Balance",
                amount: balance,
                tint: balance < 0 ? .red : .primary
            )
            SummaryRow(
                title: "Available After Investments",
                amount: availableAfterInvestments,
                tint: availableAfterInvestments < 0 ? .red : .primary
            )
        }
        .padding(.vertical, 4)
    }
}

private struct SummaryRow: View {
    let title: LocalizedStringKey
    let amount: Decimal
    let tint: Color

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)

            Spacer()

            Text(amount, format: .currency(code: "BRL").locale(AppLocalization.selectedLocale))
                .fontWeight(.semibold)
                .foregroundStyle(tint)
        }
    }
}
