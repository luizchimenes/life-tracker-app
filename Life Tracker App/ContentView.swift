import SwiftData
import SwiftUI

struct ContentView: View {
    @AppStorage(AppLanguage.storageKey) private var languageRawValue = AppLanguage.system.rawValue
    @State private var selectedTab = AppTab.home
    @State private var showsAppSettings = false

    private var selectedLocale: Locale {
        (AppLanguage(rawValue: languageRawValue) ?? .system).locale
    }

    var body: some View {
        // Rebuilding the tab tree on language change refreshes text that is
        // resolved outside SwiftUI views (reports, insights, formatted values).
        // Settings and tab selection live above it so they survive the rebuild.
        AppTabView(selection: $selectedTab)
            .id(languageRawValue)
            .environment(\.presentAppSettings, PresentAppSettingsAction { showsAppSettings = true })
            .sheet(isPresented: $showsAppSettings) {
                AppSettingsView()
                    .environment(\.locale, selectedLocale)
            }
            .environment(\.locale, selectedLocale)
    }
}

#Preview {
    ContentView()
        .modelContainer(LifeTrackerPersistence.previewContainer())
}
