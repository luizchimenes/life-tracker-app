import Foundation
import SwiftData

enum BackupError: LocalizedError, Equatable {
    case unreadableFile
    case notABackup
    case corrupted
    case unsupportedVersion(Int)
    case missingReference(collection: String, id: UUID)
    case invalidValue(field: String, value: String)
    case invalid([String])
    case stagingFailed
    case applyFailed
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            AppLocalization.string("The file could not be read.")
        case .notABackup:
            AppLocalization.string("This file is not a LifeTracker backup.")
        case .corrupted:
            AppLocalization.string("The backup file is damaged or incomplete.")
        case .unsupportedVersion(let version):
            AppLocalization.string("This backup uses format version \(version), which this version of LifeTracker cannot read. Update the app and try again.")
        case .missingReference, .invalidValue:
            AppLocalization.string("The backup has records that point to missing data.")
        case .invalid(let problems):
            AppLocalization.string("The backup failed \(problems.count) integrity checks, so it cannot be restored. Your current data was not changed.")
        case .stagingFailed:
            AppLocalization.string("The backup could not be prepared for restoring. Your current data was not changed.")
        case .applyFailed:
            AppLocalization.string("The restore could not be completed. Your current data was not changed.")
        case .verificationFailed:
            AppLocalization.string("The restored data did not match the backup, so your previous data was put back.")
        }
    }
}

