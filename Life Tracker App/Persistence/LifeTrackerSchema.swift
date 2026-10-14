import Foundation
import SwiftData

// How to change a persisted model
//
// V1 references the live model classes because it is the current shape.
// Before the first change that alters the stored shape:
//
// 1. Copy every current @Model definition into `LifeTrackerSchemaV1` as nested
//    types, so V1 stays frozen exactly as it is stored on devices today.
// 2. Create `LifeTrackerSchemaV2` (version 2.0.0) listing the live classes,
//    then change the live classes.
// 3. Add a `MigrationStage` from V1 to V2 (`.lightweight` for additive or
//    optional changes, `.custom` when values must be transformed).
// 4. Append V2 to `LifeTrackerMigrationPlan.schemas` and the stage to `stages`,
//    and point `LifeTrackerPersistence.currentSchema` at V2.
// 5. Add a test that writes a V1 store to disk, reopens it with the plan and
//    checks the migrated values (see `PersistenceTests`).
//
// Never ship a model change without a new version: a store whose shape matches
// no listed schema fails to open.

enum LifeTrackerSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

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
        [LifeTrackerSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

/// Single source of truth for the schema and container used by the app,
/// previews and tests.
enum LifeTrackerPersistence {
    static let currentSchema: any VersionedSchema.Type = LifeTrackerSchemaV1.self

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
