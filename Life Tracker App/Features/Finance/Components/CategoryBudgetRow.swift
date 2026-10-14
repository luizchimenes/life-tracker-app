import SwiftUI

struct CategoryBudgetRow: View {
    let budget: CategoryBudget
    let amountSpent: Decimal
    let pendingRecurringAmount: Decimal

    private let currencyFormat = Decimal.FormatStyle.Currency(code: "BRL")
        .locale(AppLocalization.selectedLocale)

    private var remaining: Decimal {
        budget.monthlyLimit - amountSpent
    }

    private var projectedAmount: Decimal {
        amountSpent + pendingRecurringAmount
    }

    private var projectedRemaining: Decimal {
        budget.monthlyLimit - projectedAmount
    }

    private var progress: Double {
        guard budget.monthlyLimit > 0 else {
            return 0
        }

        return NSDecimalNumber(decimal: amountSpent / budget.monthlyLimit).doubleValue
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

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CategoryIcon(
                iconName: budget.category.iconName,
                colorName: budget.category.colorName
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(budget.category.displayName())
                    .font(.headline)

                if pendingRecurringAmount > 0 {
                    Text("\(amountSpent.formatted(currencyFormat)) spent")
                        .font(.subheadline)

                    Text("\(pendingRecurringAmount.formatted(currencyFormat)) still scheduled")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Projected: \(projectedAmount.formatted(currencyFormat)) / \(budget.monthlyLimit.formatted(currencyFormat))")
                        .font(.caption)

                    if projectedRemaining >= 0 {
                        Text("\(projectedRemaining.formatted(currencyFormat)) projected remaining")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\((-projectedRemaining).formatted(currencyFormat)) projected over budget")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } else {
                    Text("\(amountSpent.formatted(currencyFormat)) of \(budget.monthlyLimit.formatted(currencyFormat))")
                        .font(.subheadline)

                    if remaining >= 0 {
                        Text("\(remaining.formatted(currencyFormat)) remaining")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\((-remaining).formatted(currencyFormat)) over budget")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                ProgressView(value: min(max(progress, 0), 1))
                    .tint(statusTint)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
