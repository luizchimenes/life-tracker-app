import SwiftUI

struct HomeFixedBillRow: View {
    let occurrence: FixedBillOccurrence

    var body: some View {
        HStack(spacing: 10) {
            CategoryIcon(
                iconName: occurrence.fixedBill.category.iconName,
                colorName: occurrence.fixedBill.category.colorName,
                size: .body,
                width: 24
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(occurrence.fixedBill.name)
                    .fontWeight(.medium)

                Text(dueText)
                    .font(.caption)
                    .foregroundStyle(occurrence.isOverdue() ? .red : .secondary)
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private var dueText: LocalizedStringResource {
        occurrence.isOverdue()
            ? "Overdue • Due \(occurrence.dueDate, format: .dateTime.month(.abbreviated).day())"
            : "Due \(occurrence.dueDate, format: .dateTime.month(.abbreviated).day())"
    }
}
