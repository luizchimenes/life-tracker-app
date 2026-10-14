import SwiftUI

enum CategoryColorName: String, CaseIterable, Identifiable {
    case red
    case orange
    case yellow
    case green
    case mint
    case teal
    case blue
    case indigo
    case purple
    case pink
    case gray
    case brown

    var id: Self { self }

    var color: Color {
        switch self {
        case .red:
            .red
        case .orange:
            .orange
        case .yellow:
            .yellow
        case .green:
            .green
        case .mint:
            .mint
        case .teal:
            .teal
        case .blue:
            .blue
        case .indigo:
            .indigo
        case .purple:
            .purple
        case .pink:
            .pink
        case .gray:
            .gray
        case .brown:
            .brown
        }
    }
}

extension Color {
    static func category(named name: String) -> Color {
        CategoryColorName(rawValue: name)?.color ?? .accentColor
    }
}
