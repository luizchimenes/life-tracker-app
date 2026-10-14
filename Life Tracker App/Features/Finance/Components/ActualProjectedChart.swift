import Charts
import SwiftUI

struct ActualProjectedChart: View {
    let actualExpenses: Decimal
    let projectedExpenses: Decimal
    let monthlyBudget: Decimal?

    private struct Metric: Identifiable {
        let name: String
        let amount: Decimal
        let color: Color

        var id: String { name }
    }

    private let currencyFormat = Decimal.FormatStyle.Currency(code: "BRL")
        .locale(AppLocalization.selectedLocale)

    private var metrics: [Metric] {
        [
            Metric(
                name: AppLocalization.string("Actual"),
                amount: actualExpenses,
                color: .accentColor
            ),
            Metric(
                name: AppLocalization.string("Projected"),
                amount: projectedExpenses,
                color: projectedExceedsBudget ? .red : .orange
            )
        ]
    }

    private var projectedExceedsBudget: Bool {
        guard let monthlyBudget else {
            return false
        }

        return projectedExpenses > monthlyBudget
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Chart {
                ForEach(metrics) { metric in
                    BarMark(
                        x: .value("Amount", NSDecimalNumber(decimal: metric.amount).doubleValue),
                        y: .value("Type", metric.name)
                    )
                    .foregroundStyle(metric.color)
                    .annotation(position: .trailing) {
                        Text(metric.amount.formatted(currencyFormat))
                            .font(.caption)
                    }
                }

                if let monthlyBudget {
                    RuleMark(
                        x: .value(
                            "Financial Cycle Budget",
                            NSDecimalNumber(decimal: monthlyBudget).doubleValue
                        )
                    )
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Budget")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 150)
            .chartXAxis {
                AxisMarks(
                    format: Decimal.FormatStyle.Currency(code: "BRL")
                        .locale(AppLocalization.selectedLocale)
                        .precision(.fractionLength(0)),
                    values: .automatic(desiredCount: 4)
                )
            }
            .accessibilityLabel("Actual versus projected expenses")

            if let monthlyBudget {
                Text("Financial cycle budget: \(monthlyBudget.formatted(currencyFormat))")
                    .font(.subheadline)

                if projectedExceedsBudget {
                    Text("Projected spending exceeds the financial cycle budget.")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text("Projected spending remains within the financial cycle budget.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