/// Reads and validates a backup file. Nothing here touches the live store.
@MainActor
enum BackupValidator {
    static func decode(_ data: Data) throws -> LifeTrackerBackup {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BackupError.corrupted
        }
        guard object["format"] as? String == LifeTrackerBackup.formatIdentifier else {
            throw BackupError.notABackup
        }
        guard let version = object["backupVersion"] as? Int else {
            throw BackupError.corrupted
        }
        // Only versions with an explicit reader are accepted.
        guard version == LifeTrackerBackup.currentVersion else {
            throw BackupError.unsupportedVersion(version)
        }
        do {
            return try BackupCoding.decoder().decode(LifeTrackerBackup.self, from: data)
        } catch {
            throw BackupError.corrupted
        }
    }

    /// Decodes and checks a file; throws with every problem found.
    static func load(_ data: Data) throws -> LifeTrackerBackup {
        let backup = try decode(data)
        let problems = problems(in: backup.data)
        guard problems.isEmpty else { throw BackupError.invalid(problems) }
        return backup
    }

    /// Internal consistency of a dataset. Permissive about legitimate history
    /// (e.g. a deleted recurring rule) but strict about anything the app
    /// relies on to rebuild relationships or avoid duplicates.
    static func problems(in data: BackupDataset) -> [String] {
        var problems: [String] = []
        func duplicates<T>(_ items: [T], _ key: (T) -> String?, _ name: String) {
            var seen = Set<String>()
            for item in items {
                guard let value = key(item) else { continue }
                if !seen.insert(value).inserted {
                    problems.append("duplicate \(name) \(value)")
                }
            }
        }
        func require(_ condition: Bool, _ message: @autoclosure () -> String) {
            if !condition { problems.append(message()) }
        }

        duplicates(data.transactions, { $0.id.uuidString }, "transaction id")
        duplicates(data.transactions, { $0.recurringOccurrenceID }, "recurring occurrence")
        duplicates(data.transactions, { $0.sourceFixedBillOccurrenceID?.uuidString }, "fixed bill payment")
        duplicates(data.transactionCategories, { $0.id.uuidString }, "category id")
        duplicates(data.categoryBudgets, { $0.id.uuidString }, "budget id")
        duplicates(data.financeSettings, { $0.id.uuidString }, "settings id")
        duplicates(data.recurringTransactions, { $0.id.uuidString }, "recurring rule id")
        duplicates(data.creditCards, { $0.id.uuidString }, "card id")
        duplicates(data.creditCardInvoices, { $0.id.uuidString }, "invoice id")
        duplicates(data.creditCardInvoices, { $0.invoiceIdentifier }, "invoice identifier")
        duplicates(data.fixedBills, { $0.id.uuidString }, "fixed bill id")
        duplicates(data.fixedBillOccurrences, { $0.id.uuidString }, "bill occurrence id")
        duplicates(data.fixedBillOccurrences, { $0.occurrenceIdentifier }, "bill occurrence identifier")
        duplicates(data.habits, { $0.id.uuidString }, "habit id")
        duplicates(data.habitScheduleVersions, { $0.id.uuidString }, "schedule version id")
        duplicates(data.habitCompletions, { $0.id.uuidString }, "completion id")
        duplicates(data.habitCompletions, { $0.completionKey }, "completion")

        let categories = Dictionary(data.transactionCategories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let cards = Set(data.creditCards.map(\.id))
        let invoices = Dictionary(data.creditCardInvoices.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let bills = Set(data.fixedBills.map(\.id))
        let transactions = Set(data.transactions.map(\.id))
        let habits = Set(data.habits.map(\.id))

        for category in data.transactionCategories {
            require(TransactionCategoryType(rawValue: category.type) != nil, "category \(category.id) has an invalid type")
        }
        for budget in data.categoryBudgets {
            require(categories[budget.categoryID] != nil, "budget \(budget.id) points to a missing category")
            require(budget.monthlyLimit.value >= 0, "budget \(budget.id) is negative")
        }
        for settings in data.financeSettings {
            require(settings.monthlySpendingBudget.value >= 0, "cycle budget is negative")
        }
        for card in data.creditCards {
            require(card.creditLimit.value >= 0, "card \(card.id) has a negative limit")
            require((1...31).contains(card.closingDay) && (1...31).contains(card.dueDay), "card \(card.id) has invalid days")
        }
        for invoice in data.creditCardInvoices {
            require(cards.contains(invoice.creditCardID), "invoice \(invoice.id) points to a missing card")
            require(CreditCardInvoiceStatus(rawValue: invoice.status) != nil, "invoice \(invoice.id) has an invalid status")
        }
        for rule in data.recurringTransactions {
            require(categories[rule.categoryID] != nil, "recurring rule \(rule.id) points to a missing category")
            require(rule.creditCardID.map(cards.contains) ?? true, "recurring rule \(rule.id) points to a missing card")
            require(TransactionType(rawValue: rule.type) != nil, "recurring rule \(rule.id) has an invalid type")
            require(RecurringFrequency(rawValue: rule.frequency) != nil, "recurring rule \(rule.id) has an invalid frequency")
            require(rule.paymentMethodRawValue.map { PaymentMethod(rawValue: $0) != nil } ?? true, "recurring rule \(rule.id) has an invalid payment method")
            require(rule.amount.value >= 0, "recurring rule \(rule.id) is negative")
        }
        for bill in data.fixedBills {
            require(categories[bill.categoryID] != nil, "fixed bill \(bill.id) points to a missing category")
            require(FixedBillAmountMode(rawValue: bill.amountMode) != nil, "fixed bill \(bill.id) has an invalid amount type")
            require(PaymentMethod(rawValue: bill.defaultPaymentMethodRawValue) != nil, "fixed bill \(bill.id) has an invalid payment method")
            require((bill.estimatedAmount?.value ?? 0) >= 0, "fixed bill \(bill.id) is negative")
        }
        for occurrence in data.fixedBillOccurrences {
            require(bills.contains(occurrence.fixedBillID), "bill occurrence \(occurrence.id) points to a missing fixed bill")
            require(FixedBillOccurrenceStatus(rawValue: occurrence.status) != nil, "bill occurrence \(occurrence.id) has an invalid status")
            require(occurrence.generatedTransactionID.map(transactions.contains) ?? true, "bill occurrence \(occurrence.id) points to a missing payment")
            require(occurrence.paymentMethodRawValue.map { PaymentMethod(rawValue: $0) != nil } ?? true, "bill occurrence \(occurrence.id) has an invalid payment method")
            require((occurrence.actualAmount?.value ?? 0) >= 0, "bill occurrence \(occurrence.id) is negative")
        }
        if data.transactions.contains(where: { $0.categoryID == nil }) {
            require(!data.transactionCategories.isEmpty, "transactions without a category need at least one category")
        }
        for transaction in data.transactions {
            require(TransactionType(rawValue: transaction.type) != nil, "transaction \(transaction.id) has an invalid type")
            require(transaction.categoryID.map { categories[$0] != nil } ?? true, "transaction \(transaction.id) points to a missing category")
            require(transaction.paymentMethodRawValue.map { PaymentMethod(rawValue: $0) != nil } ?? true, "transaction \(transaction.id) has an invalid payment method")
            require(transaction.creditCardID.map(cards.contains) ?? true, "transaction \(transaction.id) points to a missing card")
            require(transaction.amount.value >= 0, "transaction \(transaction.id) is negative")
            if let invoiceID = transaction.creditCardInvoiceID {
                let invoice = invoices[invoiceID]
                require(invoice != nil, "transaction \(transaction.id) points to a missing invoice")
                require(invoice == nil || invoice?.creditCardID == transaction.creditCardID, "transaction \(transaction.id) is on another card's invoice")
            }
        }
        // Installment groups: one total, numbers unique and within it.
        for (purchaseID, group) in Dictionary(grouping: data.transactions.filter { $0.sourcePurchaseID != nil }, by: { $0.sourcePurchaseID! }) {
            let totals = Set(group.compactMap(\.totalInstallments))
            let numbers = group.compactMap(\.installmentNumber)
            require(totals.count <= 1, "purchase \(purchaseID) has inconsistent installment totals")
            require(Set(numbers).count == numbers.count, "purchase \(purchaseID) repeats an installment")
            if let total = totals.first {
                require(numbers.allSatisfy { (1...total).contains($0) }, "purchase \(purchaseID) has an installment out of range")
                require(group.count <= total, "purchase \(purchaseID) has more installments than its total")
            }
        }
        for habit in data.habits {
            require(HabitScheduleType(rawValue: habit.scheduleTypeRawValue) != nil, "habit \(habit.id) has an invalid schedule")
            require(HabitSchedule.decode(habit.weekdaysRawValue).count == habit.weekdaysRawValue.split(separator: ",").count, "habit \(habit.id) has invalid weekdays")
        }
        for version in data.habitScheduleVersions {
            require(habits.contains(version.habitID), "schedule version \(version.id) points to a missing habit")
            require(HabitScheduleType(rawValue: version.scheduleTypeRawValue) != nil, "schedule version \(version.id) has an invalid schedule")
        }
        for completion in data.habitCompletions {
            require(habits.contains(completion.habitID), "completion \(completion.id) points to a missing habit")
            require(completion.completionKey.hasPrefix(completion.habitID.uuidString + "|"), "completion \(completion.id) belongs to another habit")
        }
        return problems
    }
}

/// Replaces all app data with a backup, safely.
///
/// 1. The backup is validated, then written to a separate temporary store,
///    saved, reopened and re-exported: it must equal the backup exactly.
/// 2. The current data is exported to a JSON safety copy on the device.
/// 3. Every record is deleted and the backup inserted in one context and
///    committed with a single `save()` — one SQLite transaction, so an error
///    or the app being killed mid-way leaves the previous data in place.
/// 4. The live store is re-exported and compared with the backup. If it does
///    not match, the safety copy is put back the same way.
@MainActor
enum BackupRestorer {
    struct Result {
        let counts: BackupCounts
        let safetyCopyURL: URL?
    }

    static var safetyDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "LifeTracker Backups", directoryHint: .isDirectory)
    }

    /// Step 1: proves the backup persists and reads back identically.
    static func stage(_ backup: LifeTrackerBackup) throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "LifeTrackerRestoreStaging-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appending(path: "staging.store")
            try autoreleasepool {
                let context = ModelContext(try LifeTrackerPersistence.makeContainer(storeURL: url))
                try BackupImporter.insert(backup.data, into: context)
                try context.save()
            }
            let reopened = ModelContext(try LifeTrackerPersistence.makeContainer(storeURL: url))
            guard try BackupExporter.dataset(from: reopened) == backup.data.canonical else {
                throw BackupError.stagingFailed
            }
        } catch {
            throw BackupError.stagingFailed
        }
    }

    static func restore(
        _ backup: LifeTrackerBackup,
        into context: ModelContext,
        safetyDirectory: URL? = nil,
        now: Date = .now,
        beforeCommit: (() throws -> Void)? = nil
    ) throws -> Result {
        let problems = BackupValidator.problems(in: backup.data)
        guard problems.isEmpty else { throw BackupError.invalid(problems) }
        try stage(backup)

        let previous = try BackupExporter.makeBackup(from: context, now: now)
        let safetyCopyURL = try? writeSafetyCopy(previous, to: safetyDirectory ?? Self.safetyDirectory, now: now)

        do {
            try replaceAll(with: backup.data, in: context, beforeCommit: beforeCommit)
        } catch {
            context.rollback()
            throw BackupError.applyFailed
        }

        guard (try? BackupExporter.dataset(from: context)) == backup.data.canonical else {
            try? replaceAll(with: previous.data, in: context, beforeCommit: nil)
            throw BackupError.verificationFailed
        }
        return Result(counts: backup.data.counts, safetyCopyURL: safetyCopyURL)
    }

    /// Deletes everything and inserts `data`, committed as one save.
    static func replaceAll(with data: BackupDataset, in context: ModelContext, beforeCommit: (() throws -> Void)?) throws {
        try context.fetch(FetchDescriptor<HabitCompletion>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<HabitScheduleVersion>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<Habit>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<FixedBillOccurrence>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<Transaction>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<CreditCardInvoice>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<FixedBill>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<RecurringTransaction>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<CategoryBudget>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<FinanceSettings>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<CreditCard>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<TransactionCategory>()).forEach(context.delete)
        try BackupImporter.insert(data, into: context)
        try beforeCommit?()
        try context.save()
    }

    /// Keeps the three most recent pre-restore copies.
    static func writeSafetyCopy(_ backup: LifeTrackerBackup, to directory: URL, now: Date) throws -> URL {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "PreRestore_" + BackupExporter.fileName(for: now))
        try BackupExporter.encode(backup).write(to: url, options: [.atomic, .completeFileProtection])
        let copies = (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for old in copies.filter({ $0.lastPathComponent.hasPrefix("PreRestore_") }).sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).dropFirst(3) {
            try? manager.removeItem(at: old)
        }
        return url
    }
}

/// Writes an export to a temporary, protected file for the share sheet.
@MainActor
enum BackupFileExporter {
    static var directory: URL {
        FileManager.default.temporaryDirectory.appending(path: "LifeTrackerBackupExports", directoryHint: .isDirectory)
    }

    static func export(from context: ModelContext, now: Date = .now) throws -> URL {
        let backup = try BackupExporter.makeBackup(from: context, now: now)
        let data = try BackupExporter.encode(backup)
        // Prove the file reads back as the same, valid backup before offering it.
        let decoded = try BackupValidator.load(data)
        guard decoded.data == backup.data, decoded.data.counts.total == backup.data.counts.total else {
            throw BackupError.corrupted
        }
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: BackupExporter.fileName(for: now))
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    static func discard(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
