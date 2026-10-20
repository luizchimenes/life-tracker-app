import Foundation

/// The configured cost of active fixed bills, per cycle.
///
/// A commitment-configuration figure, not spending: it reads the bill rules,
/// never their paid occurrences or generated transactions.
struct FixedBillCommitment {
    /// Active bills with a fixed configured amount.
    let exactCount: Int
    /// Active variable bills with an estimate.
    let estimatedCount: Int
    /// Active bills with no amount; never counted as zero.
    let unknownCount: Int
    /// Sum of exact and estimated amounts.
    let total: Decimal

    var activeCount: Int {
        exactCount + estimatedCount + unknownCount
    }

    var includesEstimates: Bool {
        estimatedCount > 0 || unknownCount > 0
    }

    init(bills: [FixedBill]) {
        let active = bills.filter(\.isActive)
        exactCount = active.count { $0.amountMode == .fixed && $0.estimatedAmount != nil }
        estimatedCount = active.count { $0.amountMode == .variable && $0.estimatedAmount != nil }
        unknownCount = active.count { $0.estimatedAmount == nil }
        total = active.compactMap(\.estimatedAmount).reduce(Decimal.zero, +)
    }
}

/// The configured cost of active recurring expense rules, per cycle.
///
/// Every supported frequency is monthly, which is exactly one occurrence per
/// 9th-to-8th cycle, so each rule counts once. Generated transactions are
/// history and are not read here.
struct RecurringExpenseCommitment {
    let activeCount: Int
    let creditCardCount: Int
    let total: Decimal

    init(rules: [RecurringTransaction]) {
        let active = rules.filter {
            $0.isActive && $0.type == .expense && $0.frequency == .monthly
        }
        activeCount = active.count
        creditCardCount = active.count { $0.paymentMethod == .creditCard }
        total = active.reduce(Decimal.zero) { $0 + $1.amount }
    }
}

/// Fixed bills plus recurring expenses: what is committed every cycle before
/// any variable spending.
struct FixedCommitmentSummary {
    let fixedBills: FixedBillCommitment
    let recurring: RecurringExpenseCommitment

    var total: Decimal {
        fixedBills.total + recurring.total
    }

    var includesEstimates: Bool {
        fixedBills.includesEstimates
    }

    var unknownCount: Int {
        fixedBills.unknownCount
    }

    var isEmpty: Bool {
        fixedBills.activeCount == 0 && recurring.activeCount == 0
    }

    init(bills: [FixedBill], rules: [RecurringTransaction]) {
        fixedBills = FixedBillCommitment(bills: bills)
        recurring = RecurringExpenseCommitment(rules: rules)
    }
}
