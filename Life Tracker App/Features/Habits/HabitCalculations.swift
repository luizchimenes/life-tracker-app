import Foundation

/// A calendar day, independent of time and time zone. All habit logic works on
/// these, never on raw timestamps, and moves between days with calendar
/// arithmetic instead of fixed 24-hour steps.
nonisolated struct HabitDay: Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
    }

    /// Midday of the day, so a later time-zone change never moves it.
    func date(in calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .distantPast
    }

    func adding(days: Int, calendar: Calendar = .current) -> HabitDay {
        HabitDay(calendar.date(byAdding: .day, value: days, to: date(in: calendar)) ?? date(in: calendar), calendar: calendar)
    }

    /// 1 = Sunday … 7 = Saturday, as `Calendar` defines it.
    func weekday(calendar: Calendar = .current) -> Int {
        calendar.component(.weekday, from: date(in: calendar))
    }

    var key: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

/// Every day, or selected weekdays. A weekly schedule with no days is a pause
/// (used while a habit was archived) and is never scheduled.
nonisolated struct HabitSchedule: Equatable, Sendable {
    var type: HabitScheduleType
    var weekdays: Set<Int>

    static let everyDay = HabitSchedule(type: .daily, weekdays: [])
    static let paused = HabitSchedule(type: .weekly, weekdays: [])

    var isValid: Bool {
        type == .daily || !weekdays.isEmpty
    }

    func includes(_ day: HabitDay, calendar: Calendar = .current) -> Bool {
        switch type {
        case .daily: true
        case .weekly: weekdays.contains(day.weekday(calendar: calendar))
        }
    }

    static func encode(_ weekdays: Set<Int>) -> String {
        weekdays.sorted().map(String.init).joined(separator: ",")
    }

    static func decode(_ raw: String) -> Set<Int> {
        Set(raw.split(separator: ",").compactMap { Int($0) }.filter { (1...7).contains($0) })
    }
}

/// Immutable copy of one habit for calculations: built once per screen from
/// the model, then queried without touching SwiftData again.
nonisolated struct HabitSnapshot: Identifiable, Sendable {
    struct ScheduleEntry: Sendable {
        let from: HabitDay
        let schedule: HabitSchedule
    }

    let id: UUID
    let startDay: HabitDay
    /// Last day judged when archived.
    let endDay: HabitDay?
    /// Ascending by `from`.
    let timeline: [ScheduleEntry]
    let completedDays: Set<HabitDay>
    let calendar: Calendar

    init(
        id: UUID,
        startDay: HabitDay,
        endDay: HabitDay?,
        timeline: [ScheduleEntry],
        completedDays: Set<HabitDay>,
        calendar: Calendar = .current
    ) {
        self.id = id
        self.startDay = startDay
        self.endDay = endDay
        self.timeline = timeline.sorted { $0.from < $1.from }
        self.completedDays = completedDays
        self.calendar = calendar
    }

    /// The schedule in effect on `day`.
    func schedule(on day: HabitDay) -> HabitSchedule {
        timeline.last { $0.from <= day }?.schedule ?? timeline.first?.schedule ?? .everyDay
    }

    /// Scheduled on that day, whether past, today or future.
    func isScheduled(_ day: HabitDay) -> Bool {
        guard day >= startDay else { return false }
        if let endDay, day > endDay { return false }
        return schedule(on: day).includes(day, calendar: calendar)
    }

    func isCompleted(_ day: HabitDay) -> Bool {
        completedDays.contains(day)
    }
}

extension HabitSnapshot {
    @MainActor
    init(_ habit: Habit, calendar: Calendar = .current) {
        let startDay = HabitDay(habit.startDate, calendar: calendar)
        var timeline = habit.scheduleVersions.map {
            ScheduleEntry(from: HabitDay($0.effectiveFrom, calendar: calendar), schedule: $0.schedule)
        }
        if timeline.isEmpty {
            timeline = [ScheduleEntry(from: startDay, schedule: habit.schedule)]
        }
        self.init(
            id: habit.id,
            startDay: startDay,
            endDay: habit.isArchived ? habit.archivedAt.map { HabitDay($0, calendar: calendar) } : nil,
            timeline: timeline,
            completedDays: Set(habit.completions.map { HabitDay($0.day, calendar: calendar) }),
            calendar: calendar
        )
    }
}

