import Foundation
import SwiftData
import Testing
@testable import Life_Tracker_App

@Suite("Persistence")
@MainActor
struct PersistenceTests {
    private let expectedEntities: Set<String> = [
        "Transaction",
        "TransactionCategory",
        "CategoryBudget",
        "FinanceSettings",
        "RecurringTransaction",
        "CreditCard",
        "CreditCardInvoice",
        "FixedBill",
        "FixedBillOccurrence"
    ]

    @Test func currentSchemaContainsEveryPersistedModel() {
        #expect(Set(LifeTrackerPersistence.schema.entities.map(\.name)) == expectedEntities)
        #expect(LifeTrackerSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(LifeTrackerSchemaV2.versionIdentifier == Schema.Version(2, 0, 0))
        #expect(Set(Schema(versionedSchema: LifeTrackerSchemaV1.self).entities.map(\.name)) == expectedEntities)
    }

    @Test func migrationPlanEndsAtCurrentSchema() throws {
        let latest = try #require(LifeTrackerMigrationPlan.schemas.last)
        #expect(latest.versionIdentifier == LifeTrackerPersistence.currentSchema.versionIdentifier)
        #expect(LifeTrackerMigrationPlan.stages.count == LifeTrackerMigrationPlan.schemas.count - 1)
    }

    @Test func inMemoryContainerUsesMigrationPlan() throws {
        let container = try LifeTrackerPersistence.makeContainer(inMemory: true)
        #expect(Set(container.schema.entities.map(\.name)) == expectedEntities)
        #expect(container.migrationPlan == LifeTrackerMigrationPlan.self)
    }

    @Test func coreModelsAndRelationshipsRoundTrip() throws {
        let context = ModelContext(try LifeTrackerPersistence.makeContainer(inMemory: true))
        Fixture.insert(into: context)
        try context.save()
        try Fixture.verify(ModelContext(context.container))
    }

    /// Before versioning the app opened an unversioned container; later builds
    /// opened it as V1. Both kinds of store must migrate to the current schema
    /// with every model and relationship intact.
    @Test(arguments: [false, true])
    func v1StoreMigratesToCurrentSchema(versioned: Bool) throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "LifeTrackerV1Store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "default.store")

        try autoreleasepool {
            let v1Schema = versioned
                ? Schema(versionedSchema: LifeTrackerSchemaV1.self)
                : Schema(LifeTrackerSchemaV1.models)
            let v1 = try ModelContainer(
                for: v1Schema,
                configurations: [ModelConfiguration(schema: v1Schema, url: storeURL)]
            )
            let context = ModelContext(v1)
            FixtureV1.insert(into: context)
            try context.save()
        }

        let migrated = ModelContext(try LifeTrackerPersistence.makeContainer(storeURL: storeURL))
        try Fixture.verify(migrated)

        // Rules created before V2 keep their previous behavior: Debit, no card.
        let rule = try #require(try migrated.fetch(FetchDescriptor<RecurringTransaction>()).first)
        #expect(rule.paymentMethodRawValue == nil)
        #expect(rule.paymentMethod == .debit)
        #expect(rule.creditCard == nil)

        // Reopening an already migrated store keeps working.
        try Fixture.verify(ModelContext(try LifeTrackerPersistence.makeContainer(storeURL: storeURL)))
    }
}

