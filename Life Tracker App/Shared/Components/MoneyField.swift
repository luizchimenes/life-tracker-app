import SwiftUI

struct MoneyField: View {
    let title: LocalizedStringResource
    @Binding var amount: Decimal?

    init(
        _ title: LocalizedStringResource = "Amount",
        amount: Binding<Decimal?>
    ) {
        self.title = title
        _amount = amount
    }

    init(
        _ title: LocalizedStringResource = "Amount",
        amount: Binding<Decimal>
    ) {
        self.title = title
        _amount = Binding(
            get: { amount.wrappedValue == 0 ? nil : amount.wrappedValue },
            set: { amount.wrappedValue = max($0 ?? 0, 0) }
        )
    }

    var body: some View {
        TextField(
            title,
            value: $amount,
            format: .currency(code: "BRL")
                .locale(AppLocalization.selectedLocale)
                .precision(.fractionLength(2))
        )
#if os(iOS)
        .keyboardType(.decimalPad)
#endif
    }
}
