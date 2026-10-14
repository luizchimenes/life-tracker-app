import SwiftUI

struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var languageRawValue = AppLanguage.system.rawValue

    private var language: Binding<AppLanguage> {
        Binding(
            get: { AppLanguage(rawValue: languageRawValue) ?? .system },
            set: { languageRawValue = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("App Language", selection: language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.title).tag(language)
                        }
                    }
                } header: {
                    Text("Language")
                } footer: {
                    Text("System follows the language selected in iOS Settings.")
                }
            }
            .navigationTitle("App Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
