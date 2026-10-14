import SwiftUI

struct AssistantView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                Image(systemName: "sparkles")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)

                VStack(spacing: 8) {
                    Text("LifeTracker Assistant")
                        .font(.title2.bold())

                    Text("Ask about your finances, habits, and tasks here in a future update.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 12) {
                    Text("Message")
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.tint)
                }
                .padding()
                .background(.background.secondary, in: .rect(cornerRadius: 20))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Message field, coming soon")
            }
            .padding()
            .navigationTitle("Assistant")
        }
    }
}

#Preview {
    AssistantView()
}
