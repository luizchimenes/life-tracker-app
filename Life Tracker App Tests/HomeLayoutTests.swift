import Foundation
import SwiftData
import Testing
@testable import Life_Tracker_App

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
}

/// A private UserDefaults suite, so tests never touch the real preferences.
private final class TestDefaults {
    let name = "HomeLayoutTests-\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: name)!
    }

    var preferences: HomeLayoutPreferences { HomeLayoutPreferences(defaults: defaults) }

    deinit {
        defaults.removePersistentDomain(forName: name)
    }
}

@Suite("Home layout")
struct HomeLayoutTests {
    @Test func defaultOrderIsFinanceFirstWithEverythingVisible() {
        let layout = TestDefaults().preferences.load()
        #expect(layout == .default)
        #expect(layout.order == [.finance, .billsToPay, .recentActivity, .habits])
        #expect(layout.visibleSections == layout.order)
        #expect(layout.isDefault)
    }

    @Test func movingHabitsAboveFinance() {
        var layout = HomeLayout.default
        layout.move(fromOffsets: [3], toOffset: 0)
        #expect(layout.order == [.habits, .finance, .billsToPay, .recentActivity])

        // Dragging down uses the List destination, which counts the moved row.
        layout.move(fromOffsets: [0], toOffset: 4)
        #expect(layout.order == HomeLayout.default.order)

        layout.move(.habits, by: -1)
        #expect(layout.order == [.finance, .billsToPay, .habits, .recentActivity])
        layout.move(.finance, by: -1)
        #expect(layout.order == [.finance, .billsToPay, .habits, .recentActivity])
    }

    @Test func customizedOrderIsSavedAndLoadedBack() {
        let store = TestDefaults()
        var layout = HomeLayout.default
        layout.move(fromOffsets: [3], toOffset: 0)
        store.preferences.save(layout)

        #expect(store.defaults.string(forKey: HomeLayout.orderKey) == "habits,finance,billsToPay,recentActivity")
        // A new launch reads the same order.
        #expect(HomeLayoutPreferences(defaults: store.defaults).load() == layout)
    }

    @Test func loadingASavedOrder() {
        let layout = HomeLayout(storedOrder: "recentActivity,habits,finance,billsToPay", storedHidden: "")
        #expect(layout.order == [.recentActivity, .habits, .finance, .billsToPay])
    }

    @Test func hidingAndShowingASection() {
        let store = TestDefaults()
        var layout = HomeLayout.default
        layout.setVisible(false, for: .finance)
        store.preferences.save(layout)

        let hidden = store.preferences.load()
        #expect(!hidden.isVisible(.finance))
        #expect(hidden.visibleSections == [.billsToPay, .recentActivity, .habits])
        // Hiding keeps its place in the order.
        #expect(hidden.order == HomeLayout.default.order)

        var shown = hidden
        shown.setVisible(true, for: .finance)
        store.preferences.save(shown)
        #expect(store.preferences.load().visibleSections == HomeLayout.default.order)
    }

    @Test func allSectionsHidden() {
        var layout = HomeLayout.default
        for section in HomeSection.allCases {
            layout.setVisible(false, for: section)
        }
        #expect(layout.visibleSections.isEmpty)
        #expect(layout.order.count == HomeSection.allCases.count)
    }

    @Test func restoringTheDefaultLayout() {
        let store = TestDefaults()
        var layout = HomeLayout.default
        layout.move(fromOffsets: [3], toOffset: 0)
        layout.setVisible(false, for: .recentActivity)
        store.preferences.save(layout)
        #expect(!store.preferences.load().isDefault)

        store.preferences.save(.default)
        #expect(store.preferences.load() == .default)
    }

    @Test func unknownAndMalformedIdentifiersAreIgnored() {
        let layout = HomeLayout(storedOrder: " habits ,, notes,FINANCE,💥,finance", storedHidden: "notes,,habits ")
        #expect(layout.order == [.habits, .finance, .billsToPay, .recentActivity])
        #expect(layout.hidden == [.habits])

        // A value of another type, as an older or broken version might leave.
        let store = TestDefaults()
        store.defaults.set(["habits"], forKey: HomeLayout.orderKey)
        store.defaults.set(42, forKey: HomeLayout.hiddenKey)
        #expect(store.preferences.load() == .default)
    }

