import SwiftData
import SwiftUI

struct OverviewView: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncEngine.self) private var sync
    @Query(sort: \Charge.date, order: .reverse) private var allCharges: [Charge]
    @Query private var accounts: [BankAccount]

    var body: some View {
        let charges = visibleCharges(allCharges, accounts: accounts)
        let calendar = Calendar.current
        let now = Date.now
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? Day.start(now)
        let thisMonth = charges.filter { $0.date >= monthStart }

        ScrollView {
            VStack(spacing: 14) {
                if charges.isEmpty {
                    EmptyOverview()
                } else {
                    hero(thisMonth: thisMonth, all: charges, monthStart: monthStart)
                    tiles(charges)
                    SectionCard(title: "Daily spending") {
                        DailyChart(charges: charges)
                    }
                    categories(thisMonth)
                    cards(thisMonth)
                    recent(charges)
                }
                footer
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Charges")
        .refreshable { await sync.syncAll(context: context, refresh: true) }
    }

    // MARK: Sections

    private func hero(thisMonth: [Charge], all: [Charge], monthStart: Date) -> some View {
        let calendar = Calendar.current
        let spent = spendingTotal(thisMonth)
        let dayOfMonth = calendar.component(.day, from: .now)
        let daysInMonth = calendar.range(of: .day, in: .month, for: .now)?.count ?? 30
        let pace = dayOfMonth >= 3 ? spent / dayOfMonth * daysInMonth : nil

        // Same point last month, for a like-for-like comparison.
        let lastStart = calendar.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
        let lastCutoff = calendar.date(byAdding: .month, value: -1, to: .now) ?? monthStart
        let lastSoFar = spendingTotal(all.filter { $0.date >= lastStart && $0.date <= lastCutoff })
        let delta = spent - lastSoFar

        return VStack(alignment: .leading, spacing: 6) {
            Text(Date.now.formatted(.dateTime.month(.wide)))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(Money.short(spent))
                .font(.system(size: 44, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            HStack(spacing: 12) {
                if let pace {
                    Label("On pace for \(Money.short(pace))", systemImage: "speedometer")
                }
                if lastSoFar > 0 {
                    Label("\(Money.short(abs(delta))) \(delta > 0 ? "more" : "less") than last month",
                          systemImage: delta > 0 ? "arrow.up.right" : "arrow.down.right")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private func tiles(_ charges: [Charge]) -> some View {
        let calendar = Calendar.current
        let today = spendingTotal(charges.filter { calendar.isDateInToday($0.date) })
        let weekStart = calendar.date(byAdding: .day, value: -6, to: Day.start(.now)) ?? .now
        let week = spendingTotal(charges.filter { $0.date >= weekStart })
        let todayCount = charges.filter { calendar.isDateInToday($0.date) && $0.isSpending }.count
        return HStack(spacing: 10) {
            StatTile(label: "Today", cents: today,
                     hint: "\(todayCount) \(todayCount == 1 ? "purchase" : "purchases")")
            StatTile(label: "Last 7 days", cents: week, hint: "\(Money.short(week / 7))/day")
        }
    }

    private func categories(_ thisMonth: [Charge]) -> some View {
        var sums: [SpendCategory: Int] = [:]
        for charge in thisMonth where charge.isSpending {
            sums[charge.category, default: 0] += charge.amountCents
        }
        let rows = sums.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        let total = max(1, rows.reduce(0) { $0 + $1.value })
        let largest = max(1, rows.first?.value ?? 1)
        return Group {
          if !rows.isEmpty {
            SectionCard(title: "Categories", subtitle: "this month") {
                VStack(spacing: 12) {
                    ForEach(rows, id: \.key) { row in
                        NavigationLink {
                            ActivityView(category: row.key)
                        } label: {
                            CategoryRow(category: row.key, cents: row.value,
                                        fraction: Double(row.value) / Double(largest),
                                        share: Double(row.value) / Double(total))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
          }
        }
    }

    private func cards(_ thisMonth: [Charge]) -> some View {
        var sums: [String: Int] = [:]
        for charge in thisMonth where charge.isSpending {
            sums[charge.cardName, default: 0] += charge.amountCents
        }
        let rows = sums.sorted { $0.value > $1.value }
        return Group {
          if rows.count > 1 {
            SectionCard(title: "Cards", subtitle: "this month") {
                VStack(spacing: 10) {
                    ForEach(rows, id: \.key) { row in
                        NavigationLink {
                            ActivityView(card: row.key)
                        } label: {
                            HStack {
                                Image(systemName: "creditcard").foregroundStyle(.secondary)
                                Text(row.key).font(.subheadline).lineLimit(1)
                                Spacer()
                                Text(Money.short(row.value)).font(.subheadline.weight(.semibold)).monospacedDigit()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
          }
        }
    }

    private func recent(_ charges: [Charge]) -> some View {
        SectionCard(title: "Recent") {
            VStack(spacing: 12) {
                ForEach(charges.prefix(5)) { charge in
                    ChargeRow(charge: charge)
                }
                NavigationLink("See all activity") { ActivityView() }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let error = sync.lastError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if sync.isSyncing {
            HStack(spacing: 8) { ProgressView(); Text("Syncing…") }
                .font(.caption).foregroundStyle(.secondary)
        } else if let last = sync.lastSynced, AppConfig.hasCredentials {
            Text("Synced \(last.formatted(.relative(presentation: .named)))")
                .font(.caption).foregroundStyle(.secondary)
        } else if DemoData.isEnabled {
            Text("Showing demo data — connect a bank in Accounts.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct EmptyOverview: View {
    var body: some View {
        ContentUnavailableView {
            Label("No charges yet", systemImage: "creditcard")
        } description: {
            Text(AppConfig.hasCredentials
                 ? "Link a bank in Accounts. New purchases appear automatically — pull down to check now."
                 : "Connect your banks with your own free Plaid account in Accounts, or turn on demo data.")
        }
        .padding(.top, 60)
    }
}
