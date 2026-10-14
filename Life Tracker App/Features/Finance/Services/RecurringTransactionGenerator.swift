import Foundation
import SwiftData

enum RecurringTransactionGenerator {
    @MainActor
    static func generateDueTransactions(
        in modelContext: ModelContext,
        through today: Date = .now,
        calendar: Calendar = .current
    ) throws {
        let rules = try modelContext.fetch(
            FetchDescriptor<RecurringTransaction>()
        )
        let transactions = try modelContext.fetch(
            FetchDescriptor<Transaction>()
        )
        var existingOccurrenceIDs = Set(
            transactions.compactMap(\.recurringOccurrenceID)
        )

        let todayStart = calendar.startOfDay(for: today)

        for rule in rules where rule.isActive {
            guard let startMonth = startOfMonth(
                containing: rule.startDate,
                calendar: calendar
            ) else {
                continue
            }

            var month = startMonth
            var latestDueDate = rule.lastGeneratedDate

            while month <= todayStart {
                guard let occurrenceDate = occurrenceDate(
                    in: month,
                    dayOfMonth: rule.dayOfMonth,
                    calendar: calendar
                ) else {
                    break
                }

                let occurrenceStart = calendar.startOfDay(for: occurrenceDate)
                let ruleStart = calendar.startOfDay(for: rule.startDate)

                if occurrenceStart >= ruleStart && occurrenceStart <= todayStart {
                    let occurrenceID = occurrenceIdentifier(
                        ruleID: rule.id,
                        occurrenceDate: occurrenceStart,
                        calendar: calendar
                    )

                    let wasPreviouslyGenerated = rule.lastGeneratedDate.map {
                        occurrenceStart <= calendar.startOfDay(for: $0)
                    } ?? false

                    if !existingOccurrenceIDs.contains(occurrenceID),
                       !wasPreviouslyGenerated {
                        modelContext.insert(
                            Transaction(
                                title: rule.title,
                                amount: rule.amount,
                                date: occurrenceStart,
                                type: rule.type,
                                category: rule.category,
                                notes: rule.notes,
                                sourceRecurringTransactionID: rule.id,
                                recurringOccurrenceID: occurrenceID
                            )
                        )
                        existingOccurrenceIDs.insert(occurrenceID)
                    }

                    if latestDueDate.map({ occurrenceStart > $0 }) ?? true {
                        latestDueDate = occurrenceStart
                    }
                }

                guard let nextMonth = calendar.date(
                    byAdding: .month,
                    value: 1,
                    to: month
                ) else {
                    break
                }

                month = nextMonth
            }

            rule.lastGeneratedDate = latestDueDate
        }

        try modelContext.save()
    }

    static func occurrenceDate(
        in month: Date,
        dayOfMonth: Int,
        calendar: Calendar = .current
    ) -> Date? {
        guard let dayRange = calendar.range(of: .day, in: .month, for: month) else {
            return nil
        }

        let validDay = min(max(dayOfMonth, 1), dayRange.count)
        var components = calendar.dateComponents([.year, .month], from: month)
        components.day = validDay

        return calendar.date(from: components)
    }

    private static func startOfMonth(
        containing date: Date,
        calendar: Calendar
    ) -> Date? {
        calendar.date(
            from: calendar.dateComponents([.year, .month], from: date)
        )
    }

    static func occurrenceIdentifier(
        ruleID: UUID,
        occurrenceDate: Date,
        calendar: Calendar
    ) -> String {
        let components = calendar.dateComponents(
            [.year, .month],
            from: occurrenceDate
        )
        return "\(ruleID.uuidString)-\(components.year ?? 0)-\(components.month ?? 0)"
    }
}
