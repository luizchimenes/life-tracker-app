import SwiftUI

struct FixedCommitmentsSummaryView: View {
    let snapshot: FixedBillCycleSnapshot

    private let currencyFormat = Decimal.FormatStyle.Currency(code: "BRL")
        .locale(AppLocalization.selectedLocale)

    var body: some View {
        VStack(spacing: 10) {
            summaryRow(
                title: "Paid",
                value: "\(snapshot.paidCount) of \(snapshot.occurrences.count)"
            )
            summaryRow(
                title: "Paid amount",
                value: "\(snapshot.paidAmount.formatted(currencyFormat))"
            )
            summaryRow(
                title: "Still pending",
                value: "\(snapshot.pendingCount) bills"
            )
            summaryRow(
                title: snapshot.pendingWithoutEstimateCount > 0
                    ? "Known estimate"
                    : "Estimated remaining",
                value: estimatedRemainingText
            )
        }
    }

    private func summaryRow(
        title: LocalizedStringResource,
        value: LocalizedStringResource
    ) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
    }

    private var estimatedRemainingText: LocalizedStringResource {
        if snapshot.pendingCount == snapshot.pendingWithoutEstimateCount,
           snapshot.pendingCount > 0 {
            return "Not estimated"
        }
        return "~ \(snapshot.estimatedRemaining.formatted(currencyFormat))"
    }
}
