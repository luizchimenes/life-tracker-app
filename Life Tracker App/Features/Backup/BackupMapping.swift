import Foundation
import SwiftData

/// Reads every persisted record into backup DTOs. Read-only.
@MainActor
enum BackupExporter {
    static func makeBackup(
        from context: ModelContext,
        preferences: BackupPreferences? = nil,
        now: Date = .now
    ) throws -> LifeTrackerBackup {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return LifeTrackerBackup(
            format: LifeTrackerBackup.formatIdentifier,
            backupVersion: LifeTrackerBackup.currentVersion,
            createdAt: formatter.string(from: now),
            appSchemaVersion: LifeTrackerPersistence.currentSchema.versionIdentifier.description,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            preferences: preferences ?? BackupPreferences(appLanguage: UserDefaults.standard.string(forKey: AppLanguage.storageKey)),
            data: try dataset(from: context)
        )
    }

    static func dataset(from context: ModelContext) throws -> BackupDataset {
        BackupDataset(
            transactions: try context.fetch(FetchDescriptor<Transaction>()).map {
                BackupTransaction(
                    id: $0.id,
                    title: $0.title,
                    amount: BackupDecimal($0.amount),
                    date: $0.date,
                    type: $0.type.rawValue,
                    categoryID: $0.category?.id,
                    notes: $0.notes,
                    sourceRecurringTransactionID: $0.sourceRecurringTransactionID,
                    recurringOccurrenceID: $0.recurringOccurrenceID,
                    paymentMethodRawValue: $0.paymentMethodRawValue,
                    creditCardID: $0.creditCard?.id,
                    creditCardInvoiceID: $0.creditCardInvoice?.id,
                    installmentNumber: $0.installmentNumber,
                    totalInstallments: $0.totalInstallments,
                    sourcePurchaseID: $0.sourcePurchaseID,
                    sourceFixedBillOccurrenceID: $0.sourceFixedBillOccurrenceID,
                    financialCycleOverrideStartDate: $0.financialCycleOverrideStartDate
                )
            },
            transactionCategories: try context.fetch(FetchDescriptor<TransactionCategory>()).map {
                BackupTransactionCategory(id: $0.id, name: $0.name, iconName: $0.iconName, colorName: $0.colorName, type: $0.type.rawValue, isDefault: $0.isDefault)
            },
            categoryBudgets: try context.fetch(FetchDescriptor<CategoryBudget>()).map {
                BackupCategoryBudget(id: $0.id, categoryID: $0.category.id, monthlyLimit: BackupDecimal($0.monthlyLimit))
            },
            financeSettings: try context.fetch(FetchDescriptor<FinanceSettings>()).map {
                BackupFinanceSettings(id: $0.id, monthlySpendingBudget: BackupDecimal($0.monthlySpendingBudget))
            },
            recurringTransactions: try context.fetch(FetchDescriptor<RecurringTransaction>()).map {
                BackupRecurringTransaction(
                    id: $0.id, title: $0.title, amount: BackupDecimal($0.amount), type: $0.type.rawValue,
                    categoryID: $0.category.id, notes: $0.notes, startDate: $0.startDate, frequency: $0.frequency.rawValue,
                    dayOfMonth: $0.dayOfMonth, isActive: $0.isActive, lastGeneratedDate: $0.lastGeneratedDate,
                    paymentMethodRawValue: $0.paymentMethodRawValue, creditCardID: $0.creditCard?.id
                )
            },
            creditCards: try context.fetch(FetchDescriptor<CreditCard>()).map {
                BackupCreditCard(
                    id: $0.id, name: $0.name, lastFourDigits: $0.lastFourDigits, closingDay: $0.closingDay, dueDay: $0.dueDay,
                    creditLimit: BackupDecimal($0.creditLimit), isActive: $0.isActive, colorName: $0.colorName
                )
            },
            creditCardInvoices: try context.fetch(FetchDescriptor<CreditCardInvoice>()).map {
                BackupCreditCardInvoice(
                    id: $0.id, invoiceIdentifier: $0.invoiceIdentifier, creditCardID: $0.creditCard.id,
                    referenceMonth: $0.referenceMonth, closingDate: $0.closingDate, dueDate: $0.dueDate,
                    status: $0.status.rawValue, paidDate: $0.paidDate
                )
            },
            fixedBills: try context.fetch(FetchDescriptor<FixedBill>()).map {
                BackupFixedBill(
                    id: $0.id, name: $0.name, categoryID: $0.category.id, dueDay: $0.dueDay,
                    estimatedAmount: $0.estimatedAmount.map(BackupDecimal.init), amountMode: $0.amountMode.rawValue,
                    defaultPaymentMethodRawValue: $0.defaultPaymentMethodRawValue, startDate: $0.startDate,
                    isActive: $0.isActive, notes: $0.notes, createdAt: $0.createdAt
                )
            },
            fixedBillOccurrences: try context.fetch(FetchDescriptor<FixedBillOccurrence>()).map {
                BackupFixedBillOccurrence(
                    id: $0.id, occurrenceIdentifier: $0.occurrenceIdentifier, fixedBillID: $0.fixedBill.id,
                    dueDate: $0.dueDate, financialCycleIdentifier: $0.financialCycleIdentifier, status: $0.status.rawValue,
                    actualAmount: $0.actualAmount.map(BackupDecimal.init), paidDate: $0.paidDate,
                    paymentMethodRawValue: $0.paymentMethodRawValue, generatedTransactionID: $0.generatedTransactionID
                )
            },
            habits: try context.fetch(FetchDescriptor<Habit>()).map {
                BackupHabit(
                    id: $0.id, name: $0.name, notes: $0.notes, iconName: $0.iconName, colorName: $0.colorName,
                    createdAt: $0.createdAt, startDate: $0.startDate, isArchived: $0.isArchived, archivedAt: $0.archivedAt,
                    sortOrder: $0.sortOrder, scheduleTypeRawValue: $0.scheduleTypeRawValue, weekdaysRawValue: $0.weekdaysRawValue
                )
            },
            habitScheduleVersions: try context.fetch(FetchDescriptor<HabitScheduleVersion>()).compactMap { version in
                version.habit.map {
                    BackupHabitScheduleVersion(
                        id: version.id, habitID: $0.id, effectiveFrom: version.effectiveFrom,
                        scheduleTypeRawValue: version.scheduleTypeRawValue, weekdaysRawValue: version.weekdaysRawValue
                    )
                }
            },
            habitCompletions: try context.fetch(FetchDescriptor<HabitCompletion>()).compactMap { completion in
                completion.habit.map {
                    BackupHabitCompletion(id: completion.id, completionKey: completion.completionKey, habitID: $0.id, day: completion.day, createdAt: completion.createdAt)
                }
            }
        )
        .canonical
    }