/// The same data set written with the frozen V1 types, for migration tests.
@MainActor
enum FixtureV1 {
    static func insert(into context: ModelContext) {
        typealias V1 = LifeTrackerSchemaV1
        let food = V1.TransactionCategory(name: "Food", iconName: "fork.knife", colorName: "orange", type: .expense, isDefault: true)
        let card = V1.CreditCard(name: "Card", lastFourDigits: "1234", closingDay: 9, dueDay: 15, creditLimit: 1_000)
        let invoice = V1.CreditCardInvoice(invoiceIdentifier: "card-2026-11", creditCard: card, referenceMonth: .distantPast, closingDate: .distantPast, dueDate: .distantPast)
        let bill = V1.FixedBill(name: "Rent", category: food, dueDay: 10, estimatedAmount: 900, amountMode: .fixed, startDate: .distantPast, createdAt: .distantPast)
        context.insert(food)
        context.insert(card)
        context.insert(invoice)
        context.insert(bill)
        context.insert(V1.Transaction(title: "Lunch", amount: 25, date: .distantPast, type: .expense, category: food, paymentMethodRawValue: PaymentMethod.creditCard.rawValue, creditCard: card, creditCardInvoice: invoice, installmentNumber: 1, totalInstallments: 2))
        context.insert(V1.CategoryBudget(category: food, monthlyLimit: 500))
        context.insert(V1.FinanceSettings(monthlySpendingBudget: 2_000))
        context.insert(V1.RecurringTransaction(title: "Gym", amount: 100, type: .expense, category: food, startDate: .distantPast, dayOfMonth: 5))
        context.insert(V1.FixedBillOccurrence(occurrenceIdentifier: "rent-2026-10", fixedBill: bill, dueDate: .distantPast, financialCycleIdentifier: "2026-10-9"))
    }
}

/// Reusable data set for persistence and future migration tests.
@MainActor
enum Fixture {
    static func insert(into context: ModelContext) {
        let food = TransactionCategory(name: "Food", iconName: "fork.knife", colorName: "orange", type: .expense, isDefault: true)
        let card = CreditCard(name: "Card", lastFourDigits: "1234", closingDay: 9, dueDay: 15, creditLimit: 1_000)
        let invoice = CreditCardInvoice(invoiceIdentifier: "card-2026-11", creditCard: card, referenceMonth: .distantPast, closingDate: .distantPast, dueDate: .distantPast)
        let bill = FixedBill(name: "Rent", category: food, dueDay: 10, estimatedAmount: 900, amountMode: .fixed, startDate: .distantPast, createdAt: .distantPast)
        context.insert(food)
        context.insert(card)
        context.insert(invoice)
        context.insert(bill)
        context.insert(Transaction(title: "Lunch", amount: 25, date: .distantPast, type: .expense, category: food, paymentMethod: .creditCard, creditCard: card, creditCardInvoice: invoice, installmentNumber: 1, totalInstallments: 2))
        context.insert(CategoryBudget(category: food, monthlyLimit: 500))
        context.insert(FinanceSettings(monthlySpendingBudget: 2_000))
        context.insert(RecurringTransaction(title: "Gym", amount: 100, type: .expense, category: food, startDate: .distantPast, dayOfMonth: 5))
        context.insert(FixedBillOccurrence(occurrenceIdentifier: "rent-2026-10", fixedBill: bill, dueDate: .distantPast, financialCycleIdentifier: "2026-10-9"))
    }

    static func verify(_ context: ModelContext) throws {
        let transaction = try #require(try context.fetch(FetchDescriptor<Transaction>()).first)
        #expect(transaction.amount == 25)
        #expect(transaction.paymentMethod == .creditCard)
        #expect(transaction.category?.name == "Food")
        #expect(transaction.creditCard?.name == "Card")
        #expect(transaction.creditCardInvoice?.invoiceIdentifier == "card-2026-11")
        #expect(transaction.totalInstallments == 2)

        let occurrence = try #require(try context.fetch(FetchDescriptor<FixedBillOccurrence>()).first)
        #expect(occurrence.fixedBill.name == "Rent")
        #expect(occurrence.fixedBill.category.name == "Food")
        #expect(occurrence.status == .pending)

        #expect(try context.fetch(FetchDescriptor<CategoryBudget>()).first?.category.name == "Food")
        #expect(try context.fetch(FetchDescriptor<FinanceSettings>()).first?.monthlySpendingBudget == 2_000)
        #expect(try context.fetch(FetchDescriptor<RecurringTransaction>()).first?.category.name == "Food")
        #expect(try context.fetchCount(FetchDescriptor<TransactionCategory>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<CreditCardInvoice>()) == 1)
    }
}
