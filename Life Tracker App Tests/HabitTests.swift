import Foundation
import SwiftData
import Testing
@testable import Life_Tracker_App

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 1
    return calendar
}()

private func d(_ year: Int, _ month: Int, _ day: Int) -> HabitDay {
    HabitDay(year: year, month: month, day: day)
}

private func at(_ day: HabitDay) -> Date {
    day.date(in: utc)
}

// Calendar weekdays: 1 Sunday … 7 Saturday. 2026-10-05, 10-19 and 10-26 are Mondays.
private let monday = 2, tuesday = 3, wednesday = 4, thursday = 5, friday = 6
private let gymSchedule = HabitSchedule(type: .weekly, weekdays: [monday, wednesday, friday])

private func snapshot(
    start: HabitDay,
    schedule: HabitSchedule = .everyDay,
    completed: [HabitDay] = [],
    timeline: [HabitSnapshot.ScheduleEntry]? = nil,
    end: HabitDay? = nil
) -> HabitSnapshot {
    HabitSnapshot(
        id: UUID(),
        startDay: start,
        endDay: end,
        timeline: timeline ?? [.init(from: start, schedule: schedule)],
        completedDays: Set(completed),
        calendar: utc
    )
}

@Suite("Habits – schedule and streaks")
struct HabitStreakTests {
    @Test func dailyScheduleIsEligibleEveryDayFromStart() {
        let habit = snapshot(start: d(2026, 10, 5))
        #expect(habit.isScheduled(d(2026, 10, 5)))
        #expect(habit.isScheduled(d(2026, 10, 6)))
        #expect(!habit.isScheduled(d(2026, 10, 4)))
    }

    @Test func weeklyScheduleOnlyOnSelectedDays() {
        let gym = snapshot(start: d(2026, 10, 5), schedule: gymSchedule)
        #expect(gym.isScheduled(d(2026, 10, 5)))   // Mon
        #expect(!gym.isScheduled(d(2026, 10, 6)))  // Tue
        #expect(gym.isScheduled(d(2026, 10, 7)))   // Wed
        #expect(!gym.isScheduled(d(2026, 10, 8)))  // Thu
        #expect(gym.isScheduled(d(2026, 10, 9)))   // Fri
        #expect(!gym.isScheduled(d(2026, 10, 10))) // Sat
    }

    @Test func gymMondayWednesdayFridayStreakIgnoresOffDays() {
        let gym = snapshot(start: d(2026, 10, 5), schedule: gymSchedule, completed: [d(2026, 10, 5), d(2026, 10, 7), d(2026, 10, 9)])
        // Seen on Saturday and on the following Sunday: off days never break it.
        #expect(HabitStatistics(gym, today: d(2026, 10, 10)).currentStreak == 3)
        #expect(HabitStatistics(gym, today: d(2026, 10, 11)).currentStreak == 3)
    }

    @Test func missedScheduledDayBreaksTheStreak() {
        let gym = snapshot(start: d(2026, 10, 5), schedule: gymSchedule, completed: [d(2026, 10, 5), d(2026, 10, 9), d(2026, 10, 12)])
        let stats = HabitStatistics(gym, today: d(2026, 10, 13))
        #expect(stats.currentStreak == 2) // Wed 7 missed
        #expect(stats.bestStreak == 2)
    }

    @Test func bestStreakRemembersTheLongestRun() {
        let completed = [d(2026, 10, 1), d(2026, 10, 2), d(2026, 10, 3), d(2026, 10, 4), d(2026, 10, 6), d(2026, 10, 7)]
        let stats = HabitStatistics(snapshot(start: d(2026, 10, 1), completed: completed), today: d(2026, 10, 7))
        #expect(stats.bestStreak == 4)
        #expect(stats.currentStreak == 2)
    }

    @Test func todayUnfinishedDoesNotBreakTheStreakYet() {
        let habit = snapshot(start: d(2026, 10, 1), completed: [d(2026, 10, 1), d(2026, 10, 2)])
        let today = HabitStatistics(habit, today: d(2026, 10, 3))
        #expect(today.currentStreak == 2)
        #expect(!today.isCompletedToday)
        // Once the day is over it counts as missed.
        #expect(HabitStatistics(habit, today: d(2026, 10, 4)).currentStreak == 0)
    }

    @Test func futureDaysNeverCount() {
        let habit = snapshot(start: d(2026, 10, 1), completed: [d(2026, 10, 1), d(2026, 10, 9)])
        let stats = HabitStatistics(habit, today: d(2026, 10, 2))
        #expect(stats.totalCompletions == 1)
        #expect(stats.bestStreak == 1)
        #expect(HabitCalendar.status(of: d(2026, 10, 9), habit: habit, today: d(2026, 10, 2)) == .future)
    }

