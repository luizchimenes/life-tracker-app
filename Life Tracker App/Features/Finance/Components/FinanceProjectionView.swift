import SwiftUI

struct FinanceProjectionView: View {
    let projection: MonthlyFinanceProjection
    let monthlyBudget: Decimal?

    private let currencyFormat = Decimal.FormatStyle.Currency(code: "BRL")
        .locale(AppLocalization.selectedLocale)

    var body: some View {
        VStack(spacing: 10) {
            valueRow(
                title: "Actual spending",
                amount: projection.actualExpenses
            )
            valueRow(
                title: "Projected spending",
                amount: projection.projectedExpenses
            )
            valueRow(
                title: "Scheduled / estimated still due",
                amount: projection.pendingRecurringExpenses + projection.pendingFixedBillExpenses
            )
            valueRow(
                title: "Projected balance",
                amount: projection.projectedBalance
            )

            let unknownCount = projection.pendingFixedBillOccurrences.count {
                $0.fixedBill.estimatedAmount == nil
            }
            if unknownCount > 0 {
                Text("\(unknownCount) pending variable bill(s) have no estimate and are excluded from the projected amount.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let monthlyBudget {
                Divider()

                let remaining = projection.projectedBudgetRemaining(
                    monthlyBudget: monthlyBudget
                )

                valueRow(
                    title: remaining >= 0
                        ? "Projected budget remaining"
                        : "Projected over budget",
                    amount: abs(remaining),
                    tint: remaining >= 0 ? .primary : .red
                )

                if remaining < 0 {
                    Text("Current recurring commitments are projected to exceed your financial cycle budget.")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func valueRow(
        title: LocalizedStringKey,
        amount: Decimal,
        tint: Color = .primary
    ) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)

            Spacer()

            Text(amount.formatted(currencyFormat))
                .fontWeight(.semibold)
                .foregroundStyle(tint)
        }
    }
}
