import Foundation
import SwiftData

enum FixedBillOccurrenceGenerator {
    @MainActor
    static func generateRelevantOccurrences(
        in modelContext: ModelContext,
        for date: Date = .now,
        calendar: Calendar = .current
    ) throws {
        guard let cycle = FinancialCycle(containing: date, calendar: calendar),
              let finalCycleDay = calendar.date(
                byAdding: .day,
                value: -1,
                to: cycle.end
              ) else {
            return
        }

        let bills = try modelContext.fetch(FetchDescriptor<FixedBill>())
        let existingOccurrences = try modelContext.fetch(
            FetchDescriptor<FixedBillOccurrence>()
        )
        var existingIdentifiers = Set(existingOccurrences.map(\.occurrenceIdentifier))

        for bill in bills where bill.isActive {
            let billOccurrences = existingOccurrences.filter {
                $0.fixedBill.id == bill.id
            }
            let firstMonth: Date

            if let mostRecentDueDate = billOccurrences.map(\.dueDate).max(),
               let followingMonth = calendar.date(
                    byAdding: .month,
                    value: 1,
                    to: mostRecentDueDate
               ) {
                firstMonth = followingMonth
            } else {
                firstMonth = bill.startDate
            }

            guard var month = startOfMonth(
                containing: firstMonth,
                calendar: calendar
            ) else {
                continue
            }

            while month <= finalCycleDay {
                guard let dueDate = RecurringTransactionGenerator.occurrenceDate(
                    in: month,
                    dayOfMonth: bill.dueDay,
                    calendar: calendar
                ) else {
                    break
                }

                let dueDay = calendar.startOfDay(for: dueDate)
                if dueDay >= calendar.startOfDay(for: bill.startDate),
                   dueDay <= calendar.startOfDay(for: finalCycleDay),
                   let occurrenceCycle = FinancialCycle(
                        containing: dueDay,
                        calendar: calendar
                   ) {
                    let identifier = occurrenceIdentifier(
                        fixedBillID: bill.id,
                        dueDate: dueDay,
                        calendar: calendar
                    )

                    if !existingIdentifiers.contains(identifier) {
                        modelContext.insert(
                            FixedBillOccurrence(
                                occurrenceIdentifier: identifier,
                                fixedBill: bill,
                                dueDate: dueDay,
                                financialCycleIdentifier: occurrenceCycle.identifier(
                                    calendar: calendar
                                )
                            )
                        )
                        existingIdentifiers.insert(identifier)
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
        }

        try modelContext.save()
    }

    static func occurrenceIdentifier(
        fixedBillID: UUID,
        dueDate: Date,
        calendar: Calendar = .current
    ) -> String {
        let components = calendar.dateComponents([.year, .month], from: dueDate)
        return "\(fixedBillID.uuidString)-\(components.year ?? 0)-\(components.month ?? 0)"
    }

    private static func startOfMonth(
        containing date: Date,
        calendar: Calendar
    ) -> Date? {
        calendar.date(
            from: calendar.dateComponents([.year, .month], from: date)
        )
    }
}