    @Test func duplicateIdentifiersKeepTheFirstPosition() {
        let layout = HomeLayout(storedOrder: "habits,finance,habits,finance", storedHidden: "finance,finance")
        #expect(layout.order == [.habits, .finance, .billsToPay, .recentActivity])
        #expect(layout.storedHidden == "finance")
    }

    @Test func aNewSectionIsAppendedToACustomizedLayout() {
        // Tasks does not exist yet; the same rule will add it.
        let supported = ["finance", "billsToPay", "recentActivity", "habits", "tasks"]
        let saved = ["habits", "finance", "recentActivity", "billsToPay"]
        #expect(HomeLayout.normalized(saved, supported: supported) == ["habits", "finance", "recentActivity", "billsToPay", "tasks"])
        // A section removed in a later version drops out without moving the rest.
        #expect(HomeLayout.normalized(saved, supported: ["finance", "habits"]) == ["habits", "finance"])
        // Missing sections from today's app are appended too.
        #expect(HomeLayout(storedOrder: "habits", storedHidden: "").order == [.habits, .finance, .billsToPay, .recentActivity])
    }
}

@Suite("Home layout leaves data alone")
@MainActor
struct HomeLayoutDataTests {
    @Test func financeAndHabitsSummariesAreUnchanged() throws {
        let container = try LifeTrackerPersistence.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let food = TransactionCategory(name: "Food", iconName: "fork.knife", colorName: "orange", type: .expense)
        let salary = TransactionCategory(name: "Salary", iconName: "banknote.fill", colorName: "green", type: .income)
        context.insert(food)
        context.insert(salary)
        context.insert(Transaction(title: "Salary", amount: 5_000, date: day(2026, 10, 9), type: .income, category: salary))
        context.insert(Transaction(title: "Groceries", amount: Decimal(string: "120.35")!, date: day(2026, 10, 12), type: .expense, category: food, paymentMethod: .pix))
        let gym = try HabitService.create(name: "Gym", iconName: "dumbbell.fill", colorName: "blue", schedule: .everyDay, startDate: day(2026, 10, 1), in: context, now: day(2026, 10, 1), calendar: utc)
        try HabitService.setCompleted(gym, on: HabitDay(year: 2026, month: 10, day: 20), in: context, now: day(2026, 10, 20), calendar: utc)
        try context.save()

        func snapshot() throws -> [String] {
            let overview = FinanceOverview(
                transactions: try context.fetch(FetchDescriptor<Transaction>()),
                recurringTransactions: try context.fetch(FetchDescriptor<RecurringTransaction>()),
                fixedBillOccurrences: try context.fetch(FetchDescriptor<FixedBillOccurrence>()),
                creditCardInvoices: try context.fetch(FetchDescriptor<CreditCardInvoice>()),
                date: day(2026, 10, 20),
                calendar: utc
            )
            let habits = HabitsTodaySummary(habits: try context.fetch(FetchDescriptor<Habit>()), now: day(2026, 10, 20), calendar: utc)
            return [
                "\(overview.actual.income)", "\(overview.actual.expenses)", "\(overview.actual.balance)",
                "\(overview.bills.pendingCount)", "\(overview.daysRemaining)",
                "\(habits.completedCount)/\(habits.scheduledCount)",
                "\(try context.fetchCount(FetchDescriptor<Transaction>()))", "\(try context.fetchCount(FetchDescriptor<Habit>()))"
            ]
        }

        let before = try snapshot()
        #expect(before[0] == "5000" && before[1] == "120.35" && before[5] == "1/1")

        let store = TestDefaults()
        var layout = store.preferences.load()
        layout.move(fromOffsets: [3], toOffset: 0)
        for section in HomeSection.allCases {
            layout.setVisible(false, for: section)
        }
        store.preferences.save(layout)
        store.preferences.save(.default)

        #expect(try snapshot() == before)
        #expect(!context.hasChanges)
    }
}