    @Test func habitStartingTodayIsNotPenalized() {
        let habit = snapshot(start: d(2026, 10, 27))
        let stats = HabitStatistics(habit, today: d(2026, 10, 27))
        #expect(stats.isScheduledToday)
        #expect(stats.currentStreak == 0)
        #expect(stats.last30Scheduled == 0)
        #expect(stats.completionRate == nil)
        #expect(HabitCalendar.status(of: d(2026, 10, 26), habit: habit, today: d(2026, 10, 27)) == .beforeStart)
    }

    @Test func streaksCrossMonthAndYearBoundaries() {
        let completed = [d(2026, 12, 30), d(2026, 12, 31), d(2027, 1, 1), d(2027, 1, 2)]
        let stats = HabitStatistics(snapshot(start: d(2026, 12, 30), completed: completed), today: d(2027, 1, 2))
        #expect(stats.currentStreak == 4)
        #expect(d(2026, 12, 31).adding(days: 1, calendar: utc) == d(2027, 1, 1))
    }

    @Test func leapDayIsARealScheduledDay() {
        #expect(d(2028, 2, 28).adding(days: 1, calendar: utc) == d(2028, 2, 29))
        #expect(d(2028, 2, 29).adding(days: 1, calendar: utc) == d(2028, 3, 1))
        let skippedLeapDay = snapshot(start: d(2028, 2, 27), completed: [d(2028, 2, 27), d(2028, 2, 28), d(2028, 3, 1)])
        #expect(HabitStatistics(skippedLeapDay, today: d(2028, 3, 1)).currentStreak == 1)
        let february = HabitCalendar.days(inMonthOf: d(2028, 2, 1), habit: skippedLeapDay, today: d(2028, 3, 1))
        #expect(february.count == 29)
        #expect(february.last?.status == .missed)
    }

    @Test func completionRateCountsOnlyScheduledDays() {
        // Gym since Mon Oct 5, seen on Tue Oct 27: scheduled Mon/Wed/Fri, 30-day
        // window Sep 28 – Oct 27 starts at Oct 5. 10 scheduled days, 8 done.
        let scheduled = [d(2026, 10, 5), d(2026, 10, 7), d(2026, 10, 9), d(2026, 10, 12), d(2026, 10, 14), d(2026, 10, 16), d(2026, 10, 19), d(2026, 10, 21), d(2026, 10, 23), d(2026, 10, 26)]
        let gym = snapshot(start: d(2026, 10, 5), schedule: gymSchedule, completed: Array(scheduled.dropFirst(2)))
        let stats = HabitStatistics(gym, today: d(2026, 10, 27))
        #expect(stats.last30Scheduled == 10)
        #expect(stats.last30Completed == 8)
        #expect(stats.completionRate == 0.8)
        #expect(stats.totalCompletions == 8)
    }

    @Test func weekCountsScheduledAndCompletedDays() {
        // Week of Sun Oct 25 – Sat Oct 31: Gym on Mon 26, Wed 28, Fri 30.
        let gym = snapshot(start: d(2026, 10, 5), schedule: gymSchedule, completed: [d(2026, 10, 26)])
        let stats = HabitStatistics(gym, today: d(2026, 10, 27))
        #expect(stats.weekScheduled == 3)
        #expect(stats.weekCompleted == 1)
    }

    @Test func calendarShowsEveryState() {
        let gym = snapshot(start: d(2026, 10, 5), schedule: gymSchedule, completed: [d(2026, 10, 5)])
        let today = d(2026, 10, 9)
        let status = { HabitCalendar.status(of: $0, habit: gym, today: today) }
        #expect(status(d(2026, 10, 4)) == .beforeStart)
        #expect(status(d(2026, 10, 5)) == .completed)
        #expect(status(d(2026, 10, 6)) == .notScheduled)
        #expect(status(d(2026, 10, 7)) == .missed)
        #expect(status(d(2026, 10, 9)) == .pending)
        #expect(status(d(2026, 10, 12)) == .future)
        let october = HabitCalendar.days(inMonthOf: d(2026, 10, 1), habit: gym, today: today)
        #expect(october.count == 31)
        #expect(october.filter(\.canToggle).map(\.day) == [d(2026, 10, 5), d(2026, 10, 7), d(2026, 10, 9)])
        #expect(HabitCalendar.leadingBlanks(forMonthOf: d(2026, 10, 1), calendar: utc) == 4) // Oct 1 is a Thursday
    }

