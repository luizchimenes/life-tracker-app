import Foundation
import SwiftData

// How to change a persisted model
//
// The newest schema references the live model classes. Older schemas are
// frozen copies of what is stored on devices (see LifeTrackerSchemaV1.swift).
// Before a change that alters the stored shape:
//
// 1. Copy every current @Model definition into a new frozen file for the
//    current version (e.g. LifeTrackerSchemaV2.swift), nested in its enum.
// 2. Create the next schema (e.g. LifeTrackerSchemaV3) listing the live
//    classes, then change the live classes.
// 3. Add a `MigrationStage` (`.lightweight` for additive or optional changes,
//    `.custom` when values must be transformed).
// 4. Append the schema and stage to `LifeTrackerMigrationPlan` and point
//    `LifeTrackerPersistence.currentSchema` at the new schema.
// 5. Add a test that writes a store with the previous schema, reopens it with
//    the plan and checks the migrated values (see `PersistenceTests`).
//
// Never ship a model change without a new version: a store whose shape matches
// no listed schema fails to open.

/// V2 adds a payment method and an optional credit card to recurring rules
/// so subscriptions can be charged to a card. Both are optional, so V1 rules
/// migrate unchanged and keep generating as Debit.
enum LifeTrackerSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Transaction.self,
            TransactionCategory.self,
            CategoryBudget.self,
            FinanceSettings.self,
            RecurringTransaction.self,
            CreditCard.self,
            CreditCardInvoice.self,
            FixedBill.self,
            FixedBillOccurrence.self
        ]
    }
}

enum LifeTrackerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [LifeTrackerSchemaV1.self, LifeTrackerSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: LifeTrackerSchemaV1.self,
        toVersion: LifeTrackerSchemaV2.self
    )
}

/// Single source of truth for the schema and container used by the app,
/// previews and tests.
enum LifeTrackerPersistence {
    static let currentSchema: any VersionedSchema.Type = LifeTrackerSchemaV2.self

    static var schema: Schema {
        Schema(versionedSchema: currentSchema)
    }

    /// The on-disk store keeps the default location used before versioning
    /// (Application Support/default.store), so existing data is reopened.
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: LifeTrackerMigrationPlan.self,
            configurations: [configuration]
        )
    }

    static func makeContainer(storeURL: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        return try ModelContainer(
            for: schema,
            migrationPlan: LifeTrackerMigrationPlan.self,
            configurations: [configuration]
        )
    }

    /// In-memory container for SwiftUI previews.
    static func previewContainer() -> ModelContainer {
        do {
            return try makeContainer(inMemory: true)
        } catch {
            fatalError("Preview container failed: \(error)")
        }
    }
}
