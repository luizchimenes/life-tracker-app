import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppLanguage.storageKey) private var languageRawValue = AppLanguage.system.rawValue
    @State private var selectedTab = AppTab.home
    @State private var showsAppSettings = false
    /// Bumped after a restore so every screen is rebuilt from the new data.
    @State private var dataGeneration = 0
    @State private var isRestoringData = false

    private var selectedLocale: Locale {
        (AppLanguage(rawValue: languageRawValue) ?? .system).locale
    }

    var body: some View {
        // Rebuilding the tab tree on language change refreshes text that is
        // resolved outside SwiftUI views (reports, insights, formatted values).
        // Settings and tab selection live above it so they survive the rebuild.
        // A restore also rebuilds the tree, so no screen keeps a replaced record.
        Group {
            if isRestoringData {
                ProgressView("Restoring backup…")
            } else {
                AppTabView(selection: $selectedTab)
                    .id("\(languageRawValue)-\(dataGeneration)")
            }
        }
        .environment(\.presentAppSettings, PresentAppSettingsAction { showsAppSettings = true })
        .sheet(isPresented: $showsAppSettings) {
            AppSettingsView()
                .environment(\.locale, selectedLocale)
                .environment(\.restoreAppData, RestoreAppDataAction(restore))
        }
        .environment(\.locale, selectedLocale)
    }

    /// Takes the screens down, replaces the data, then rebuilds them.
    private func restore(_ backup: LifeTrackerBackup) async throws -> BackupRestorer.Result {
        isRestoringData = true
        defer {
            dataGeneration += 1
            isRestoringData = false
        }
        // Let the current screens disappear before their records are replaced.
        try? await Task.sleep(for: .milliseconds(300))
        let result = try BackupRestorer.restore(backup, into: modelContext)
        if let language = backup.preferences.appLanguage, AppLanguage(rawValue: language) != nil {
            languageRawValue = language
        }
        return result
    }
}

#Preview {
    ContentView()
        .modelContainer(LifeTrackerPersistence.previewContainer())
}
