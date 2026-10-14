import SwiftUI

struct PlaceholderCard: View {
    let title: LocalizedStringKey
    let value: LocalizedStringKey
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 16))
    }
}

#Preview {
    PlaceholderCard(
        title: "Monthly balance",
        value: "No data yet",
        systemImage: "banknote",
        tint: .green
    )
    .padding()
}
