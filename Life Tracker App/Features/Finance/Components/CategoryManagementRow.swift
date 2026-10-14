import SwiftUI

struct CategoryManagementRow: View {
    let category: TransactionCategory

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(
                iconName: category.iconName,
                colorName: category.colorName
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(category.displayName())
                    .font(.headline)

                Text(category.type.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if category.isDefault {
                Text("Built-in")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(.rect)
    }
}
