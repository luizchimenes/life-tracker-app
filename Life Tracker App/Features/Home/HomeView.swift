import SwiftData
import SwiftUI

struct HomeView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var recurringTransactions: [RecurringTransaction]
    @Query private var fixedBillOccurrences: [FixedBillOccurrence]
    @Query private var creditCardInvoices: [CreditCardInvoice]
    @Query(sort: \Habit.sortOrder) private var habits: [Habit]

    @AppStorage(HomeLayout.orderKey) private var storedOrder = ""
    @AppStorage(HomeLayout.hiddenKey) private var storedHidden = ""
    @State private var showsCustomization = false

    let onSeeFinance: () -> Void
    let onSeeHabits: () -> Void

    private var overview: FinanceOverview {
        FinanceOverview(
            transactions: transactions,
            recurringTransactions: recurringTransactions,
            fixedBillOccurrences: fixedBillOccurrences,
            creditCardInvoices: creditCardInvoices
        )
    }

    private var layout: HomeLayout {
        HomeLayout(storedOrder: storedOrder, storedHidden: storedHidden)
    }

    private var recentTransactions: [Transaction] {
        TransactionActivity.recent(from: transactions, limit: 3)
    }

    init(onSeeFinance: @escaping () -> Void = {}, onSeeHabits: @escaping () -> Void = {}) {
        self.onSeeFinance = onSeeFinance
        self.onSeeHabits = onSeeHabits
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                let sections = layout.visibleSections
                if sections.isEmpty {
                    ContentUnavailableView {
                        Label("No sections visible", systemImage: "rectangle.stack")
                    } description: {
                        Text("Your data is still in its tabs. Choose what to show on Home.")
                    } actions: {
                        Button("Customize Home") { showsCustomization = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 48)
                } else {
                    let overview = self.overview
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(sections) { section in
                            content(for: section, overview: overview)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Customize Home", systemImage: "slider.horizontal.3") {
                        showsCustomization = true
                    }
                }
            }
            .sheet(isPresented: $showsCustomization) {
                HomeCustomizationView()
            }
        }
    }

    @ViewBuilder
    private func content(for section: HomeSection, overview: FinanceOverview) -> some View {
        switch section {
        case .finance:
            header(for: section) {
                Button("See Finance", action: onSeeFinance)
            }
            HomeFinanceSummaryView(overview: overview)

        case .billsToPay:
            let bills = overview.bills
            if bills.pendingCount > 0 || !bills.upcomingInvoices.isEmpty {
                header(for: section)
                Button(action: onSeeFinance) {
                    HomeBillsSummaryView(bills: bills)
                }
                .buttonStyle(.plain)
            }

        case .recentActivity:
            header(for: section)
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

        case .habits:
            header(for: section)
            HomeHabitsSummaryView(summary: HabitsTodaySummary(habits: habits), onSeeHabits: onSeeHabits)
        }
    }

    /// Section title; touch and hold it to hide the section or customize Home.
    private func header(for section: HomeSection, @ViewBuilder trailing: () -> some View = { EmptyView() }) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(section.title)
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
                .contextMenu {
                    Button("Hide from Home", systemImage: "eye.slash") {
                        var layout = self.layout
                        layout.setVisible(false, for: section)
                        storedHidden = layout.storedHidden
                    }
                    Button("Customize Home", systemImage: "slider.horizontal.3") {
                        showsCustomization = true
                    }
                }

            Spacer()

            trailing()
        }
        .padding(.top, 4)
    }
}

#Preview {
    HomeView()
        .modelContainer(LifeTrackerPersistence.previewContainer())
}