    static func encode(_ backup: LifeTrackerBackup) throws -> Data {
        try BackupCoding.encoder().encode(backup)
    }

    /// "LifeTracker_Backup_2026-11-01_1930.json"
    static func fileName(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(
            format: "LifeTracker_Backup_%04d-%02d-%02d_%02d%02d.json",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0
        )
    }
}

/// Builds models from a validated dataset, rebuilding relationships from IDs
/// and writing every stored value exactly (initializers that clamp or derive
/// values are overridden right after creation).
@MainActor
enum BackupImporter {
    static func insert(_ data: BackupDataset, into context: ModelContext) throws {
        var categories: [UUID: TransactionCategory] = [:]
        for dto in data.transactionCategories {
            let category = TransactionCategory(id: dto.id, name: dto.name, iconName: dto.iconName, colorName: dto.colorName, type: try value(dto.type), isDefault: dto.isDefault)
            context.insert(category)
            categories[dto.id] = category
        }

        for dto in data.financeSettings {
            context.insert(FinanceSettings(id: dto.id, monthlySpendingBudget: dto.monthlySpendingBudget.value))
        }

        for dto in data.categoryBudgets {
            context.insert(CategoryBudget(id: dto.id, category: try lookup(categories, dto.categoryID), monthlyLimit: dto.monthlyLimit.value))
        }

        var cards: [UUID: CreditCard] = [:]
        for dto in data.creditCards {
            let card = CreditCard(id: dto.id, name: dto.name, lastFourDigits: dto.lastFourDigits, closingDay: dto.closingDay, dueDay: dto.dueDay, creditLimit: dto.creditLimit.value, isActive: dto.isActive, colorName: dto.colorName)
            context.insert(card)
            card.lastFourDigits = dto.lastFourDigits
            card.closingDay = dto.closingDay
            card.dueDay = dto.dueDay
            card.creditLimit = dto.creditLimit.value
            cards[dto.id] = card
        }

        for dto in data.recurringTransactions {
            let rule = RecurringTransaction(
                id: dto.id, title: dto.title, amount: dto.amount.value, type: try value(dto.type),
                category: try lookup(categories, dto.categoryID), notes: dto.notes, startDate: dto.startDate,
                frequency: try value(dto.frequency), dayOfMonth: dto.dayOfMonth, isActive: dto.isActive,
                lastGeneratedDate: dto.lastGeneratedDate
            )
            context.insert(rule)
            rule.dayOfMonth = dto.dayOfMonth
            rule.paymentMethodRawValue = dto.paymentMethodRawValue
            rule.creditCard = try dto.creditCardID.map { try lookup(cards, $0) }
        }

        var invoices: [UUID: CreditCardInvoice] = [:]
        for dto in data.creditCardInvoices {
            let invoice = CreditCardInvoice(
                id: dto.id, invoiceIdentifier: dto.invoiceIdentifier, creditCard: try lookup(cards, dto.creditCardID),
                referenceMonth: dto.referenceMonth, closingDate: dto.closingDate, dueDate: dto.dueDate,
                status: try value(dto.status), paidDate: dto.paidDate
            )
            context.insert(invoice)
            invoices[dto.id] = invoice
        }

        var bills: [UUID: FixedBill] = [:]
        for dto in data.fixedBills {
            let bill = FixedBill(
                id: dto.id, name: dto.name, category: try lookup(categories, dto.categoryID), dueDay: dto.dueDay,
                estimatedAmount: dto.estimatedAmount?.value, amountMode: try value(dto.amountMode),
                startDate: dto.startDate, isActive: dto.isActive, notes: dto.notes, createdAt: dto.createdAt
            )
            context.insert(bill)
            bill.dueDay = dto.dueDay
            bill.estimatedAmount = dto.estimatedAmount?.value
            bill.defaultPaymentMethodRawValue = dto.defaultPaymentMethodRawValue
            bills[dto.id] = bill
        }

        for dto in data.fixedBillOccurrences {
            let occurrence = FixedBillOccurrence(
                id: dto.id, occurrenceIdentifier: dto.occurrenceIdentifier, fixedBill: try lookup(bills, dto.fixedBillID),
                dueDate: dto.dueDate, financialCycleIdentifier: dto.financialCycleIdentifier, status: try value(dto.status),
                actualAmount: dto.actualAmount?.value, paidDate: dto.paidDate, generatedTransactionID: dto.generatedTransactionID
            )
            context.insert(occurrence)
            occurrence.paymentMethodRawValue = dto.paymentMethodRawValue
        }

        let fallbackCategory = categories.values.first
        for dto in data.transactions {
            let category = try dto.categoryID.map { try lookup(categories, $0) }
            guard let placeholder = category ?? fallbackCategory else {
                throw BackupError.missingReference(collection: "transactions", id: dto.id)
            }
            let transaction = Transaction(
                id: dto.id, title: dto.title, amount: dto.amount.value, date: dto.date, type: try value(dto.type),
                category: placeholder, notes: dto.notes, sourceRecurringTransactionID: dto.sourceRecurringTransactionID,
                recurringOccurrenceID: dto.recurringOccurrenceID, creditCard: try dto.creditCardID.map { try lookup(cards, $0) },
                creditCardInvoice: try dto.creditCardInvoiceID.map { try lookup(invoices, $0) },
                installmentNumber: dto.installmentNumber, totalInstallments: dto.totalInstallments,
                sourcePurchaseID: dto.sourcePurchaseID, sourceFixedBillOccurrenceID: dto.sourceFixedBillOccurrenceID,
                financialCycleOverrideStartDate: dto.financialCycleOverrideStartDate
            )
            context.insert(transaction)
            transaction.category = category
            // nil keeps transactions from before payment methods were stored.
            transaction.paymentMethodRawValue = dto.paymentMethodRawValue
        }

        var habits: [UUID: Habit] = [:]
        for dto in data.habits {
            let habit = Habit(
                id: dto.id, name: dto.name, notes: dto.notes, iconName: dto.iconName, colorName: dto.colorName,
                createdAt: dto.createdAt, startDate: dto.startDate, sortOrder: dto.sortOrder, schedule: .everyDay
            )
            context.insert(habit)
            habit.isArchived = dto.isArchived
            habit.archivedAt = dto.archivedAt
            habit.scheduleTypeRawValue = dto.scheduleTypeRawValue
            habit.weekdaysRawValue = dto.weekdaysRawValue
            habits[dto.id] = habit
        }

        for dto in data.habitScheduleVersions {
            let version = HabitScheduleVersion(id: dto.id, habit: try lookup(habits, dto.habitID), effectiveFrom: dto.effectiveFrom, schedule: .everyDay)
            context.insert(version)
            version.scheduleTypeRawValue = dto.scheduleTypeRawValue
            version.weekdaysRawValue = dto.weekdaysRawValue
        }

        for dto in data.habitCompletions {
            let habit = try lookup(habits, dto.habitID)
            let completion = HabitCompletion(id: dto.id, habit: habit, day: HabitDay(dto.day), createdAt: dto.createdAt)
            context.insert(completion)
            completion.completionKey = dto.completionKey
            completion.day = dto.day
        }
    }

    private static func lookup<Model>(_ map: [UUID: Model], _ id: UUID) throws -> Model {
        guard let model = map[id] else { throw BackupError.missingReference(collection: String(describing: Model.self), id: id) }
        return model
    }

    private static func value<Value: RawRepresentable>(_ raw: String) throws -> Value where Value.RawValue == String {
        guard let value = Value(rawValue: raw) else { throw BackupError.invalidValue(field: String(describing: Value.self), value: raw) }
        return value
    }
}
