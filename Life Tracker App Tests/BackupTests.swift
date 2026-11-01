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

private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
}

private let now = day(2026, 11, 1)

/// A temporary on-disk store, removed when the test ends.
@MainActor
private final class TemporaryStore {
    let directory = FileManager.default.temporaryDirectory.appending(path: "LifeTrackerBackupTest-\(UUID().uuidString)")
    var url: URL { directory.appending(path: "default.store") }
    var safetyDirectory: URL { directory.appending(path: "Safety") }

    init() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func context() throws -> ModelContext {
        ModelContext(try LifeTrackerPersistence.makeContainer(storeURL: url))
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Every kind of record and the tricky cases a restore must keep exactly.
@MainActor
private enum BackupFixture {
    static func populate(_ context: ModelContext) throws {
        let defaults = TransactionCategory.makeDefaults()
        defaults.forEach(context.insert)
        let custom = TransactionCategory(name: "Padaria do Zé", iconName: "fork.knife", colorName: "brown", type: .expense)
        context.insert(custom)
        let food = try #require(defaults.first { $0.name == "Food" })
        let salary = try #require(defaults.first { $0.name == "Salary" })
        let invest = try #require(defaults.first { $0.type == .investment })
        let housing = try #require(defaults.first { $0.name == "Housing" })
        let card = CreditCard(name: "Azul Gold", lastFourDigits: "1234", closingDay: 9, dueDay: 15, creditLimit: Decimal(string: "12500.75")!)
        context.insert(card)
        context.insert(CategoryBudget(category: food, monthlyLimit: Decimal(string: "800.10")!))
        context.insert(FinanceSettings(monthlySpendingBudget: 4_000))
        try context.save()

        func entry(_ title: String, _ amount: String, _ date: Date, _ type: TransactionType, _ category: TransactionCategory, _ method: PaymentMethod = .pix, installments: Int = 1, override: Date? = nil) throws {
            try TransactionEntry(title: title, amount: Decimal(string: amount)!, type: type, category: category, date: date, notes: "nota", paymentMethod: method, creditCard: method == .creditCard ? card : nil, installmentCount: installments, financialCycleOverrideStart: override).save(in: context, calendar: utc)
        }
        try entry("Salário", "5000", day(2026, 10, 9), .income, salary)
        try entry("Tesouro", "2000.01", day(2026, 10, 10), .investment, invest)
        try entry("Pão", "12.35", day(2026, 10, 12), .expense, custom)
        let nextCycle = FinancialCycleAllocation.storedValue(for: FinancialCycle(containing: day(2026, 10, 15), calendar: utc)!, calendar: utc)
        try entry("Notebook", "1000", day(2026, 10, 8), .expense, food, .creditCard, installments: 3, override: nextCycle)

        // A transaction from before payment methods were stored.
        let legacy = Transaction(title: "Antiga", amount: Decimal(string: "0.01")!, date: day(2026, 9, 1), type: .expense, category: food)
        context.insert(legacy)
        legacy.paymentMethodRawValue = nil

        // Netflix on the card, two charges generated, one deleted on purpose.
        let netflix = RecurringTransaction(title: "Netflix", amount: Decimal(string: "59.90")!, type: .expense, category: food, startDate: day(2026, 9, 1), dayOfMonth: 15, paymentMethod: .creditCard, creditCard: card)
        context.insert(netflix)
        try RecurringTransactionGenerator.generateDueTransactions(in: context, through: day(2026, 10, 20), calendar: utc)
        let charges = try context.fetch(FetchDescriptor<Transaction>()).filter { $0.sourceRecurringTransactionID == netflix.id }
        let september = try #require(charges.min { $0.date < $1.date })
        let all = try context.fetch(FetchDescriptor<Transaction>())
        try TransactionDeletionService.delete(try TransactionDeletionService.transactionsForSafeDeletion(of: september, from: all), from: all, in: context)

        // Rent paid, power pending.
        let rent = FixedBill(name: "Aluguel", category: housing, dueDay: 10, estimatedAmount: 1_000, amountMode: .fixed, startDate: day(2026, 10, 1))
        let power = FixedBill(name: "Energia", category: housing, dueDay: 25, estimatedAmount: 180, amountMode: .variable, defaultPaymentMethod: .bankSlip, startDate: day(2026, 10, 1))
        context.insert(rent)
        context.insert(power)
        try FixedBillOccurrenceGenerator.generateRelevantOccurrences(in: context, for: day(2026, 10, 20), calendar: utc)
        let rentOccurrence = try #require(try context.fetch(FetchDescriptor<FixedBillOccurrence>()).first { $0.fixedBill.id == rent.id })
        try FixedBillPaymentService.markPaid(occurrence: rentOccurrence, actualAmount: Decimal(string: "1012.47")!, paidDate: day(2026, 10, 10), paymentMethod: .bankSlip, category: housing, note: "", in: context)

        // Habits: one with a schedule change, one archived.
        let gym = try HabitService.create(name: "Academia", iconName: "dumbbell.fill", colorName: "blue", schedule: HabitSchedule(type: .weekly, weekdays: [2, 4, 6]), startDate: day(2026, 10, 5), in: context, now: day(2026, 10, 5), calendar: utc)
        for value in [5, 7, 9, 12] {
            try HabitService.setCompleted(gym, on: HabitDay(year: 2026, month: 10, day: value), in: context, now: day(2026, 10, 20), calendar: utc)
        }
        try HabitService.update(gym, name: "Academia", notes: "", iconName: "dumbbell.fill", colorName: "blue", schedule: .everyDay, startDate: gym.startDate, in: context, now: day(2026, 10, 19), calendar: utc)
        try HabitService.setCompleted(gym, on: HabitDay(year: 2026, month: 10, day: 20), in: context, now: day(2026, 10, 20), calendar: utc)
        let reading = try HabitService.create(name: "Leitura", iconName: "book.fill", colorName: "green", schedule: .everyDay, startDate: day(2026, 10, 1), in: context, now: day(2026, 10, 1), calendar: utc)
        try HabitService.setCompleted(reading, on: HabitDay(year: 2026, month: 10, day: 2), in: context, now: day(2026, 10, 2), calendar: utc)
        try HabitService.archive(reading, in: context, now: day(2026, 10, 3), calendar: utc)
        try context.save()
    }
}

@MainActor
private func roundTrip(_ source: ModelContext) throws -> LifeTrackerBackup {
    let data = try BackupExporter.encode(try BackupExporter.makeBackup(from: source, preferences: BackupPreferences(appLanguage: "portugueseBrazil"), now: now))
    return try BackupValidator.load(data)
}

@Suite("Backup – export and validation")
@MainActor
struct BackupExportTests {
    @Test func emptyDatasetExportsAndValidates() throws {
        let backup = try roundTrip(try TestStore.context())
        #expect(backup.data == .empty)
        #expect(backup.format == "LifeTrackerBackup")
        #expect(backup.backupVersion == 1)
        #expect(backup.appSchemaVersion == "4.0.0")
        #expect(backup.preferences.appLanguage == "portugueseBrazil")
    }

    @Test func completeExportCoversAllTwelveModelsAndCountsReconcile() throws {
        let context = try TestStore.context()
        try BackupFixture.populate(context)
        let counts = try roundTrip(context).data.counts
        #expect(counts.transactions == (try context.fetchCount(FetchDescriptor<Transaction>())))
        #expect(counts.categories == (try context.fetchCount(FetchDescriptor<TransactionCategory>())))
        #expect(counts.creditCardInvoices == (try context.fetchCount(FetchDescriptor<CreditCardInvoice>())))
        #expect(counts.habitCompletions == (try context.fetchCount(FetchDescriptor<HabitCompletion>())))
        let all = [counts.transactions, counts.categories, counts.categoryBudgets, counts.financeSettings, counts.recurringTransactions, counts.creditCards, counts.creditCardInvoices, counts.fixedBills, counts.fixedBillOccurrences, counts.habits, counts.habitScheduleVersions, counts.habitCompletions]
        #expect(all.allSatisfy { $0 > 0 })
    }

    @Test func moneyRoundTripsExactly() throws {
        let context = try TestStore.context()
        try BackupFixture.populate(context)
        let backup = try roundTrip(context)
        let amounts = Set(backup.data.transactions.map(\.amount.value))
        #expect(amounts.isSuperset(of: [Decimal(string: "0.01")!, Decimal(string: "2000.01")!, Decimal(string: "12.35")!, Decimal(string: "333.33")!, Decimal(string: "333.34")!, Decimal(string: "59.90")!, Decimal(string: "1012.47")!]))
        #expect(backup.data.creditCards.first?.creditLimit.value == Decimal(string: "12500.75")!)
        let json = String(decoding: try BackupExporter.encode(backup), as: UTF8.self)
        #expect(json.contains("\"12500.75\""))
    }

    @Test func exportDoesNotModifyLiveData() throws {
        let context = try TestStore.context()
        try BackupFixture.populate(context)
        let before = try BackupExporter.dataset(from: context)
        _ = try BackupFileExporter.export(from: context, now: now)
        #expect(!context.hasChanges)
        #expect(try BackupExporter.dataset(from: context) == before)
    }

    @Test func rejectsBrokenFiles() throws {
        let context = try TestStore.context()
        try BackupFixture.populate(context)
        let valid = try BackupExporter.encode(try BackupExporter.makeBackup(from: context, now: now))

        #expect(throws: BackupError.corrupted) { try BackupValidator.load(Data("{not json".utf8)) }
        #expect(throws: BackupError.corrupted) { try BackupValidator.load(valid.prefix(valid.count / 2)) }
        #expect(throws: BackupError.notABackup) { try BackupValidator.load(Data(#"{"format":"Other","backupVersion":1}"#.utf8)) }

        var object = try #require(try JSONSerialization.jsonObject(with: valid) as? [String: Any])
        object["backupVersion"] = 2
        #expect(throws: BackupError.unsupportedVersion(2)) { try BackupValidator.load(try JSONSerialization.data(withJSONObject: object)) }
    }

    @Test func rejectsDuplicatesAndBrokenReferences() throws {
        let context = try TestStore.context()
        try BackupFixture.populate(context)
        let backup = try roundTrip(context)

        var duplicateCompletion = backup.data
        duplicateCompletion.habitCompletions.append(duplicateCompletion.habitCompletions[0])
        #expect(!BackupValidator.problems(in: duplicateCompletion).isEmpty)

        var duplicateTransaction = backup.data
        var copy = duplicateTransaction.transactions[0]
        copy.recurringOccurrenceID = nil
        copy.sourceFixedBillOccurrenceID = nil
        duplicateTransaction.transactions.append(copy)
        #expect(BackupValidator.problems(in: duplicateTransaction).contains { $0.contains("duplicate transaction id") })

        var missingCategory = backup.data
        missingCategory.transactions[0].categoryID = UUID()
        #expect(BackupValidator.problems(in: missingCategory).contains { $0.contains("missing category") })

        var missingHabit = backup.data
        missingHabit.habitScheduleVersions[0].habitID = UUID()
        #expect(BackupValidator.problems(in: missingHabit).contains { $0.contains("missing habit") })

        var wrongInvoice = backup.data
        let cardIndex = try #require(wrongInvoice.transactions.firstIndex { $0.creditCardInvoiceID != nil })
        wrongInvoice.transactions[cardIndex].creditCardID = nil
        #expect(BackupValidator.problems(in: wrongInvoice).contains { $0.contains("another card's invoice") })

        var badEnum = backup.data
        badEnum.transactions[0].type = "transfer"
        #expect(!BackupValidator.problems(in: badEnum).isEmpty)

        #expect(BackupValidator.problems(in: backup.data).isEmpty)
    }
}

@Suite("Backup – restore")
@MainActor
struct BackupRestoreTests {
    /// Restores the fixture's backup into a separate on-disk store.
    private func restoredStore() throws -> (source: ModelContext, backup: LifeTrackerBackup, store: TemporaryStore) {
        let source = try TestStore.context()
        try BackupFixture.populate(source)
        let backup = try roundTrip(source)
        let store = try TemporaryStore()
        _ = try BackupRestorer.restore(backup, into: try store.context(), safetyDirectory: store.safetyDirectory, now: now)
        return (source, backup, store)
    }

    @Test func fullRoundTripKeepsEveryRecordAndRelationship() throws {
        let (source, backup, store) = try restoredStore()
        let reopened = try store.context()
        #expect(try BackupExporter.dataset(from: reopened) == (try BackupExporter.dataset(from: source)))
        #expect(backup.data == (try BackupExporter.dataset(from: source)))

        let transactions = try reopened.fetch(FetchDescriptor<Transaction>())
        let notebook = transactions.filter { $0.title == "Notebook" }.sorted { ($0.installmentNumber ?? 0) < ($1.installmentNumber ?? 0) }
        #expect(notebook.count == 3)
        #expect(Set(notebook.compactMap(\.sourcePurchaseID)).count == 1)
        #expect(notebook.allSatisfy { $0.creditCard?.name == "Azul Gold" && $0.creditCardInvoice?.creditCard.id == $0.creditCard?.id })
        #expect(notebook.allSatisfy { $0.financialCycleOverrideStartDate != nil })
        #expect(transactions.first { $0.title == "Tesouro" }?.type == .investment)
        #expect(transactions.first { $0.title == "Antiga" }?.paymentMethodRawValue == nil)
        #expect(transactions.first { $0.title == "Pão" }?.category?.name == "Padaria do Zé")

        let netflixCharges = transactions.filter { $0.title == "Netflix" }
        #expect(netflixCharges.count == 1)
        #expect(netflixCharges.allSatisfy { $0.sourceRecurringTransactionID != nil && $0.recurringOccurrenceID != nil && $0.creditCardInvoice != nil })

        let paidRent = try #require(try reopened.fetch(FetchDescriptor<FixedBillOccurrence>()).first { $0.status == .paid })
        #expect(paidRent.actualAmount == Decimal(string: "1012.47")!)
        #expect(transactions.contains { $0.id == paidRent.generatedTransactionID && $0.sourceFixedBillOccurrenceID == paidRent.id })

        let habits = try reopened.fetch(FetchDescriptor<Habit>())
        let gym = try #require(habits.first { $0.name == "Academia" })
        #expect(gym.scheduleVersions.count == 2)
        #expect(gym.completions.count == 5)
        #expect(habits.first { $0.name == "Leitura" }?.isArchived == true)
    }

    @Test func restorePreservesFinanceTotalsAndHabitStatistics() throws {
        let (source, _, store) = try restoredStore()
        let reopened = try store.context()
        for month in [9, 10, 11] {
            let date = day(2026, month, 20)
            let before = MonthlyFinanceSnapshot(transactions: try source.fetch(FetchDescriptor<Transaction>()), date: date, calendar: utc)
            let after = MonthlyFinanceSnapshot(transactions: try reopened.fetch(FetchDescriptor<Transaction>()), date: date, calendar: utc)
            #expect((after.income, after.expenses, after.investments) == (before.income, before.expenses, before.investments))
        }
        let today = HabitDay(year: 2026, month: 10, day: 21)
        for habit in try source.fetch(FetchDescriptor<Habit>()) {
            let restored = try #require(try reopened.fetch(FetchDescriptor<Habit>()).first { $0.id == habit.id })
            #expect(HabitStatistics(HabitSnapshot(restored, calendar: utc), today: today) == HabitStatistics(HabitSnapshot(habit, calendar: utc), today: today))
        }
    }

    @Test func startupGenerationAfterRestoreCreatesNoDuplicates() throws {
        let (_, backup, store) = try restoredStore()
        let context = try store.context()
        try RecurringTransactionGenerator.generateDueTransactions(in: context, through: day(2026, 10, 20), calendar: utc)
        try FixedBillOccurrenceGenerator.generateRelevantOccurrences(in: context, for: day(2026, 10, 20), calendar: utc)
        try TransactionCategory.seedDefaultsIfNeeded(in: context)
        #expect(try BackupExporter.dataset(from: context) == backup.data)
        // The deliberately deleted September Netflix charge stays deleted.
        #expect(try context.fetch(FetchDescriptor<Transaction>()).count { $0.title == "Netflix" } == 1)
    }

    @Test func failedRestoreKeepsCurrentData() throws {
        let (_, backup, _) = try restoredStore()
        let store = try TemporaryStore()
        let context = try store.context()
        let reading = try HabitService.create(name: "Current", iconName: "book.fill", colorName: "green", schedule: .everyDay, startDate: now, in: context, now: now, calendar: utc)
        context.insert(Transaction(title: "Current data", amount: 99, date: now, type: .expense, category: TransactionCategory(name: "Current", iconName: "x", colorName: "red", type: .expense)))
        try context.save()
        let before = try BackupExporter.dataset(from: context)

        struct Interrupted: Error {}
        #expect(throws: BackupError.applyFailed) {
            _ = try BackupRestorer.restore(backup, into: context, safetyDirectory: store.safetyDirectory, now: now) { throw Interrupted() }
        }
        #expect(try BackupExporter.dataset(from: context) == before)
        #expect(try BackupExporter.dataset(from: try store.context()) == before)
        #expect(reading.name == "Current")

        // An invalid backup is refused before anything happens.
        var broken = backup
        broken.data.transactions[0].categoryID = UUID()
        #expect(throws: BackupError.self) {
            _ = try BackupRestorer.restore(broken, into: context, safetyDirectory: store.safetyDirectory, now: now)
        }
        #expect(try BackupExporter.dataset(from: try store.context()) == before)
    }

