import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case portugueseBrazil

    static let storageKey = "appLanguage"

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .system: "System"
        case .english: "English"
        case .portugueseBrazil: "Português (Brasil)"
        }
    }

    var locale: Locale {
        switch self {
        case .system: .autoupdatingCurrent
        case .english: Locale(identifier: "en")
        case .portugueseBrazil: Locale(identifier: "pt-BR")
        }
    }
}

enum AppLocalization {
    static var selectedLocale: Locale {
        let storedValue = UserDefaults.standard.string(
            forKey: AppLanguage.storageKey
        )
        return (storedValue.flatMap(AppLanguage.init(rawValue:)) ?? .system).locale
    }

    static func string(_ resource: LocalizedStringResource) -> String {
        var localizedResource = resource
        localizedResource.locale = selectedLocale
        return String(localized: localizedResource)
    }
}

/// Presents App Settings from the root, outside the subtree that is rebuilt
/// when the language changes, so the sheet stays open while switching.
struct PresentAppSettingsAction: Equatable {
    private let action: () -> Void

    init(_ action: @escaping () -> Void = {}) {
        self.action = action
    }

    func callAsFunction() {
        action()
    }

    // The action always targets the same root state, so instances are interchangeable.
    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

extension EnvironmentValues {
    @Entry var presentAppSettings = PresentAppSettingsAction()
}
