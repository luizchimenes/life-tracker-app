import SwiftUI

struct CategoryIcon: View {
    let iconName: String
    let colorName: String
    var size: Font = .title3
    var width: CGFloat = 28

    var body: some View {
        Image(systemName: iconName)
            .font(size)
            .foregroundStyle(Color.category(named: colorName))
            .frame(width: width)
            .accessibilityHidden(true)
    }
}
