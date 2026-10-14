import SwiftData
import SwiftUI

@main
struct LifeTrackerApp: App {
    // Opening the store never deletes or resets it. If it fails, the app shows
    // the error instead of starting with an empty database.
    private let container = Result {
        try LifeTrackerPersistence.makeContainer()
    }

    var body: some Scene {
        WindowGroup {
            switch container {
            case .success(let container):
                ContentView()
                    .modelContainer(container)
            case .failure(let error):
                StoreUnavailableView(error: error)
            }
        }
    }
}
