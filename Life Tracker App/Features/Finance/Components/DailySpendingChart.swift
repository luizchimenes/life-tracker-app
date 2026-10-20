import Charts
import SwiftUI

struct DailySpendingChart: View {
    let spending: [DailySpendingData]

    @State private var selectedDate: Date?
    /// Raw x value written by a tap; resolved to a day and cleared at once.
    @State private var tappedDate: Date?

    private let currencyFormat = Decimal.FormatStyle.Currency(code: "BRL")
        .locale(AppLocalization.selectedLocale)

    private var selectedSpending: DailySpendingData? {
        guard let selectedDate else {
            return nil
        }

        return spending.first {
            Calendar.current.isDate($0.date, inSameDayAs: selectedDate)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Chart(spending) { item in
                BarMark(
                    x: .value("Day", item.date, unit: .day),
                    y: .value(
                        "Expenses",
                        NSDecimalNumber(decimal: item.amount).doubleValue
                    )
                )
                .foregroundStyle(.tint)
                .opacity(
                    selectedSpending == nil
                        || selectedSpending?.id == item.id ? 1 : 0.45
                )
            }
            .frame(height: 240)
            // A single tap selects (or deselects) a day; the default selection
            // gesture needs a press and hold.
            .chartXSelection(value: $tappedDate)
            .chartGesture { proxy in
                SpatialTapGesture()
                    .onEnded { proxy.selectXValue(at: $0.location.x) }
            }
            .onChange(of: tappedDate) {
                guard let tappedDate else { return }
                let day = DailySpendingData.day(atChartDate: tappedDate, in: spending)
                selectedDate = day?.id == selectedSpending?.id ? nil : day?.date
                self.tappedDate = nil
            }
            .sensoryFeedback(.selection, trigger: selectedDate)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 5)) {
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.day())
                }
            }
            .chartYAxis {
                AxisMarks(
                    format: Decimal.FormatStyle.Currency(code: "BRL")
                        .locale(AppLocalization.selectedLocale)
                        .precision(.fractionLength(0)),
                    values: .automatic(desiredCount: 4)
                )
            }
            .accessibilityLabel("Daily spending")

            if let selectedSpending {
                HStack {
                    Text(
                        selectedSpending.date,
                        format: .dateTime.day().month(.wide)
                    )

                    Spacer()

                    Text(selectedSpending.amount.formatted(currencyFormat))
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
            } else {
                Text("Select a bar to see that day’s spending.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
