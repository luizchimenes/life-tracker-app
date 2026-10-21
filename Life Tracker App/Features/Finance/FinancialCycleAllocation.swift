import Foundation
import SwiftData

/// Which financial cycle may receive an entry dated near the 9th.
///
/// Dates from the 6th to the 8th may count in the following cycle; dates from
/// the 9th to the 11th may count in the preceding one. Outside that window only
/// the automatic, date-based cycle exists. Nothing is ever chosen
/// automatically: `nil` always means Automatic.
enum FinancialCycleAllocation {
    nonisolated enum Kind: Equatable {
        case automatic
        case previous
        case next
    }

    struct Option: Identifiable {
        let kind: Kind
        let cycle: FinancialCycle
        /// Value stored on the transaction: `nil` for Automatic.
        let overrideStart: Date?

        var id: Date { cycle.start }

        init(kind: Kind, cycle: FinancialCycle, calendar: Calendar) {
            self.kind = kind
            self.cycle = cycle
            overrideStart = kind == .automatic ? nil : FinancialCycleAllocation.storedValue(for: cycle, calendar: calendar)
        }
    }

    /// A chosen cycle is stored as midday of its first day, so a time-zone
    /// change of a few hours can never shift it into a neighboring cycle.
    static func storedValue(for cycle: FinancialCycle, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .hour, value: 12, to: cycle.start) ?? cycle.start
    }

    /// Days of the month on each side of the cycle start that offer a choice.
    static let daysBeforeBoundary = 3
    static let daysAfterBoundary = 2

    static func options(for date: Date, calendar: Calendar = .current) -> [Option] {
        guard let automatic = FinancialCycle(containing: date, calendar: calendar) else {
            return []
        }
        let day = calendar.component(.day, from: date)
        let start = FinancialCycle.startDay
        let auto = Option(kind: .automatic, cycle: automatic, calendar: calendar)

        if (start - daysBeforeBoundary)..<start ~= day,
           let next = automatic.shifted(byMonths: 1, calendar: calendar) {
            return [auto, Option(kind: .next, cycle: next, calendar: calendar)]
        }
        if start...(start + daysAfterBoundary) ~= day,
           let previous = automatic.shifted(byMonths: -1, calendar: calendar) {
            return [auto, Option(kind: .previous, cycle: previous, calendar: calendar)]
        }
        return []
    }

    /// Whether a stored choice is still allowed for `date`. Automatic always is.
    static func isValid(_ overrideStart: Date?, for date: Date, calendar: Calendar = .current) -> Bool {
        guard let overrideStart else { return true }
        let chosen = FinancialCycle(containing: overrideStart, calendar: calendar)?.start
        return options(for: date, calendar: calendar).contains {
            $0.kind != .automatic && $0.cycle.start == chosen
        }
    }

    /// Keeps a choice only if it stays valid after the date changed.
    static func revalidated(_ overrideStart: Date?, for date: Date, calendar: Calendar = .current) -> Date? {
        isValid(overrideStart, for: date, calendar: calendar) ? overrideStart : nil
    }

    /// Installment `index` (0-based) of a purchase whose first installment was
    /// moved to the cycle starting at `firstStart` lands one cycle later each
    /// month, keeping the original spacing.
    static func overrideStart(
        forInstallmentAt index: Int,
        firstStart: Date?,
        calendar: Calendar = .current
    ) -> Date? {
        guard let firstStart,
              let first = FinancialCycle(containing: firstStart, calendar: calendar) else {
            return nil
        }
        return first.shifted(byMonths: index, calendar: calendar).map { storedValue(for: $0, calendar: calendar) }
    }
}

enum FinancialCycleAllocationError: LocalizedError {
    case notAllowed
    case generatedTransaction

    var errorDescription: String? {
        switch self {
        case .notAllowed:
            AppLocalization.string("This financial cycle cannot be chosen for this date.")
        case .generatedTransaction:
            AppLocalization.string("Recurring and fixed-bill entries always use their automatic financial cycle.")
        }
    }
}

/// Changes only the financial-cycle allocation of an existing entry. The date,
/// card, invoice, installments and limit are left exactly as they are.
@MainActor
enum FinancialCycleAllocationService {
    static func canChangeAllocation(of transaction: Transaction) -> Bool {
        transaction.sourceRecurringTransactionID == nil
            && transaction.sourceFixedBillOccurrenceID == nil
    }

    /// Applies `overrideStart` (the cycle for the entry, or for installment 1
    /// of a purchase) to the entry or to its whole installment group.
    static func apply(
        _ overrideStart: Date?,
        to transaction: Transaction,
        allTransactions: [Transaction],
        in modelContext: ModelContext,
        calendar: Calendar = .current
    ) throws {
        guard canChangeAllocation(of: transaction) else {
            throw FinancialCycleAllocationError.generatedTransaction
        }
        // Every installment shares the purchase date, so validity is checked once.
        guard FinancialCycleAllocation.isValid(overrideStart, for: transaction.date, calendar: calendar) else {
            throw FinancialCycleAllocationError.notAllowed
        }

        if let purchaseID = transaction.sourcePurchaseID {
            let group = allTransactions.filter { $0.sourcePurchaseID == purchaseID }
            for installment in group {
                let index = max((installment.installmentNumber ?? 1) - 1, 0)
                installment.financialCycleOverrideStartDate = FinancialCycleAllocation.overrideStart(
                    forInstallmentAt: index,
                    firstStart: overrideStart,
                    calendar: calendar
                )
            }
        } else {
            transaction.financialCycleOverrideStartDate = overrideStart
        }
        try modelContext.save()
    }

    /// The choice as shown in forms: the cycle of the entry, or of installment 1.
    static func currentSelection(for transaction: Transaction, allTransactions: [Transaction], calendar: Calendar = .current) -> Date? {
        guard let purchaseID = transaction.sourcePurchaseID else {
            return transaction.financialCycleOverrideStartDate
        }
        let first = allTransactions
            .filter { $0.sourcePurchaseID == purchaseID }
            .min { ($0.installmentNumber ?? 1) < ($1.installmentNumber ?? 1) }
        return (first ?? transaction).financialCycleOverrideStartDate
    }
}
