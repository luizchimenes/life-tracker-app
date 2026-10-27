import Foundation
import SwiftData

nonisolated enum HabitScheduleType: String, Codable, CaseIterable, Identifiable {
    case daily
    case weekly

    var id: Self { self }

    var displayName: LocalizedStringResource {
        switch self {
        case .daily: "Every Day"
        case .weekly: "Specific Days"
        }
    }
}

/// A habit and its current schedule. Past days are judged by the schedule in
/// effect at the time (`scheduleVersions`), so editing the schedule never
/// rewrites history. Archiving keeps every completion.
@Model
final class Habit {
    @Attribute(.unique) var id: UUID
    var name: String
    var notes: String
    var iconName: String
    var colorName: String
    var createdAt: Date
    /// Midday of the first eligible day.
    var startDate: Date
    var isArchived: Bool
    /// Midday of the day it was archived; days after it are not judged.
    var archivedAt: Date?
    var sortOrder: Int
    /// Current schedule; mirrors the newest schedule version.
    var scheduleTypeRawValue: String
    /// Calendar weekdays (1 = Sunday … 7 = Saturday), comma separated.
    var weekdaysRawValue: String

    @Relationship(deleteRule: .cascade, inverse: \HabitScheduleVersion.habit)
    var scheduleVersions: [HabitScheduleVersion] = []

    @Relationship(deleteRule: .cascade, inverse: \HabitCompletion.habit)
    var completions: [HabitCompletion] = []

    init(
        id: UUID = UUID(),
        name: String,
        notes: String = "",
        iconName: String,
        colorName: String,
        createdAt: Date,
        startDate: Date,
        sortOrder: Int,
        schedule: HabitSchedule
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.iconName = iconName
        self.colorName = colorName
        self.createdAt = createdAt
        self.startDate = startDate
        isArchived = false
        archivedAt = nil
        self.sortOrder = sortOrder
        scheduleTypeRawValue = schedule.type.rawValue
        weekdaysRawValue = HabitSchedule.encode(schedule.weekdays)
    }

    var schedule: HabitSchedule {
        get {
            HabitSchedule(
                type: HabitScheduleType(rawValue: scheduleTypeRawValue) ?? .daily,
                weekdays: HabitSchedule.decode(weekdaysRawValue)
            )
        }
        set {
            scheduleTypeRawValue = newValue.type.rawValue
            weekdaysRawValue = HabitSchedule.encode(newValue.weekdays)
        }
    }
}

/// The schedule that applies from `effectiveFrom` until the next version.
@Model
final class HabitScheduleVersion {
    @Attribute(.unique) var id: UUID
    var habit: Habit?
    /// Midday of the first day this schedule applies.
    var effectiveFrom: Date
    var scheduleTypeRawValue: String
    var weekdaysRawValue: String

    init(id: UUID = UUID(), habit: Habit?, effectiveFrom: Date, schedule: HabitSchedule) {
        self.id = id
        self.habit = habit
        self.effectiveFrom = effectiveFrom
        scheduleTypeRawValue = schedule.type.rawValue
        weekdaysRawValue = HabitSchedule.encode(schedule.weekdays)
    }

    var schedule: HabitSchedule {
        HabitSchedule(
            type: HabitScheduleType(rawValue: scheduleTypeRawValue) ?? .daily,
            weekdays: HabitSchedule.decode(weekdaysRawValue)
        )
    }
}

/// One completed day of one habit. `completionKey` (habit + calendar day) is
/// unique, so a habit can be completed at most once per day.
@Model
final class HabitCompletion {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var completionKey: String
    var habit: Habit?
    /// Midday of the completed calendar day.
    var day: Date
    var createdAt: Date

    init(id: UUID = UUID(), habit: Habit, day: HabitDay, createdAt: Date, calendar: Calendar = .current) {
        self.id = id
        completionKey = HabitCompletion.key(habitID: habit.id, day: day)
        self.habit = habit
        self.day = day.date(in: calendar)
        self.createdAt = createdAt
    }

    static func key(habitID: UUID, day: HabitDay) -> String {
        "\(habitID.uuidString)|\(day.key)"
    }
}
