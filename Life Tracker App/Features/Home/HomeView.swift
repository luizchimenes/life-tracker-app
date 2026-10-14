import SwiftData
import SwiftUI

struct HomeView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var settingsRecords: [FinanceSettings]
    @Query private var recurringTransactions: [RecurringTransaction]
    @Query private var fixedBillOccurrences: [FixedBillOccurrence]
    @Query private var creditCardInvoices: [CreditCardInvoice]

    let onSeeFinance: () -> Void

    private var snapshot: MonthlyFinanceSnapshot {
        projection.actual
    }

    private var projection: MonthlyFinanceProjection {
        MonthlyFinanceProjection(
            transactions: transactions,
            recurringTransactions: recurringTransactions,
            fixedBillOccurrences: fixedBillOccurrences
        )
    }

    private var payableInvoices: [CreditCardInvoice] {
        Array(
            CreditCardInvoicePaymentService.payableInvoices(
                creditCardInvoices,
                transactions: transactions
            )
            .prefix(3)
        )
    }

    private var pendingBills: [FixedBillOccurrence] {
        Array(
            FixedBillCycleSnapshot(occurrences: fixedBillOccurrences)
                .pendingOccurrences
                .prefix(max(3 - payableInvoices.count, 0))
        )
    }

    private var recentTransactions: [Transaction] {
        TransactionActivity.recent(from: transactions, limit: 3)
    }

    private var monthlyBudget: Decimal? {
        guard let budget = settingsRecords.first?.monthlySpendingBudget,
              budget > 0 else {
            return nil
        }

        return budget
    }

    init(onSeeFinance: @escaping () -> Void = {}) {
        self.onSeeFinance = onSeeFinance
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Finance This Cycle")
                            .font(.title2.bold())

                        Spacer()

                        Button("See Finance", action: onSeeFinance)
                    }

                    HomeFinanceSummaryView(
                        balance: snapshot.balance,
                        expenses: snapshot.expenses,
                        projectedExpenses: projection.projectedExpenses,
                        monthlyBudget: monthlyBudget
                    )

                    if !pendingBills.isEmpty || !payableInvoices.isEmpty {
                        Text("Bills to Pay")
                            .font(.headline)

                        VStack(spacing: 0) {
                            ForEach(payableInvoices) { invoice in
                                HomeInvoiceBillRow(invoice: invoice)
                                    .padding()

                                if invoice.id != payableInvoices.last?.id || !pendingBills.isEmpty {
                                    Divider()
                                }
                            }

                            ForEach(pendingBills) { occurrence in
                                HomeFixedBillRow(occurrence: occurrence)
                                    .padding()

                                if occurrence.id != pendingBills.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .background(.background.secondary, in: .rect(cornerRadius: 16))
                    }

                    Text("Recent Activity")
                        .font(.headline)

                    if recentTransactions.isEmpty {
                        Text("No transactions yet")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(.background.secondary, in: .rect(cornerRadius: 16))
                    } else {
                        VStack(spacing: 0) {
                            ForEach(recentTransactions) { transaction in
                                TransactionRow(transaction: transaction)
                                    .padding()

                                if transaction.id != recentTransactions.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .background(.background.secondary, in: .rect(cornerRadius: 16))
                    }

                    Text("Today")
                        .font(.title2.bold())

                    PlaceholderCard(title: "Today's habits", value: "No habits scheduled", systemImage: "checkmark.circle", tint: .blue)
                    PlaceholderCard(title: "Today's tasks", value: "No tasks scheduled", systemImage: "list.bullet", tint: .orange)
                }
                .padding()
            }
            .navigationTitle("Home")
        }
    }
}

#Preview {
    HomeView()
        .modelContainer(LifeTrackerPersistence.previewContainer())
}
