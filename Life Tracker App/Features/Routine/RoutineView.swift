import SwiftUI

struct RoutineView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    PlaceholderCard(title: "Habits", value: "Your daily habits will appear here", systemImage: "repeat.circle", tint: .blue)
                    PlaceholderCard(title: "Tasks", value: "Your tasks will appear here", systemImage: "checklist", tint: .orange)
                }
                .padding()
            }
            .navigationTitle("Routine")
        }
    }
}

#Preview {
    RoutineView()
}