    @Test func scheduleEditsKeepPastDaysAsTheyWere() {
        // Gym Mon/Wed/Fri until Sun Oct 18, then every day from Mon Oct 19.
        let timeline: [HabitSnapshot.ScheduleEntry] = [
            .init(from: d(2026, 10, 5), schedule: gymSchedule),
            .init(from: d(2026, 10, 19), schedule: .everyDay)
        ]
        let completed = [d(2026, 10, 12), d(2026, 10, 14), d(2026, 10, 16), d(2026, 10, 19), d(2026, 10, 20)]
        let gym = snapshot(start: d(2026, 10, 5), completed: completed, timeline: timeline)
        let stats = HabitStatistics(gym, today: d(2026, 10, 20))
        // Tue 13 and Thu 15 were not scheduled then, so they are not misses.
        #expect(stats.currentStreak == 5)
        #expect(HabitCalendar.status(of: d(2026, 10, 13), habit: gym, today: d(2026, 10, 20)) == .notScheduled)
        #expect(gym.isScheduled(d(2026, 10, 20)))
    }
}

@Suite("Habits – service and persistence")
@MainActor
struct HabitServiceTests {
    private let now = at(d(2026, 10, 27))

    private func create(_ name: String = "Gym", schedule: HabitSchedule = gymSchedule, start: HabitDay = d(2026, 10, 5), in context: ModelContext) throws -> Habit {
        try HabitService.create(name: name, iconName: "dumbbell.fill", colorName: "blue", schedule: schedule, startDate: at(start), in: context, now: now, calendar: utc)
    }

    @Test func createsAHabitWithItsFirstSchedule() throws {
        let context = try TestStore.context()
        let gym = try create(in: context)
        let reading = try create("Reading", schedule: .everyDay, in: context)
        #expect(gym.name == "Gym")
        #expect(gym.schedule == gymSchedule)
        #expect(gym.scheduleVersions.count == 1)
        #expect((gym.sortOrder, reading.sortOrder) == (0, 1))
        #expect(HabitDay(gym.startDate, calendar: utc) == d(2026, 10, 5))
        #expect(throws: HabitError.emptyName) { try create("  ", in: context) }
        #expect(throws: HabitError.invalidSchedule) { try create("X", schedule: HabitSchedule(type: .weekly, weekdays: []), in: context) }
    }

    @Test func editingTheScheduleStartsANewVersionToday() throws {
        let context = try TestStore.context()
        let gym = try create(in: context)
        try HabitService.update(gym, name: "Gym 💪", notes: "Leg day", iconName: "figure.run", colorName: "red", schedule: .everyDay, startDate: gym.startDate, in: context, now: now, calendar: utc)
        #expect(gym.name == "Gym 💪")
        #expect(gym.schedule == .everyDay)
        let versions = gym.scheduleVersions.sorted { $0.effectiveFrom < $1.effectiveFrom }
        #expect(versions.map { HabitDay($0.effectiveFrom, calendar: utc) } == [d(2026, 10, 5), d(2026, 10, 27)])
        #expect(versions.first?.schedule == gymSchedule)

        // Before the habit starts an edit just replaces the schedule.
        let future = try create("Run", start: d(2026, 11, 2), in: context)
        try HabitService.update(future, name: "Run", notes: "", iconName: "figure.run", colorName: "blue", schedule: .everyDay, startDate: future.startDate, in: context, now: now, calendar: utc)
        #expect(future.scheduleVersions.count == 1)
    }

    @Test func completesAndUndoesWithOneToggleAndNoDuplicates() throws {
        let context = try TestStore.context()
        let gym = try create(in: context)
        let monday = d(2026, 10, 26)
        #expect(try HabitService.toggleCompletion(of: gym, on: monday, in: context, now: now, calendar: utc))
        try HabitService.setCompleted(gym, on: monday, in: context, now: now, calendar: utc)
        #expect(try context.fetchCount(FetchDescriptor<HabitCompletion>()) == 1)
        #expect(!(try HabitService.toggleCompletion(of: gym, on: monday, in: context, now: now, calendar: utc)))
        #expect(try context.fetchCount(FetchDescriptor<HabitCompletion>()) == 0)
    }

