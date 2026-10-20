import SwiftUI

/// Configured cost of the active fixed bills, shown below their list.
struct FixedBillTotalView: View {
    let commitment: FixedBillCommitment

    private let currencyFormat = Decimal.FormatStyle.Currency(code: "BRL")
        .locale(AppLocalization.selectedLocale)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(commitment.includesEstimates ? "Estimated total" : "Total")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(commitment.includesEstimates
                    ? "~ \(commitment.total.formatted(currencyFormat))"
                    : "\(commitment.total.formatted(currencyFormat))")
                    .font(.title3.bold())
            }

            breakdownText
                .font(.caption)
                .foregroundStyle(.secondary)

            if commitment.unknownCount > 0 {
                Text("+ \(commitment.unknownCount) amounts still unknown")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var breakdownText: Text {
        let exact = Text("\(commitment.exactCount) fixed amounts")
        guard commitment.estimatedCount > 0 else {
            return exact
        }
        return Text("\(exact) + \(Text("\(commitment.estimatedCount) estimates"))")
    }
}

/// Configured cost of the active recurring expense rules, per cycle.
struct RecurringExpenseTotalView: View {
    let commitment: RecurringExpenseCommitment

    private let currencyFormat = Decimal.FormatStyle.Currency(code: "BRL")
        .locale(AppLocalization.selectedLocale)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Recurring total")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(commitment.total.formatted(currencyFormat)) / cycle")
                    .font(.title3.bold())
            }

            Text("\(commitment.activeCount) active recurring expenses")
                .font(.caption)
                .foregroundStyle(.secondary)

            if commitment.creditCardCount > 0 {
                Text("\(commitment.creditCardCount) charged to credit cards")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
