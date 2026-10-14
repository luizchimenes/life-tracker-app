import Charts
import SwiftUI

struct SpendingByCategoryChart: View {
    let categories: [CategorySpendingData]
    let totalExpenses: Decimal

    private let currencyFormat = Decimal.FormatStyle.Currency(code: "BRL")
        .locale(AppLocalization.selectedLocale)

    var body: some View {
        VStack(spacing: 16) {
            Chart(categories) { category in
                SectorMark(
                    angle: .value(
                        "Amount",
                        NSDecimalNumber(decimal: category.amount).doubleValue
                    ),
                    innerRadius: .ratio(0.62),
                    angularInset: 1.5
                )
                .cornerRadius(3)
                .foregroundStyle(
                    Color.category(named: category.colorName)
                )
            }
            .frame(height: 240)
            .chartBackground { _ in
                VStack(spacing: 2) {
                    Text("Spent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(totalExpenses.formatted(currencyFormat))
                        .font(.headline)
                }
            }
            .accessibilityLabel("Spending by category")

            VStack(spacing: 10) {
                ForEach(categories) { category in
                    HStack(spacing: 10) {
                        CategoryIcon(
                            iconName: category.iconName,
                            colorName: category.colorName,
                            size: .body,
                            width: 22
                        )

                        Text(category.name)

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(category.amount.formatted(currencyFormat))
                                .fontWeight(.medium)

                            Text(
                                category.percentage(of: totalExpenses),
                                format: .percent.precision(.fractionLength(0))
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
