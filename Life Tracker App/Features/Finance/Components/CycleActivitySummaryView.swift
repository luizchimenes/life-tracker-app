import SwiftUI

/// Current-cycle spending at a glance: actual spending first, then what is
/// expected by the end of the cycle, what was invested and the configured
/// fixed commitments.
struct CycleActivitySummaryView: View {
    let projection: MonthlyFinanceProjection
    var commitments: FixedCommitmentSummary?
    var prominent = true

    private let currencyFormat = Decimal.FormatStyle.Currency(code: "BRL")
        .locale(AppLocalization.selectedLocale)

    var body: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Actual Spending")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(projection.actualExpenses.formatted(currencyFormat))
                    .font(prominent ? .largeTitle.bold() : .title.bold())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Divider()

            row("Projected Spending", Text(projection.projectedExpenses.formatted(currencyFormat)))
            row("Invested", Text(projection.projectedInvestments.formatted(currencyFormat)))

            if let commitments, !commitments.isEmpty {
                row(
                    "Fixed Commitments",
                    Text(commitments.includesEstimates
                        ? "~ \(commitments.total.formatted(currencyFormat))"
                        : "\(commitments.total.formatted(currencyFormat))")
                )
            }
        }
        .padding(.vertical, 4)
    }

    private func row(_ title: LocalizedStringKey, _ value: Text) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            value
                .fontWeight(.semibold)
        }
        .accessibilityElement(children: .combine)
    }
}
