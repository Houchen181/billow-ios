import SwiftData
import SwiftUI

struct ActivityView: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncEngine.self) private var sync
    @Query(sort: \Charge.date, order: .reverse) private var allCharges: [Charge]
    @Query private var accounts: [BankAccount]

    @State private var search = ""
    @State private var category: SpendCategory?
    @State private var card: String?
    @State private var selected: Charge?

    init(category: SpendCategory? = nil, card: String? = nil) {
        _category = State(initialValue: category)
        _card = State(initialValue: card)
    }

    private var filtered: [Charge] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        return visibleCharges(allCharges, accounts: accounts).filter { charge in
            if let category, charge.category != category { return false }
            if let card, charge.cardName != card { return false }
            if needle.isEmpty { return true }
            return "\(charge.merchant) \(charge.rawName) \(charge.cardName) \(charge.note)"
                .lowercased().contains(needle)
        }
    }

    var body: some View {
        let list = filtered
        let groups = Dictionary(grouping: list) { Day.start($0.date) }
            .sorted { $0.key > $1.key }
        let cardNames = Array(Set(allCharges.map(\.cardName))).sorted()

        List {
            ForEach(groups, id: \.key) { group in
                Section {
                    ForEach(group.value) { charge in
                        Button { selected = charge } label: { ChargeRow(charge: charge) }
                            .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Text(Day.label(group.key))
                        Spacer()
                        Text(Money.string(spendingTotal(group.value))).monospacedDigit()
                    }
                }
            }
        }
        .overlay {
            if list.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .navigationTitle(category?.title ?? card ?? "Activity")
        .searchable(text: $search, prompt: "Merchant, card or note")
        .refreshable { await sync.syncAll(context: context, refresh: true) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Category", selection: $category) {
                        Text("All categories").tag(SpendCategory?.none)
                        ForEach(SpendCategory.allCases) { c in
                            Label(c.title, systemImage: c.symbol).tag(SpendCategory?.some(c))
                        }
                    }
                    Picker("Card", selection: $card) {
                        Text("All cards").tag(String?.none)
                        ForEach(cardNames, id: \.self) { name in
                            Text(name).tag(String?.some(name))
                        }
                    }
                } label: {
                    Image(systemName: category == nil && card == nil
                          ? "line.3.horizontal.decrease.circle"
                          : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityLabel("Filter")
            }
        }
        .sheet(item: $selected) { charge in
            ChargeDetailView(charge: charge)
        }
    }
}

struct ChargeDetailView: View {
    @Bindable var charge: Charge
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 12) {
                            CategoryIcon(category: charge.category, size: 40)
                            VStack(alignment: .leading) {
                                Text(charge.merchant).font(.headline)
                                Text(charge.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        Text(Money.string(charge.amountCents, currency: charge.currency))
                            .font(.system(size: 34, weight: .bold))
                            .padding(.top, 6)
                        if charge.pending {
                            Label("Pending — the final amount may still change", systemImage: "clock")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Category") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                        ForEach(SpendCategory.allCases) { option in
                            Button { choose(option) } label: {
                                HStack(spacing: 8) {
                                    CategoryIcon(category: option, size: 24)
                                    Text(option.title).font(.footnote).lineLimit(1)
                                    Spacer(minLength: 0)
                                    if charge.category == option {
                                        Image(systemName: "checkmark").font(.footnote.weight(.bold))
                                    }
                                }
                                .padding(8)
                                .background(charge.category == option ? Color.accentColor.opacity(0.12) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Note") {
                    TextField("Add a note", text: $charge.note, axis: .vertical)
                }

                Section("Details") {
                    LabeledContent("Card", value: charge.cardName)
                    if charge.rawName != charge.merchant {
                        LabeledContent("Bank description", value: charge.rawName)
                    }
                    LabeledContent("Source", value: sourceLabel)
                }

                if charge.source != "plaid" {
                    Section {
                        Button("Delete charge", role: .destructive) {
                            context.delete(charge)
                            try? context.save()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Charge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }

    private var sourceLabel: String {
        switch charge.source {
        case "plaid": "Bank sync (Plaid)"
        case "tap": "Apple Pay tap"
        case "demo": "Demo data"
        default: charge.source
        }
    }

    private func choose(_ option: SpendCategory) {
        charge.category = option
        charge.userCategorized = true
        CategoryMemory.remember(option, for: charge.merchant)
        try? context.save()
    }
}
