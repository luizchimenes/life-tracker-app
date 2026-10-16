import Charts
import SwiftUI

struct TransactionPeriodChart: View {
    let periods: [TransactionPeriodSummary]
    @Binding var selectedCycleStart: Date?

    var body: some View {
        Chart {
            ForEach(periods) { period in
                BarMark(
                    x: .value("Cycle", period.cycle.start, unit: .month),
                    y: .value("Expenses", period.expenses)
                )
                .foregroundStyle(by: .value("Flow", AppLocalization.string("Expenses")))

                BarMark(
                    x: .value("Cycle", period.cycle.start, unit: .month),
                    y: .value("Investments", period.investments)
                )
                .foregroundStyle(by: .value("Flow", AppLocalization.string("Investments")))
            }

            if let selectedCycleStart {
                RuleMark(x: .value("Selected Cycle", selectedCycleStart, unit: .month))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
        }
        .chartForegroundStyleScale([
                AppLocalization.string("Expenses"): Color.red,
                AppLocalization.string("Investments"): Color.indigo
        ])
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { value in
                AxisValueLabel(format: .dateTime.month(.abbreviated))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartXSelection(value: $selectedCycleStart)
        .frame(height: 190)
        .accessibilityLabel("Expenses and investments by financial cycle")
    }
}
