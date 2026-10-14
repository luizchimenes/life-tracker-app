import SwiftUI

struct MonthlyBudgetSummaryView: View {
    let amountSpent: Decimal
    let budget: Decimal

    private let currencyFormat = Decimal.FormatStyle.Currency(code: "BRL")
        .locale(AppLocalization.selectedLocale)

    private var remaining: Decimal {
        budget - amountSpent
    }

    private var progress: Double {
        guard budget > 0 else {
            return 0
        }

        return NSDecimalNumber(decimal: amountSpent / budget).doubleValue
    }

    private var statusTint: Color {
        if progress >= 1 {
            return .red
        }

        if progress >= 0.8 {
            return .orange
        }

        return .accentColor
    }

    private var statusText: LocalizedStringKey {
        if progress >= 1 {
            return "Budget exceeded"
        }

        if progress >= 0.8 {
            return "Close to budget"
        }

        return "On track"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(amountSpent.formatted(currencyFormat)) of \(budget.formatted(currencyFormat))")
                .font(.headline)

            HStack {
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .fontWeight(.semibold)

                Text("used")
                    .foregroundStyle(.secondary)

                Spacer()

                Text(statusText)
                    .fontWeight(.medium)
                    .foregroundStyle(statusTint)
            }
            .font(.subheadline)

            if remaining >= 0 {
                Text("\(remaining.formatted(currencyFormat)) actual budget remaining")
                    .foregroundStyle(.secondary)
            } else {
                Text("\((-remaining).formatted(currencyFormat)) over budget")
                    .foregroundStyle(.red)
            }

            ProgressView(value: min(max(progress, 0), 1))
                .tint(statusTint)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
