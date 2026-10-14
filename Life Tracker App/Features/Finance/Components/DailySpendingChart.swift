import Charts
import SwiftUI

struct DailySpendingChart: View {
    let spending: [DailySpendingData]

    @State private var selectedDate: Date?

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
            .chartXSelection(value: $selectedDate)
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
