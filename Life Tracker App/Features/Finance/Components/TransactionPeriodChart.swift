import Charts
import SwiftUI

struct TransactionPeriodChart: View {
    let periods: [TransactionPeriodSummary]
    @Binding var selectedCycleStart: Date?

    /// Raw x value written by a tap; resolved to a cycle and cleared at once so
    /// tapping the same column again still registers.
    @State private var tappedDate: Date?

    var body: some View {
        Chart {
            ForEach(periods) { period in
                BarMark(
                    x: .value("Cycle", period.cycle.start, unit: .month),
                    y: .value("Expenses", period.expenses)
                )
                .foregroundStyle(by: .value("Flow", AppLocalization.string("Expenses")))
                .opacity(opacity(for: period))

                BarMark(
                    x: .value("Cycle", period.cycle.start, unit: .month),
                    y: .value("Investments", period.investments)
                )
                .foregroundStyle(by: .value("Flow", AppLocalization.string("Investments")))
                .opacity(opacity(for: period))
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
        // A single tap selects; the default selection gesture needs a press and hold.
        .chartXSelection(value: $tappedDate)
        .chartGesture { proxy in
            SpatialTapGesture()
                .onEnded { proxy.selectXValue(at: $0.location.x) }
        }
        .onChange(of: tappedDate) {
            guard let tappedDate else { return }
            if let period = TransactionPeriodSummary.period(atChartDate: tappedDate, in: periods) {
                selectedCycleStart = period.cycle.start
            }
            self.tappedDate = nil
        }
        .sensoryFeedback(.selection, trigger: selectedCycleStart)
        .frame(height: 190)
        .accessibilityLabel("Expenses and investments by financial cycle")
    }

    private func opacity(for period: TransactionPeriodSummary) -> Double {
        guard let selectedCycleStart else { return 1 }
        return Calendar.current.isDate(period.cycle.start, inSameDayAs: selectedCycleStart) ? 1 : 0.35
    }
}