    @Test func safetyCopyAllowsRecoveringThePreviousData() throws {
        let (_, backup, _) = try restoredStore()
        let store = try TemporaryStore()
        let context = try store.context()
        context.insert(Transaction(title: "Before restore", amount: 10, date: now, type: .expense, category: TransactionCategory(name: "Mine", iconName: "x", colorName: "red", type: .expense)))
        try context.save()
        let previous = try BackupExporter.dataset(from: context)

        let result = try BackupRestorer.restore(backup, into: context, safetyDirectory: store.safetyDirectory, now: now)
        #expect(result.counts == backup.data.counts)
        let safetyURL = try #require(result.safetyCopyURL)
        let safety = try BackupValidator.load(try Data(contentsOf: safetyURL))
        #expect(safety.data == previous)

        _ = try BackupRestorer.restore(safety, into: context, safetyDirectory: store.safetyDirectory, now: now)
        #expect(try BackupExporter.dataset(from: try store.context()) == previous)
    }

    @Test func pdfExportStillWorksOnRestoredData() throws {
        let (_, _, store) = try restoredStore()
        let context = try store.context()
        let content = try #require(FinancialReportPDFContent.make(
            cycle: FinancialCycle(containing: day(2026, 10, 20), calendar: utc)!,
            transactions: try context.fetch(FetchDescriptor<Transaction>()),
            categoryBudgets: try context.fetch(FetchDescriptor<CategoryBudget>()),
            monthlyBudget: 4_000,
            fixedBillOccurrences: try context.fetch(FetchDescriptor<FixedBillOccurrence>()),
            creditCardInvoices: try context.fetch(FetchDescriptor<CreditCardInvoice>()),
            recurringTransactions: try context.fetch(FetchDescriptor<RecurringTransaction>()),
            generatedAt: day(2026, 10, 20),
            locale: Locale(identifier: "en"),
            calendar: utc
        ))
        #expect(!content.statementTransactionIDs.isEmpty)
        #expect(!FinancialReportPDFDocument(content: content).render().isEmpty)
    }
}
