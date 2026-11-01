import SwiftUI

/// Reorder Home sections by dragging and turn them on or off. Changes are
/// saved at once and Home follows them live.
struct HomeCustomizationView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(HomeLayout.orderKey) private var storedOrder = ""
    @AppStorage(HomeLayout.hiddenKey) private var storedHidden = ""

    private var layout: HomeLayout {
        HomeLayout(storedOrder: storedOrder, storedHidden: storedHidden)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(layout.order) { section in
                        row(for: section)
                    }
                    .onMove { source, destination in
                        update { $0.move(fromOffsets: source, toOffset: destination) }
                    }
                } header: {
                    Text("Show on Home")
                } footer: {
                    Text("Drag to change the order. Hiding a section only removes it from Home; its data stays in its tab.")
                }

                Section {
                    Button("Restore Default Layout") {
                        update { $0 = .default }
                    }
                    .disabled(layout.isDefault)
                }
            }
            // Always editing, so the drag handles are visible.
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Customize Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(for section: HomeSection) -> some View {
        let isVisible = layout.isVisible(section)
        return Toggle(isOn: Binding(
            get: { isVisible },
            set: { visible in update { $0.setVisible(visible, for: section) } }
        )) {
            Label {
                Text(section.title)
            } icon: {
                Image(systemName: section.systemImage)
            }
            .foregroundStyle(isVisible ? .primary : .secondary)
        }
        .accessibilityAction(named: "Move Up") { update { $0.move(section, by: -1) } }
        .accessibilityAction(named: "Move Down") { update { $0.move(section, by: 1) } }
    }

    private func update(_ change: (inout HomeLayout) -> Void) {
        var layout = self.layout
        change(&layout)
        storedOrder = layout.storedOrder
        storedHidden = layout.storedHidden
    }
}

#Preview {
    HomeCustomizationView()
}
