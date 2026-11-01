import Foundation

/// A section the user can reorder or hide on Home. Raw values are stored in
/// UserDefaults, so they must never change; add new cases with a new ID.
nonisolated enum HomeSection: String, CaseIterable, Identifiable, Sendable {
    case finance
    case billsToPay
    case recentActivity
    case habits

    var id: Self { self }

    /// Default order is the declaration order. A section added later is
    /// appended to customized layouts, so declare it at the end.
    static let defaultOrder = allCases

    var title: LocalizedStringResource {
        switch self {
        case .finance: "Finance This Cycle"
        case .billsToPay: "Bills to Pay"
        case .recentActivity: "Recent Activity"
        case .habits: "Today's Habits"
        }
    }

    var systemImage: String {
        switch self {
        case .finance: "chart.pie"
        case .billsToPay: "calendar.badge.clock"
        case .recentActivity: "clock.arrow.circlepath"
        case .habits: "checkmark.circle"
        }
    }
}

/// Home section order and visibility. A UI preference only: changing it never
/// touches Finance or Habits records.
nonisolated struct HomeLayout: Equatable, Sendable {
    static let orderKey = "homeSectionOrder"
    static let hiddenKey = "homeHiddenSections"

    /// Every supported section, exactly once.
    private(set) var order: [HomeSection]
    private(set) var hidden: Set<HomeSection>

    static let `default` = HomeLayout(order: HomeSection.defaultOrder, hidden: [])

    init(order: [HomeSection], hidden: Set<HomeSection>) {
        self.order = Self.normalized(order.map(\.rawValue), supported: HomeSection.defaultOrder.map(\.rawValue))
            .compactMap(HomeSection.init(rawValue:))
        self.hidden = hidden
    }

    /// Reads the stored strings. Unknown, duplicate or malformed values are
    /// ignored and missing sections are appended, so this never fails.
    init(storedOrder: String, storedHidden: String) {
        self.init(
            order: Self.identifiers(in: storedOrder).compactMap(HomeSection.init(rawValue:)),
            hidden: Set(Self.identifiers(in: storedHidden).compactMap(HomeSection.init(rawValue:)))
        )
    }

    var storedOrder: String { order.map(\.rawValue).joined(separator: ",") }
    var storedHidden: String { order.filter(hidden.contains).map(\.rawValue).joined(separator: ",") }

    var visibleSections: [HomeSection] { order.filter { !hidden.contains($0) } }
    var isDefault: Bool { self == .default }

    func isVisible(_ section: HomeSection) -> Bool { !hidden.contains(section) }

    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        // Same semantics as `Array.move(fromOffsets:toOffset:)` in SwiftUI.
        let moving = source.sorted().map { order[$0] }
        let before = order[..<min(destination, order.count)].enumerated().filter { !source.contains($0.offset) }.count
        order.removeAll { moving.contains($0) }
        order.insert(contentsOf: moving, at: before)
    }

    /// Moves a section one place up (-1) or down (+1); out of range does nothing.
    mutating func move(_ section: HomeSection, by step: Int) {
        guard let index = order.firstIndex(of: section), order.indices.contains(index + step) else { return }
        order.swapAt(index, index + step)
    }

    mutating func setVisible(_ visible: Bool, for section: HomeSection) {
        if visible {
            hidden.remove(section)
        } else {
            hidden.insert(section)
        }
    }

    /// Saved IDs that are still supported, in saved order and without
    /// duplicates, followed by supported IDs the saved order did not have
    /// (sections added in a newer version), in their default order.
    static func normalized(_ saved: [String], supported: [String]) -> [String] {
        var result: [String] = []
        for id in saved where supported.contains(id) && !result.contains(id) {
            result.append(id)
        }
        return result + supported.filter { !result.contains($0) }
    }

    static func identifiers(in stored: String) -> [String] {
        stored.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

/// Loads and saves the layout. Tests pass their own `UserDefaults` suite.
nonisolated struct HomeLayoutPreferences {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> HomeLayout {
        // `string(forKey:)` is nil for a value of another type, so old or
        // malformed preferences fall back to the default.
        HomeLayout(
            storedOrder: defaults.string(forKey: HomeLayout.orderKey) ?? "",
            storedHidden: defaults.string(forKey: HomeLayout.hiddenKey) ?? ""
        )
    }

    func save(_ layout: HomeLayout) {
        defaults.set(layout.storedOrder, forKey: HomeLayout.orderKey)
        defaults.set(layout.storedHidden, forKey: HomeLayout.hiddenKey)
    }
}