/// Statistics for one habit as of `today`.
///
/// - Streaks count consecutive *scheduled* days; unscheduled days are skipped.
/// - A missed scheduled day breaks a streak; today does not until it is over.
/// - Days before the start, after archiving and in the future never count.
nonisolated struct HabitStatistics: Equatable, Sendable {
    let isScheduledToday: Bool
    let isCompletedToday: Bool
    let currentStreak: Int
    let bestStreak: Int
    let totalCompletions: Int
    /// Completed ÷ scheduled days in the last 30 days (today counts only once done).
    let completionRate: Double?
    let last30Scheduled: Int
    let last30Completed: Int
    /// Scheduled and completed days in the current week (whole week, including
    /// days still ahead).
    let weekScheduled: Int
    let weekCompleted: Int

    init(_ habit: HabitSnapshot, today: HabitDay) {
        let calendar = habit.calendar
        let lastJudged = min(today, habit.endDay ?? today)
        isScheduledToday = habit.isScheduled(today)
        isCompletedToday = habit.isCompleted(today)

        // Walk every scheduled day once, oldest first.
        var best = 0
        var run = 0
        var scheduledDays: [HabitDay] = []
        var day = habit.startDay
        while day <= lastJudged {
            if habit.isScheduled(day) {
                scheduledDays.append(day)
                if habit.isCompleted(day) {
                    run += 1
                    best = max(best, run)
                } else if day != today {
                    run = 0
                }
            }
            day = day.adding(days: 1, calendar: calendar)
        }
        bestStreak = best

        // Current streak: back from today, skipping an unfinished today.
        var current = 0
        for scheduled in scheduledDays.reversed() {
            if habit.isCompleted(scheduled) {
                current += 1
            } else if scheduled == today {
                continue
            } else {
                break
            }
        }
        currentStreak = current

        totalCompletions = habit.completedDays.count { $0 >= habit.startDay && $0 <= lastJudged }

        let windowStart = today.adding(days: -29, calendar: calendar)
        let window = scheduledDays.filter { $0 >= windowStart && ($0 != today || habit.isCompleted($0)) }
        last30Scheduled = window.count
        last30Completed = window.count { habit.isCompleted($0) }
        completionRate = last30Scheduled > 0 ? Double(last30Completed) / Double(last30Scheduled) : nil

        let weekDays = Self.week(containing: today, calendar: calendar)
        let weekScheduledDays = weekDays.filter { habit.isScheduled($0) && $0 <= (habit.endDay ?? $0) }
        weekScheduled = weekScheduledDays.count
        weekCompleted = weekScheduledDays.count { habit.isCompleted($0) && $0 <= today }
    }

    static func week(containing day: HabitDay, calendar: Calendar) -> [HabitDay] {
        let offset = (day.weekday(calendar: calendar) - calendar.firstWeekday + 7) % 7
        let first = day.adding(days: -offset, calendar: calendar)
        return (0..<7).map { first.adding(days: $0, calendar: calendar) }
    }
}

/// One cell of the history calendar.
nonisolated struct HabitCalendarDay: Identifiable, Sendable {
    enum Status: Equatable, Sendable {
        case completed
        case missed
        /// Scheduled today and not done yet.
        case pending
        case notScheduled
        case beforeStart
        case future
    }

    let day: HabitDay
    let status: Status

    var id: String { day.key }

    /// Past and today's scheduled days can be marked or unmarked.
    var canToggle: Bool {
        [.completed, .missed, .pending].contains(status)
    }
}

nonisolated enum HabitCalendar {
    /// Every day of the month containing `month`, with its status as of `today`.
    static func days(inMonthOf month: HabitDay, habit: HabitSnapshot, today: HabitDay) -> [HabitCalendarDay] {
        let calendar = habit.calendar
        guard let range = calendar.range(of: .day, in: .month, for: month.date(in: calendar)) else { return [] }
        return range.map { value in
            let day = HabitDay(year: month.year, month: month.month, day: value)
            return HabitCalendarDay(day: day, status: status(of: day, habit: habit, today: today))
        }
    }

    static func status(of day: HabitDay, habit: HabitSnapshot, today: HabitDay) -> HabitCalendarDay.Status {
        if day > today { return .future }
        if day < habit.startDay { return .beforeStart }
        guard habit.isScheduled(day) else {
            return habit.isCompleted(day) ? .completed : .notScheduled
        }
        if habit.isCompleted(day) { return .completed }
        return day == today ? .pending : .missed
    }

    /// Blank cells before day 1 so weekdays line up with the header.
    static func leadingBlanks(forMonthOf month: HabitDay, calendar: Calendar) -> Int {
        let first = HabitDay(year: month.year, month: month.month, day: 1)
        return (first.weekday(calendar: calendar) - calendar.firstWeekday + 7) % 7
    }
}

/// Today's habits for the Habits screen and Home: same data, same rules.
@MainActor
struct HabitsTodaySummary {
    struct Item: Identifiable {
        let habit: Habit
        let snapshot: HabitSnapshot
        let statistics: HabitStatistics

        var id: UUID { habit.id }
        var isCompleted: Bool { statistics.isCompletedToday }
    }

    let today: HabitDay
    /// Active habits scheduled today, in display order.
    let scheduled: [Item]
    /// Active habits not scheduled today.
    let others: [Item]

    var completedCount: Int { scheduled.count(where: \.isCompleted) }
    var scheduledCount: Int { scheduled.count }
    var progress: Double { scheduledCount == 0 ? 0 : Double(completedCount) / Double(scheduledCount) }
    var pending: [Item] { scheduled.filter { !$0.isCompleted } }
    var completed: [Item] { scheduled.filter(\.isCompleted) }

    init(habits: [Habit], now: Date = .now, calendar: Calendar = .current) {
        let today = HabitDay(now, calendar: calendar)
        self.today = today
        let items = habits
            .filter { !$0.isArchived }
            .sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
            .map { habit in
                let snapshot = HabitSnapshot(habit, calendar: calendar)
                return Item(habit: habit, snapshot: snapshot, statistics: HabitStatistics(snapshot, today: today))
            }
        scheduled = items.filter(\.statistics.isScheduledToday)
        others = items.filter { !$0.statistics.isScheduledToday }
    }
}