    @Test func rejectsInvalidDays() throws {
        let context = try TestStore.context()
        let gym = try create(in: context)
        #expect(throws: HabitError.notScheduled) { try HabitService.setCompleted(gym, on: d(2026, 10, 27), in: context, now: now, calendar: utc) }
        #expect(throws: HabitError.futureDay) { try HabitService.setCompleted(gym, on: d(2026, 10, 28), in: context, now: now, calendar: utc) }
        #expect(throws: HabitError.beforeStart) { try HabitService.setCompleted(gym, on: d(2026, 9, 28), in: context, now: now, calendar: utc) }
        #expect(try context.fetchCount(FetchDescriptor<HabitCompletion>()) == 0)
    }

    @Test func archivingKeepsHistoryAndLeavesActiveLists() throws {
        let context = try TestStore.context()
        let gym = try create(in: context)
        let reading = try create("Reading", schedule: .everyDay, in: context)
        try HabitService.setCompleted(gym, on: d(2026, 10, 26), in: context, now: now, calendar: utc)
        try HabitService.archive(gym, in: context, now: now, calendar: utc)
        #expect(gym.isArchived)
        #expect(gym.completions.count == 1)
        let summary = HabitsTodaySummary(habits: [gym, reading], now: now, calendar: utc)
        #expect(summary.scheduled.map(\.habit.id) == [reading.id])
        #expect(!summary.others.contains { $0.habit.id == gym.id })
        #expect(throws: HabitError.archived) { try HabitService.toggleCompletion(of: gym, on: d(2026, 10, 26), in: context, now: now, calendar: utc) }
    }

    @Test func reactivatingTreatsTheArchivedGapAsAPause() throws {
        let context = try TestStore.context()
        let reading = try create("Reading", schedule: .everyDay, start: d(2026, 10, 1), in: context)
        for day in 1...3 {
            try HabitService.setCompleted(reading, on: d(2026, 10, day), in: context, now: at(d(2026, 10, 3)), calendar: utc)
        }
        try HabitService.archive(reading, in: context, now: at(d(2026, 10, 3)), calendar: utc)
        try HabitService.reactivate(reading, in: context, now: at(d(2026, 10, 10)), calendar: utc)
        try HabitService.setCompleted(reading, on: d(2026, 10, 10), in: context, now: at(d(2026, 10, 10)), calendar: utc)
        let stats = HabitStatistics(HabitSnapshot(reading, calendar: utc), today: d(2026, 10, 10))
        #expect(stats.currentStreak == 4)
        #expect(!HabitSnapshot(reading, calendar: utc).isScheduled(d(2026, 10, 6)))
    }

    @Test func homeAndHabitsShareTheSameSummary() throws {
        let context = try TestStore.context()
        let gym = try create(in: context)          // Mon/Wed/Fri: not today (Tue)
        let reading = try create("Reading", schedule: .everyDay, in: context)
        let french = try create("French", schedule: HabitSchedule(type: .weekly, weekdays: [tuesday, thursday]), in: context)
        try HabitService.setCompleted(reading, on: d(2026, 10, 27), in: context, now: now, calendar: utc)
        let habits = try context.fetch(FetchDescriptor<Habit>())

        let summary = HabitsTodaySummary(habits: habits, now: now, calendar: utc)
        #expect(summary.scheduledCount == 2)
        #expect(summary.completedCount == 1)
        #expect(summary.progress == 0.5)
        #expect(summary.pending.map(\.habit.id) == [french.id])
        #expect(summary.completed.map(\.habit.id) == [reading.id])
        #expect(summary.others.map(\.habit.id) == [gym.id])
        // Each item carries the same statistics the detail screen computes.
        let readingStats = HabitStatistics(HabitSnapshot(reading, calendar: utc), today: d(2026, 10, 27))
        #expect(summary.completed.first?.statistics == readingStats)
    }

    @Test func completionsSurviveReopeningTheStore() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "LifeTrackerHabits-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "default.store")

        try autoreleasepool {
            let context = ModelContext(try LifeTrackerPersistence.makeContainer(storeURL: url))
            let gym = try create(in: context)
            try HabitService.setCompleted(gym, on: d(2026, 10, 26), in: context, now: now, calendar: utc)
            try HabitService.setCompleted(gym, on: d(2026, 10, 23), in: context, now: now, calendar: utc)
        }

        let reopened = ModelContext(try LifeTrackerPersistence.makeContainer(storeURL: url))
        let gym = try #require(try reopened.fetch(FetchDescriptor<Habit>()).first)
        #expect(Set(gym.completions.map { HabitDay($0.day, calendar: utc) }) == [d(2026, 10, 23), d(2026, 10, 26)])
        #expect(HabitStatistics(HabitSnapshot(gym, calendar: utc), today: d(2026, 10, 27)).currentStreak == 2)
    }
}
