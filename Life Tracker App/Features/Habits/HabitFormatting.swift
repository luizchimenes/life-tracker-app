import SwiftUI

/// Localized weekday names and schedule descriptions for the app language.
enum HabitFormatting {
    static var calendar: Calendar {
        var calendar = Calendar.current
        calendar.locale = AppLocalization.selectedLocale
        return calendar
    }

    /// Weekdays (1 = Sunday … 7) starting at the calendar's first weekday.
    static func orderedWeekdays(_ calendar: Calendar = HabitFormatting.calendar) -> [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    static func shortName(_ weekday: Int) -> String {
        calendar.shortWeekdaySymbols[weekday - 1]
    }

    static func veryShortName(_ weekday: Int) -> String {
        calendar.veryShortWeekdaySymbols[weekday - 1]
    }

    static func fullName(_ weekday: Int) -> String {
        calendar.weekdaySymbols[weekday - 1]
    }

    static func summary(_ schedule: HabitSchedule) -> String {
        switch schedule.type {
        case .daily:
            return AppLocalization.string("Every day")
        case .weekly:
            let days = orderedWeekdays().filter(schedule.weekdays.contains)
            if days.count == 7 {
                return AppLocalization.string("Every day")
            }
            return days.map { shortName($0) }.joined(separator: ", ")
        }
    }

    static func dayText(_ day: HabitDay) -> String {
        day.date().formatted(.dateTime.day().month(.wide).locale(AppLocalization.selectedLocale))
    }

    static func monthTitle(_ day: HabitDay) -> String {
        day.date().formatted(.dateTime.month(.wide).year().locale(AppLocalization.selectedLocale))
    }

    static let icons = [
        "checkmark.circle", "figure.run", "dumbbell.fill", "figure.mind.and.body", "bicycle", "figure.walk",
        "book.fill", "graduationcap.fill", "pencil", "globe", "music.note", "paintbrush.fill",
        "drop.fill", "fork.knife", "cup.and.saucer.fill", "pills.fill", "heart.fill", "brain.head.profile",
        "bed.double.fill", "moon.fill", "sun.max.fill", "leaf.fill", "house.fill", "pawprint.fill",
        "laptopcomputer", "creditcard", "phone.down.fill", "sparkles"
    ]
}
