import Foundation
import SwiftData

enum HabitError: LocalizedError, Equatable {
    case emptyName
    case invalidSchedule
    case notScheduled
    case futureDay
    case beforeStart
    case archived

    var errorDescription: String? {
        switch self {
        case .emptyName: AppLocalization.string("Enter a name for the habit.")
        case .invalidSchedule: AppLocalization.string("Choose at least one day of the week.")
        case .notScheduled: AppLocalization.string("This habit is not scheduled on that day.")
        case .futureDay: AppLocalization.string("Future days cannot be completed yet.")
        case .beforeStart: AppLocalization.string("That day is before the habit started.")
        case .archived: AppLocalization.string("Reactivate the habit to change its history.")
        }
    }
}

/// The only place that writes habits and completions, shared by every screen.
///
/// Schedule-edit policy: a new schedule applies from the day of the edit
/// onward. Earlier days keep being judged by the schedule that applied then,
/// so an edit never turns past days into misses or erases history. Before the
/// habit starts, an edit simply replaces the schedule.
@MainActor
enum HabitService {
    @discardableResult
    static func create(
        name: String,
        notes: String = "",
        iconName: String,
        colorName: String,
        schedule: HabitSchedule,
        startDate: Date,
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws -> Habit {
        let trimmed = try validated(name: name, schedule: schedule)
        let existing = try context.fetch(FetchDescriptor<Habit>())
        let start = HabitDay(startDate, calendar: calendar).date(in: calendar)
        let habit = Habit(
            name: trimmed,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            iconName: iconName,
            colorName: colorName,
            createdAt: now,
            startDate: start,
            sortOrder: (existing.map(\.sortOrder).max() ?? -1) + 1,
            schedule: schedule
        )
        context.insert(habit)
        context.insert(HabitScheduleVersion(habit: habit, effectiveFrom: start, schedule: schedule))
        try context.save()
        return habit
    }

    static func update(
        _ habit: Habit,
        name: String,
        notes: String,
        iconName: String,
        colorName: String,
        schedule: HabitSchedule,
        startDate: Date,
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws {
        let trimmed = try validated(name: name, schedule: schedule)
        let today = HabitDay(now, calendar: calendar)
        let newStart = HabitDay(startDate, calendar: calendar)
        let oldStart = HabitDay(habit.startDate, calendar: calendar)

        habit.name = trimmed
        habit.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        habit.iconName = iconName
        habit.colorName = colorName
        habit.startDate = newStart.date(in: calendar)

        let versions = habit.scheduleVersions.sorted { $0.effectiveFrom < $1.effectiveFrom }
        if oldStart >= today || newStart >= today || versions.isEmpty {
            // Not started yet: nothing to preserve, the schedule is replaced.
            versions.forEach(context.delete)
            context.insert(HabitScheduleVersion(habit: habit, effectiveFrom: newStart.date(in: calendar), schedule: schedule))
        } else {
            // The first schedule always covers the start day.
            if let first = versions.first, HabitDay(first.effectiveFrom, calendar: calendar) > newStart {
                first.effectiveFrom = newStart.date(in: calendar)
            }
            if habit.schedule != schedule {
                // From today on; an edit made earlier today is simply replaced.
                versions.filter { HabitDay($0.effectiveFrom, calendar: calendar) == today }.forEach(context.delete)
                context.insert(HabitScheduleVersion(habit: habit, effectiveFrom: today.date(in: calendar), schedule: schedule))
            }
        }
        habit.schedule = schedule
        try context.save()
    }

    static func archive(_ habit: Habit, in context: ModelContext, now: Date = .now, calendar: Calendar = .current) throws {
        guard !habit.isArchived else { return }
        habit.isArchived = true
        habit.archivedAt = HabitDay(now, calendar: calendar).date(in: calendar)
        try context.save()
    }

    /// Reactivating resumes from today. The archived period becomes a pause in
    /// the schedule history, so it never counts as missed days.
    static func reactivate(_ habit: Habit, in context: ModelContext, now: Date = .now, calendar: Calendar = .current) throws {
        guard habit.isArchived else { return }
        let today = HabitDay(now, calendar: calendar)
        if let archivedAt = habit.archivedAt {
            let pauseStart = HabitDay(archivedAt, calendar: calendar).adding(days: 1, calendar: calendar)
            if pauseStart < today {
                context.insert(HabitScheduleVersion(habit: habit, effectiveFrom: pauseStart.date(in: calendar), schedule: .paused))
                context.insert(HabitScheduleVersion(habit: habit, effectiveFrom: today.date(in: calendar), schedule: habit.schedule))
            }
        }
        habit.isArchived = false
        habit.archivedAt = nil
        try context.save()
    }

    /// Marks or unmarks `day`. Returns whether the day is now completed.
    @discardableResult
    static func toggleCompletion(
        of habit: Habit,
        on day: HabitDay,
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws -> Bool {
        if let existing = completion(of: habit, on: day, calendar: calendar) {
            guard !habit.isArchived else { throw HabitError.archived }
            context.delete(existing)
            try context.save()
            return false
        }
        try setCompleted(habit, on: day, in: context, now: now, calendar: calendar)
        return true
    }

    /// Completes `day` once; calling it again for the same day does nothing.
    static func setCompleted(
        _ habit: Habit,
        on day: HabitDay,
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws {
        guard !habit.isArchived else { throw HabitError.archived }
        let today = HabitDay(now, calendar: calendar)
        let snapshot = HabitSnapshot(habit, calendar: calendar)
        guard day <= today else { throw HabitError.futureDay }
        guard day >= snapshot.startDay else { throw HabitError.beforeStart }
        guard snapshot.isScheduled(day) else { throw HabitError.notScheduled }
        guard completion(of: habit, on: day, calendar: calendar) == nil else { return }
        context.insert(HabitCompletion(habit: habit, day: day, createdAt: now, calendar: calendar))
        try context.save()
    }

    static func completion(of habit: Habit, on day: HabitDay, calendar: Calendar = .current) -> HabitCompletion? {
        let key = HabitCompletion.key(habitID: habit.id, day: day)
        return habit.completions.first { $0.completionKey == key }
    }

    private static func validated(name: String, schedule: HabitSchedule) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HabitError.emptyName }
        guard schedule.isValid else { throw HabitError.invalidSchedule }
        return trimmed
    }
}
