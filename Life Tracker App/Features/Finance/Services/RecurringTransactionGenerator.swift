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
            // A card rule without its card cannot be charged anywhere; leave it
            // untouched instead of silently generating a different method.
            if rule.paymentMethod == .creditCard && rule.creditCard == nil {
                continue
            }

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
                        try generateOccurrence(
                            of: rule,
                            on: occurrenceStart,
                            occurrenceID: occurrenceID,
                            in: modelContext,
                            calendar: calendar
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

    /// Card rules become a one-installment card purchase so invoice, limit and
    /// cycle rules stay in CreditCardPurchaseService; other methods are a
    /// direct transaction, as before V2.
    @MainActor
    private static func generateOccurrence(
        of rule: RecurringTransaction,
        on date: Date,
        occurrenceID: String,
        in modelContext: ModelContext,
        calendar: Calendar
    ) throws {
        if rule.type == .expense,
           rule.paymentMethod == .creditCard,
           let creditCard = rule.creditCard {
            try CreditCardPurchaseService.createPurchase(
                title: rule.title,
                totalAmount: rule.amount,
                purchaseDate: date,
                category: rule.category,
                notes: rule.notes,
                creditCard: creditCard,
                installmentCount: 1,
                sourceRecurringTransactionID: rule.id,
                recurringOccurrenceID: occurrenceID,
                in: modelContext,
                calendar: calendar
            )
            return
        }

        modelContext.insert(
            Transaction(
                title: rule.title,
                amount: rule.amount,
                date: date,
                type: rule.type,
                category: rule.category,
                notes: rule.notes,
                sourceRecurringTransactionID: rule.id,
                recurringOccurrenceID: occurrenceID,
                paymentMethod: rule.type == .income ? .debit : rule.paymentMethod.directOrDebit
            )
        )
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
