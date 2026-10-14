import SwiftUI

struct FinanceSummaryView: View {
    let income: Decimal
    let expenses: Decimal
    let balance: Decimal

    var body: some View {
        VStack(spacing: 12) {
            SummaryRow(title: "Income", amount: income, tint: .green)
            SummaryRow(title: "Expenses", amount: expenses, tint: .red)
            Divider()
            SummaryRow(
                title: "Balance",
                amount: balance,
                tint: balance < 0 ? .red : .primary
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
