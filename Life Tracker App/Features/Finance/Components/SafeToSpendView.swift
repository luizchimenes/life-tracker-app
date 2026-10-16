import SwiftUI

struct SafeToSpendView: View {
    let safeToSpend: SafeToSpend
    var prominent = true

    private let currencyFormat = Decimal.FormatStyle.Currency(code: "BRL")
        .locale(AppLocalization.selectedLocale)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Safe to Spend")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(safeToSpend.displayAmount.formatted(currencyFormat))
                .font(prominent ? .largeTitle.bold() : .title.bold())
                .foregroundStyle(safeToSpend.isShortfall ? .red : .primary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            if safeToSpend.isShortfall {
                Text(shortfallText)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            } else {
                Text("\(safeToSpend.perDay.formatted(currencyFormat)) per day • \(daysRemainingText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Planning estimate for this financial cycle, not your bank balance or card limit.")
    }

    private var daysRemainingText: LocalizedStringResource {
        "\(safeToSpend.daysRemaining) days remaining"
    }

    private var shortfallText: LocalizedStringResource {
        let amount = safeToSpend.shortfall.formatted(currencyFormat)
        return switch safeToSpend.constraint {
        case .budget: "\(amount) over the projected budget"
        case .cash: "\(amount) over what's projected to be available"
        }
    }
}
